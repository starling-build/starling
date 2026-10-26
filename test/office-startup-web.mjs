#!/usr/bin/env node
// Measure first-frame and font-settled startup in a fresh Chrome profile, then
// reload with its cache. No dependencies; uses the same Chrome/CDP as web-drive.
// node test/office-startup-web.mjs --url URL --out /tmp/startup.json
// Optional: --mbps 10 --latency-ms 40 --port 9960
import { spawn } from 'node:child_process';
import { mkdtempSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const options = {};
for (let i = 2; i < process.argv.length; i += 2) options[process.argv[i].replace(/^--/, '')] = process.argv[i + 1];
if (!options.url || !options.out) throw Error('--url and --out are required');
const port = Number(options.port || 9960);
const profile = mkdtempSync(join(tmpdir(), 'starling-startup-'));
const chrome = spawn(process.env.CHROME || (process.platform === 'darwin'
  ? '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' : 'google-chrome'), [
  '--headless=new', '--no-first-run', '--enable-unsafe-swiftshader',
  `--remote-debugging-port=${port}`, `--user-data-dir=${profile}`, '--window-size=1440,1000', 'about:blank',
], {stdio: 'ignore'});
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
let ws, id = 0;
const pending = new Map();
const browserErrors = [];
try {
  let tab;
  for (let attempt = 0; attempt < 100; attempt++) {
    try { tab = (await (await fetch(`http://127.0.0.1:${port}/json/list`)).json()).find(t => t.type === 'page'); } catch {}
    if (tab) break;
    await sleep(100);
  }
  if (!tab) throw Error('Chrome did not start');
  ws = new WebSocket(tab.webSocketDebuggerUrl);
  await new Promise((resolve, reject) => { ws.addEventListener('open', resolve, {once:true}); ws.addEventListener('error', reject, {once:true}); });
  ws.addEventListener('message', ({data}) => {
    const message = JSON.parse(data);
    if (pending.has(message.id)) { pending.get(message.id)(message); pending.delete(message.id); }
    if (message.method === 'Runtime.exceptionThrown') browserErrors.push(message.params.exceptionDetails.text);
  });
  const send = (method, params = {}) => new Promise((resolve, reject) => {
    const request = ++id;
    const timer = setTimeout(() => { pending.delete(request); reject(Error(`Timed out: ${method}`)); }, 30000);
    pending.set(request, message => { clearTimeout(timer); message.error ? reject(Error(message.error.message)) : resolve(message.result); });
    ws.send(JSON.stringify({id:request, method, params}));
  });
  const evaluate = async expression => {
    const response = await send('Runtime.evaluate', {expression, returnByValue:true});
    if (response.exceptionDetails) throw Error(response.exceptionDetails.exception?.description || response.exceptionDetails.text);
    return response.result.value;
  };
  await send('Page.enable');
  await send('Runtime.enable');
  await send('Network.enable');
  await send('Emulation.setDeviceMetricsOverride', {width:1440, height:1000, deviceScaleFactor:1, mobile:false});
  if (options.mbps) {
    const rate = Number(options.mbps) * 1e6 / 8;
    await send('Network.emulateNetworkConditions', {offline:false, latency:Number(options['latency-ms'] || 0), downloadThroughput:rate, uploadThroughput:rate});
  }
  await send('Page.addScriptToEvaluateOnNewDocument', {source: `
    window.__startup = {phases:[]};
    window.addEventListener('starling-reader-ready', () => {
      window.__startup.readyMs = performance.now();
      const settled = () => {
        if (window.starling?.fontsPending() === 0) window.__startup.settledMs = performance.now();
        else setTimeout(settled, 20);
      };
      requestAnimationFrame(settled);
    });
    document.addEventListener('DOMContentLoaded', () => {
      const text = document.querySelector('#loading-text');
      if (text) {
        const record = () => window.__startup.phases.push({text:text.textContent, ms:performance.now()});
        record(); new MutationObserver(record).observe(text, {subtree:true, childList:true, characterData:true});
      }
    });
  `});
  const measurements = [];
  let previousTimeOrigin = 0;
  for (const cache of ['cold', 'warm']) {
    await send('Page.navigate', {url:'about:blank'});
    await send('Page.navigate', {url:options.url});
    let settled = false;
    for (let attempt = 0; attempt < 600; attempt++) {
      try { settled = await evaluate(`location.href === ${JSON.stringify(options.url)} && performance.timeOrigin !== ${previousTimeOrigin} && Boolean(window.__startup?.settledMs)`); } catch {}
      if (settled) break;
      await sleep(100);
    }
    if (!settled) throw Error('Editor did not become ready with fonts settled');
    // Capture only the initial editor load; avoid counting delayed analytics.
    const result = await evaluate(`({
      ...window.__startup,
      timeOrigin:performance.timeOrigin,
      document:window.starling.debug('name'),
      resources:performance.getEntriesByType('resource')
        .filter(r => r.name.startsWith(location.origin + '/'))
        .map(r => ({path:new URL(r.name).pathname, ms:r.duration, startMs:r.startTime,
          transfer:r.transferSize, encoded:r.encodedBodySize, decoded:r.decodedBodySize}))
    })`);
    if (browserErrors.length) throw Error(browserErrors.join('; '));
    result.cache = cache;
    previousTimeOrigin = result.timeOrigin;
    result.transferBytes = result.resources.reduce((total, r) => total + r.transfer, 0);
    measurements.push(result);
    if (options.shot && cache === 'cold') {
      const {data} = await send('Page.captureScreenshot', {format:'png'});
      writeFileSync(options.shot, Buffer.from(data, 'base64'));
    }
    console.log(`${cache}: ready ${(result.readyMs / 1000).toFixed(2)}s, fonts settled ${(result.settledMs / 1000).toFixed(2)}s, ${(result.transferBytes / 1e6).toFixed(2)} MB`);
  }
  writeFileSync(options.out, JSON.stringify({url:options.url, measuredAt:new Date().toISOString(),
    network:options.mbps ? {mbps:Number(options.mbps), latencyMs:Number(options['latency-ms'] || 0)} : 'unthrottled',
    measurements}, null, 2) + '\n');
} finally {
  ws?.close();
  chrome.kill();
  await sleep(500);
  rmSync(profile, {recursive:true, force:true, maxRetries:3, retryDelay:200});
}
