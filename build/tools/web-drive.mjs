#!/usr/bin/env node
// Drive the browser build in headless Chrome over the DevTools protocol —
// the web counterpart of build/shell-drive.py. Loads the page the dev
// server serves (build/web-app.sh --serve, or build/tools/web-serve.py),
// then runs the actions given, in order:
//
//   click X Y            press and release the left button at CSS X,Y
//   move X Y             move the pointer
//   type TEXT            each character as a key down (with text) and up
//   press KEY            one key by name: Enter, Backspace, Tab, ArrowDown…
//   chord ctrl|meta KEY  the key with Control or Meta held (chord ctrl s)
//   setfile PATH         hand an ABSOLUTE path to the page's <input
//                        id=starling-file>, as if picked (Office's Open)
//   downloads DIR        let downloads land in DIR (Office's Save)
//   eval JS              print the expression's value as JSON, `eval: …`
//   dump KIND FILE       write starling.debug(KIND) to FILE (Office:
//                        'layout' — the same text `OfficeApp --layout`
//                        prints natively)
//   wait MS              sleep
//   shot FILE            screenshot to FILE (PNG)
//
// Prints the page's console. Environment: URL (default
// http://127.0.0.1:8137/), W and H (the window, default 1400×900 — Chrome
// lays out nothing narrower than 500), DPR, CHROME (the binary),
// CHROME_PROFILE (a user-data dir; the default is under the OS temp dir),
// PORT (the DevTools port, default 9333 — a crashed run leaves its Chrome
// on the port, and the next attaches to the stale target and hangs; this
// script kills what it started, `pkill -f remote-debugging-port=9333` for
// what it did not).
//
//   node build/tools/web-drive.mjs wait 6000 chord ctrl o wait 500 \
//       setfile "$PWD/apps/OfficeApp/Tests/OfficeAppTests/Fixtures/word-boringcrypto.docx" \
//       wait 8000 dump layout /tmp/web.txt shot /tmp/web.png
//
// Node 22+ (the global WebSocket); no dependencies.
import { spawn } from 'node:child_process';
import { writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const args = process.argv.slice(2);
const W = +(process.env.W || 1400), H = +(process.env.H || 900);
const port = +(process.env.PORT || 9333);
const chromeBinary = process.env.CHROME
  || (process.platform === 'darwin' ? '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' : 'google-chrome');
const profile = process.env.CHROME_PROFILE || join(tmpdir(), 'starling-web-drive-profile');
const chrome = spawn(chromeBinary, [
  '--headless=new', '--no-first-run', `--remote-debugging-port=${port}`,
  `--user-data-dir=${profile}`, '--enable-unsafe-swiftshader',
  `--window-size=${W},${H}`, 'about:blank',
], { stdio: 'ignore' });
const finish = (code) => { try { chrome.kill(); } catch {} process.exit(code); };
process.on('SIGINT', () => finish(130));
process.on('SIGTERM', () => finish(143));

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
let targets;
for (let i = 0; i < 50 && !targets; i++) {
  try { targets = await (await fetch(`http://127.0.0.1:${port}/json`)).json(); }
  catch { await sleep(200); }
}
if (!targets) { console.error(`web-drive: no DevTools on port ${port}`); finish(1); }
const ws = new WebSocket(targets.find((t) => t.type === 'page').webSocketDebuggerUrl);
await new Promise((r) => ws.addEventListener('open', r));
let id = 0; const pending = new Map();
ws.addEventListener('message', ({ data }) => {
  const m = JSON.parse(data);
  if (m.id && pending.has(m.id)) { pending.get(m.id)(m); pending.delete(m.id); }
  else if (m.method === 'Runtime.consoleAPICalled') {
    console.log(m.params.type + ':', m.params.args.map((a) => a.value ?? a.description).join(' ').slice(0, 30000));
  } else if (m.method === 'Runtime.exceptionThrown') {
    console.log('exception:', (m.params.exceptionDetails.exception?.description || m.params.exceptionDetails.text).slice(0, 20000));
  }
});
const send = (method, params = {}) => new Promise((resolve, reject) => {
  ws.send(JSON.stringify({ id: ++id, method, params }));
  pending.set(id, (m) => m.error ? reject(new Error(`${method}: ${m.error.message}`)) : resolve(m.result));
});
await send('Runtime.enable');
await send('Emulation.setDeviceMetricsOverride', { width: W, height: H, deviceScaleFactor: +(process.env.DPR || 1), mobile: false });
await send('Page.navigate', { url: process.env.URL || 'http://127.0.0.1:8137/' });
await sleep(3000);
const mouse = async (type, x, y, button = 'left') =>
  send('Input.dispatchMouseEvent', { type, x, y, button, clickCount: 1, buttons: type === 'mouseReleased' ? 0 : 1 });
const evaluate = async (expression) => {
  const { result, exceptionDetails } = await send('Runtime.evaluate', { expression, returnByValue: true });
  if (exceptionDetails) throw new Error(exceptionDetails.exception?.description || exceptionDetails.text);
  return result.value;
};
let failed = false;
try {
  while (args.length) {
    const op = args.shift();
    if (op === 'click') {
      const x = +args.shift(), y = +args.shift();
      await mouse('mouseMoved', x, y); await sleep(50);
      await mouse('mousePressed', x, y); await sleep(80);
      await mouse('mouseReleased', x, y); await sleep(300);
    } else if (op === 'move') {
      await send('Input.dispatchMouseEvent', { type: 'mouseMoved', x: +args.shift(), y: +args.shift(), buttons: 0 });
    } else if (op === 'type') {
      for (const ch of args.shift()) {
        const code = /[a-z]/i.test(ch) ? 'Key' + ch.toUpperCase() : /[0-9]/.test(ch) ? 'Digit' + ch : ch === ' ' ? 'Space' : 'Unidentified';
        await send('Input.dispatchKeyEvent', { type: 'keyDown', key: ch, code, text: ch, unmodifiedText: ch });
        await send('Input.dispatchKeyEvent', { type: 'keyUp', key: ch, code });
        await sleep(30);
      }
    } else if (op === 'press') {
      const key = args.shift();
      const vk = { Enter: 13, Backspace: 8, Tab: 9, Escape: 27, Delete: 46 }[key] || 0;
      await send('Input.dispatchKeyEvent', { type: 'keyDown', key, code: key, windowsVirtualKeyCode: vk });
      await send('Input.dispatchKeyEvent', { type: 'keyUp', key, code: key });
      await sleep(100);
    } else if (op === 'chord') {
      const mod = args.shift(); const k = args.shift();
      const modKey = mod === 'ctrl' ? { key: 'Control', code: 'ControlLeft', modifiers: 2 } : { key: 'Meta', code: 'MetaLeft', modifiers: 4 };
      await send('Input.dispatchKeyEvent', { type: 'keyDown', key: modKey.key, code: modKey.code, modifiers: modKey.modifiers });
      await send('Input.dispatchKeyEvent', { type: 'keyDown', key: k, code: 'Key' + k.toUpperCase(), modifiers: modKey.modifiers });
      await send('Input.dispatchKeyEvent', { type: 'keyUp', key: k, code: 'Key' + k.toUpperCase(), modifiers: modKey.modifiers });
      await send('Input.dispatchKeyEvent', { type: 'keyUp', key: modKey.key, code: modKey.code });
      await sleep(200);
    } else if (op === 'eval') {
      console.log('eval:', JSON.stringify(await evaluate(args.shift())));
    } else if (op === 'dump') {
      const kind = args.shift(); const file = args.shift();
      const text = await evaluate(`window.starling.debug(${JSON.stringify(kind)})`);
      if (text == null) throw new Error(`the app does not answer debug(${JSON.stringify(kind)})`);
      writeFileSync(file, text);
    } else if (op === 'setfile') {
      const path = args.shift();
      const { root } = await send('DOM.getDocument');
      const { nodeId } = await send('DOM.querySelector', { nodeId: root.nodeId, selector: '#starling-file' });
      await send('DOM.setFileInputFiles', { files: [path], nodeId });
      await sleep(300);
    } else if (op === 'downloads') {
      await send('Browser.setDownloadBehavior', { behavior: 'allow', downloadPath: args.shift(), eventsEnabled: true });
    } else if (op === 'wait') {
      await sleep(+args.shift());
    } else if (op === 'shot') {
      const { data } = await send('Page.captureScreenshot', { format: 'png' });
      writeFileSync(args.shift(), Buffer.from(data, 'base64'));
    } else {
      throw new Error(`unknown action ${op}`);
    }
  }
} catch (error) {
  console.error(`web-drive: ${error.message}`);
  failed = true;
}
ws.close();
finish(failed ? 1 : 0);
