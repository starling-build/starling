#!/usr/bin/env node
// Drive the browser build in headless Chrome over the DevTools protocol —
// the web counterpart of build/shell-drive.py. Loads the page the dev
// server serves (build/web-app.sh --serve, or build/tools/web-serve.py),
// then runs the actions given, in order:
//
//   click X Y            press and release the left button at CSS X,Y
//   modclick ctrl|meta X Y  click with Control or Meta held (follow a link)
//   rightclick X Y       open the context menu at CSS X,Y
//   move X Y             move the pointer
//   touchdrag X Y DX DY  one finger: down at X,Y, dragged by DX,DY, lifted
//   dblclick X Y         two presses in quick succession (selects a word)
//   type TEXT            each character as a key down (with text) and up
//   press KEY            one key by name: Enter, Backspace, Tab, ArrowDown…
//   chord ctrl|meta KEY  the key with Control or Meta held (chord ctrl s)
//   setfile PATH         hand an ABSOLUTE path to the page's <input
//                        id=starling-file>, as if picked (Office's Open)
//   downloads DIR        let downloads land in DIR (Office's Save)
//   eval JS              print the expression's value as JSON, `eval: …`
//   settle NAME          wait for the opened Office document and quiet fonts
//   dump KIND FILE       write starling.debug(KIND) to FILE (Office:
//                        'layout' — the same text `OfficeApp --layout`
//                        prints natively)
//   pdfs LIST OUTDIR     Office: every file named in LIST (one absolute
//                        path a line) opened and exported to PDF —
//                        OUTDIR/NAME.pdf, and a line per file in
//                        OUTDIR/web.tsv (ok, OPEN-FAIL, EXPORT-FAIL with
//                        the status bar's words). One page for all of
//                        them, reloaded after a failure; a file whose PDF
//                        is already there is skipped, so a sweep resumes.
//   walk FILE OUT        Office: open FILE (absolute), then click every
//                        ribbon tab and every control with a tooltip on it,
//                        one at a time, Escape after each; a line per
//                        control in OUT (app, tab, tip, ok or THREW and the
//                        page's error); the page is reloaded and FILE
//                        reopened after a failure. TABS (comma list)
//                        limits the tabs. Then every control a button
//                        brought up (a dialog's, a menu's: SUB=0 skips),
//                        each File backstage entry (FILE=0 skips) and each
//                        right-click menu item (CONTEXT=0 skips), each with
//                        its own showing. The browser's ControlSweepTests.
//   wait MS              sleep
//   shot FILE            screenshot to FILE (PNG)
//   canvas FILE          save the rendered app canvas to FILE (PNG)
//
// Prints the page's console. Environment: URL (default
// http://127.0.0.1:8137/), W and H (the window, default 1400×900 — Chrome
// lays out nothing narrower than 500), DPR, CHROME (the binary),
// CHROME_PROFILE (a user-data dir; the default is under the OS temp dir),
// BLOCK_URLS (JSON array of CDP URL patterns to fail before navigation),
// DISABLE_SCRIPTS=1 (disable page scripts before navigation),
// PICKERS=1 (keep the browser's file pickers; by default they are hidden, so
// Open is the file input and Save a download), PRELOAD (a .js file run in every
// page before its own scripts, e.g. stand-in pickers),
// OPEN_MS (document-open timeout, default 30000), FONT_WAIT_MS (settle
// timeout, default 60000), SETTLE_MS (font-quiet interval, default 800),
// PORT (the DevTools port, default 9333 — a crashed run leaves its Chrome
// on the port, and the next attaches to the stale target and hangs; this
// script kills what it started, `pkill -f remote-debugging-port=9333` for
// what it did not).
//
//   node build/tools/web-drive.mjs wait 6000 chord ctrl o wait 500 \
//       setfile "$PWD/apps/OfficeApp/Tests/OfficeAppTests/Fixtures/word-boringcrypto.docx" \
//       settle word-boringcrypto.docx dump layout /tmp/web.txt shot /tmp/web.png
//
// Node 22+ (the global WebSocket); no dependencies.
import { spawn } from 'node:child_process';
import { appendFileSync, existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { basename, join, resolve } from 'node:path';

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
let thrown = 0;   // exceptions the page has thrown: a trap ends the app
let lastThrown = '';
ws.addEventListener('message', ({ data }) => {
  const m = JSON.parse(data);
  if (m.id && pending.has(m.id)) { pending.get(m.id)(m); pending.delete(m.id); }
  else if (m.method === 'Runtime.consoleAPICalled') {
    console.log(m.params.type + ':', m.params.args.map((a) => a.value ?? a.description).join(' ').slice(0, 30000));
  } else if (m.method === 'Runtime.exceptionThrown') {
    thrown++;
    lastThrown = (m.params.exceptionDetails.exception?.description || m.params.exceptionDetails.text || '').split('\n')[0];
    if (process.env.QUIET_EXCEPTIONS !== '1') console.log('exception:', (m.params.exceptionDetails.exception?.description || m.params.exceptionDetails.text).slice(0, 20000));
  }
});
const send = (method, params = {}) => new Promise((resolve, reject) => {
  ws.send(JSON.stringify({ id: ++id, method, params }));
  pending.set(id, (m) => m.error ? reject(new Error(`${method}: ${m.error.message}`)) : resolve(m.result));
});
await send('Runtime.enable');
await send('Emulation.setDeviceMetricsOverride', { width: W, height: H, deviceScaleFactor: +(process.env.DPR || 1), mobile: false });
if (process.env.BLOCK_URLS) {
  await send('Network.enable');
  await send('Network.setBlockedURLs', { urls: JSON.parse(process.env.BLOCK_URLS) });
}
if (process.env.DISABLE_SCRIPTS === '1') await send('Emulation.setScriptExecutionDisabled', { value:true });
// The browser's own file pickers open native dialogs no script can answer, so a driven page goes
// without them (Save is then a download, as in Firefox) unless PICKERS=1. PRELOAD=file.js runs in
// every page before its scripts: a test's stand-in pickers, for one.
{
  let early = process.env.PICKERS === '1' ? '' :
    "for (const k of ['showSaveFilePicker','showOpenFilePicker']) Object.defineProperty(window, k, { value: undefined, configurable: true, writable: true });\n";
  if (process.env.PRELOAD) early += readFileSync(process.env.PRELOAD, 'utf8');
  if (early) { await send('Page.enable'); await send('Page.addScriptToEvaluateOnNewDocument', { source: early }); }
}
// CLIPBOARD=1 grants the page the clipboard without a prompt (a test's paste from another app).
if (process.env.CLIPBOARD === '1') {
  await send('Browser.grantPermissions', { origin: new URL(process.env.URL || 'http://127.0.0.1:8137/').origin,
    permissions: ['clipboardReadWrite', 'clipboardSanitizedWrite'] });
}
await send('Page.navigate', { url: process.env.URL || 'http://127.0.0.1:8137/' });
await sleep(3000);
const mouse = async (type, x, y, button = 'left') =>
  send('Input.dispatchMouseEvent', { type, x, y, button, clickCount: 1, buttons: type === 'mouseReleased' ? 0 : 1 });
const evaluate = async (expression) => {
  const { result, exceptionDetails } = await send('Runtime.evaluate', { expression, returnByValue: true, awaitPromise: true });
  if (exceptionDetails) throw new Error(exceptionDetails.exception?.description || exceptionDetails.text);
  return result.value;
};
// Shared bounded polling; callers must check a timeout instead of continuing.
const until = async (ms, test) => {
  for (const end = Date.now() + ms; Date.now() < end; await sleep(100)) {
    const value = await test();
    if (value) return value;
  }
  return null;
};
let failed = false;
try {
  while (args.length) {
    const op = args.shift();
    if (op === 'modclick') {
      const modifier = args.shift();
      if (!['ctrl', 'meta'].includes(modifier)) throw new Error('modclick expects ctrl or meta');
      const x = +args.shift(), y = +args.shift();
      const key = modifier === 'ctrl' ? 'Control' : 'Meta';
      const modifiers = modifier === 'ctrl' ? 2 : 4;
      const windowsVirtualKeyCode = modifier === 'ctrl' ? 17 : 91;
      await mouse('mouseMoved', x, y); await sleep(50);
      await send('Input.dispatchKeyEvent', { type:'keyDown', key, code:key+'Left', windowsVirtualKeyCode, modifiers });
      await sleep(80);
      await send('Input.dispatchMouseEvent', { type:'mousePressed', x, y, button:'left', buttons:1, clickCount:1, modifiers });
      await sleep(80);
      await send('Input.dispatchMouseEvent', { type:'mouseReleased', x, y, button:'left', buttons:0, clickCount:1, modifiers });
      await send('Input.dispatchKeyEvent', { type:'keyUp', key, code:key+'Left', windowsVirtualKeyCode, modifiers:0 });
      await sleep(300);
    } else if (op === 'rightclick') {
      const x = +args.shift(), y = +args.shift();
      await mouse('mouseMoved', x, y); await sleep(50);
      await send('Input.dispatchMouseEvent', { type:'mousePressed', x, y, button:'right', buttons:2, clickCount:1 });
      await sleep(80);
      await send('Input.dispatchMouseEvent', { type:'mouseReleased', x, y, button:'right', buttons:0, clickCount:1 });
      await sleep(300);
    } else if (op === 'click') {
      const x = +args.shift(), y = +args.shift();
      await mouse('mouseMoved', x, y); await sleep(50);
      await mouse('mousePressed', x, y); await sleep(80);
      await mouse('mouseReleased', x, y); await sleep(300);
    } else if (op === 'move') {
      await send('Input.dispatchMouseEvent', { type: 'mouseMoved', x: +args.shift(), y: +args.shift(), buttons: 0 });
    } else if (op === 'dblclick') {
      const x = +args.shift(), y = +args.shift();
      await mouse('mouseMoved', x, y); await sleep(50);
      for (let i = 0; i < 2; i++) {
        await mouse('mousePressed', x, y); await sleep(40);
        await mouse('mouseReleased', x, y); await sleep(60);
      }
      await sleep(300);
    } else if (op === 'touchdrag') {
      const x = +args.shift(), y = +args.shift(), dx = +args.shift(), dy = +args.shift();
      await send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [{ x, y }] });
      const steps = 8;
      for (let i = 1; i <= steps; i++) {
        await send('Input.dispatchTouchEvent', { type: 'touchMove', touchPoints: [{ x: x + dx * i / steps, y: y + dy * i / steps }] });
        await sleep(16);
      }
      await send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
      await sleep(400);
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
      // Navigation keys keep their physical code (Home, End, ArrowLeft…);
      // KeyHOME is not a browser key code and cannot drive Ctrl+Home.
      const code = /^[a-z]$/i.test(k) ? 'Key' + k.toUpperCase() : /^[0-9]$/.test(k) ? 'Digit' + k : k;
      await send('Input.dispatchKeyEvent', { type: 'keyDown', key: modKey.key, code: modKey.code, modifiers: modKey.modifiers });
      await send('Input.dispatchKeyEvent', { type: 'keyDown', key: k, code, modifiers: modKey.modifiers });
      await send('Input.dispatchKeyEvent', { type: 'keyUp', key: k, code, modifiers: modKey.modifiers });
      await send('Input.dispatchKeyEvent', { type: 'keyUp', key: modKey.key, code: modKey.code });
      await sleep(200);
    } else if (op === 'eval') {
      console.log('eval:', JSON.stringify(await evaluate(args.shift())));
    } else if (op === 'settle') {
      const name = args.shift();
      if (!await until(+(process.env.OPEN_MS || 30000), async () =>
        await evaluate('window.starling?.debug?.("name")') === name)) {
        throw new Error(`document did not open before timeout: ${name}`);
      }
      // Loading a large document can request more font families as it lays out.
      // Require a quiet interval after the final registration/relayout, just as
      // PDF export does, rather than capturing a provisional fallback layout.
      let quiet = null;
      if (!await until(+(process.env.FONT_WAIT_MS || 60000), async () => {
        const pending = await evaluate('window.starling?.fontsPending?.()');
        if (pending !== 0) { quiet = null; return false; }
        quiet ??= Date.now();
        return Date.now() - quiet >= +(process.env.SETTLE_MS || 800);
      })) throw new Error(`fonts did not settle before timeout: ${name}`);
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
    } else if (op === 'pdfs') {
      const list = readFileSync(args.shift(), 'utf8').split('\n').map((l) => l.trim()).filter(Boolean).map((l) => resolve(l));
      const out = args.shift();
      mkdirSync(out, { recursive: true });
      await send('Browser.setDownloadBehavior', { behavior: 'allow', downloadPath: out, eventsEnabled: true });
      const debug = (kind) => evaluate(`window.starling && window.starling.debug ? window.starling.debug(${JSON.stringify(kind)}) : null`).catch(() => null);
      const reload = async () => {
        await send('Page.navigate', { url: process.env.URL || 'http://127.0.0.1:8137/' });
        await until(60000, async () => (await debug('name')) != null);
        await sleep(500);
      };
      await until(60000, async () => (await debug('name')) != null);
      for (const path of list) {
        const name = basename(path), pdf = join(out, name.replace(/\.[^.]+$/, '') + '.pdf');
        if (existsSync(pdf)) continue;
        let verdict = 'ok';
        const key = (type, extra) => send('Input.dispatchKeyEvent', { type, ...extra });
        await key('keyDown', { key: 'Control', code: 'ControlLeft', modifiers: 2 });
        await key('keyDown', { key: 'o', code: 'KeyO', modifiers: 2 });
        await key('keyUp', { key: 'o', code: 'KeyO', modifiers: 2 });
        await key('keyUp', { key: 'Control', code: 'ControlLeft' });
        await sleep(300);
        const { root } = await send('DOM.getDocument');
        const { nodeId } = await send('DOM.querySelector', { nodeId: root.nodeId, selector: '#starling-file' });
        await send('DOM.setFileInputFiles', { files: [path], nodeId });
        if (!await until(+(process.env.OPEN_MS || 30000), async () => (await debug('name')) === name)) {
          verdict = 'OPEN-FAIL\t' + ((await debug('status')) || 'did not open');
        } else {
          // Lazy fonts arrive after the open and re-lay the lines they set;
          // pictures decode after it too. Quiet for SETTLE_MS, then export.
          let quiet = Date.now();
          await until(30000, async () => {
            if (await evaluate('window.starling.fontsPending ? window.starling.fontsPending() : 0').catch(() => 0)) quiet = Date.now();
            return Date.now() - quiet >= +(process.env.SETTLE_MS || 800);
          });
          // PDF_QUERY=book-pdf is Sheets' whole workbook, as the gate prints it.
          const before = thrown;
          await debug(process.env.PDF_QUERY || 'pdf').catch(() => null);
          const done = await until(+(process.env.EXPORT_MS || 120000), async () => {
            if (existsSync(pdf)) return 'ok';
            if (thrown > before) return 'the page threw';
            const status = (await debug('status')) || '';
            return /^(Could not|Nothing)/.test(status) ? status : null;
          });
          if (done !== 'ok') verdict = 'EXPORT-FAIL\t' + (done || 'timed out');
        }
        appendFileSync(join(out, 'web.tsv'), `${name}\t${verdict}\n`);
        console.log(`${name}\t${verdict}`);
        if (verdict !== 'ok') await reload();
      }
    } else if (op === 'walk') {
      const path = resolve(args.shift()), out = args.shift(), name = basename(path);
      const debug = (kind) => evaluate(`window.starling && window.starling.debug ? window.starling.debug(${JSON.stringify(kind)}) : null`).catch(() => null);
      const key = (type, extra) => send('Input.dispatchKeyEvent', { type, ...extra });
      const chord = async (k, code) => {
        await key('keyDown', { key: 'Control', code: 'ControlLeft', modifiers: 2 });
        await key('keyDown', { key: k, code, modifiers: 2 }); await key('keyUp', { key: k, code, modifiers: 2 });
        await key('keyUp', { key: 'Control', code: 'ControlLeft' }); await sleep(300);
      };
      const escape = async () => {
        for (let i = 0; i < 2; i++) { await key('keyDown', { key: 'Escape', code: 'Escape', windowsVirtualKeyCode: 27 }); await key('keyUp', { key: 'Escape', code: 'Escape', windowsVirtualKeyCode: 27 }); await sleep(150); }
      };
      const click = async (x, y) => { await mouse('mouseMoved', x, y); await sleep(50); await mouse('mousePressed', x, y); await sleep(80); await mouse('mouseReleased', x, y); };
      // A file picker (Open, Insert Picture) is swallowed, not left open.
      await send('Page.setInterceptFileChooserDialog', { enabled: true }).catch(() => null);
      await send('Browser.setDownloadBehavior', { behavior: 'deny' }).catch(() => null);
      const open = async (reload) => {
        if (reload) await send('Page.navigate', { url: process.env.URL || 'http://127.0.0.1:8137/' });
        if (!await until(60000, async () => (await debug('name')) != null)) throw new Error('the app did not start');
        await sleep(500);
        await send('Page.setInterceptFileChooserDialog', { enabled: false }).catch(() => null);
        await chord('o', 'KeyO');
        const { root } = await send('DOM.getDocument');
        const { nodeId } = await send('DOM.querySelector', { nodeId: root.nodeId, selector: '#starling-file' });
        await send('DOM.setFileInputFiles', { files: [path], nodeId });
        if (!await until(+(process.env.OPEN_MS || 30000), async () => (await debug('name')) === name)) throw new Error(`${name} did not open`);
        await sleep(1500);
        await send('Page.setInterceptFileChooserDialog', { enabled: true }).catch(() => null);
        if (process.env.NOSELECT !== '1') await chord('a', 'KeyA');   // a selection, so formatting commands act
      };
      const controls = async () => ((await debug('controls')) || '').split('\n').filter(Boolean).map((l) => {
        const [kind, x, y, label] = l.split('\t'); return { kind, x: +x, y: +y, label };
      }).filter((c) => c.x >= 0 && c.y >= 0 && c.x < W && c.y < H);
      // A control a click brought up (a dialog's buttons, a menu's items):
      // in `after`, not in `before`, compared by kind, label and place (a
      // menu's Cut is not the ribbon's Cut).
      const spot = (c) => `${c.kind}\t${c.label}\t${c.x}\t${c.y}`;
      const appeared = (before, after) => {
        const seen = new Set(before.map(spot));
        return [...new Map(after.filter((c) => !seen.has(spot(c))).map((c) => [spot(c), c])).values()];
      };
      // The same control on a new showing: the nearest one of its kind and label.
      const again = (list, item) => list.filter((d) => d.kind === item.kind && d.label === item.label)
        .sort((a, b) => Math.hypot(a.x - item.x, a.y - item.y) - Math.hypot(b.x - item.x, b.y - item.y))[0];
      // Clicks each control `show` brings up, one per showing, and records
      // it as `where` > label. `show` resets nothing: it is called after
      // Escape (or a reload, after a failure).
      const probe = async (where, show) => {
        const base = await controls();
        await show();
        const items = appeared(base, await controls()).slice(0, +(process.env.SUB_MAX || 40));
        await escape();
        for (const item of items) {
          await show();
          const c = again(await controls(), item);
          if (!c) { appendFileSync(out, `${app}\t${where}\t${item.label}\tNOT-FOUND\n`); await escape(); continue; }
          const before = thrown;
          await click(c.x, c.y);
          await sleep(+(process.env.STEP_MS || 1000));
          let verdict = 'ok';
          if (thrown > before) verdict = `THREW\t${lastThrown.slice(0, 200)}`;
          else if ((await debug('name')) == null) verdict = 'DEAD\tthe app stopped answering';
          appendFileSync(out, `${app}\t${where}\t${item.label}\t${verdict}\n`);
          if (verdict !== 'ok') { console.log(`${app}\t${where}\t${item.label}\t${verdict}`); await open(true); continue; }
          await escape();
          if ((await debug('name')) !== name) await open(true);
        }
      };
      const tabNames = (process.env.TABS || 'File,Home,Insert,Draw,Design,Layout,References,Mailings,Transitions,Animations,Slide Show,Review,View,Formulas,Page Layout,Data,Help').split(',');
      await open(false);
      const app = name.replace(/^.*\./, '');
      const tabsOnScreen = (await controls()).filter((c) => c.kind === 'text' && c.y < 140 && tabNames.includes(c.label));
      const tabs = [...new Set(tabsOnScreen.map((c) => c.label))].filter((t) => t !== 'File');
      for (const tab of tabs) {
        const find = async (kind, label) => (await controls()).find((c) => c.kind === kind && c.label === label);
        const showTab = async () => { const t = await find('text', tab); if (t) { await click(t.x, t.y); await sleep(300); } return !!t; };
        await showTab();
        const tips = [...new Set((await controls()).filter((c) => c.kind === 'tip').map((c) => c.label))];
        for (const tip of tips) {
          await showTab();
          const c = await find('tip', tip);
          if (!c) { appendFileSync(out, `${app}\t${tab}\t${tip}\tNOT-FOUND\n`); continue; }
          const before = thrown;
          await click(c.x, c.y);
          await sleep(+(process.env.STEP_MS || 1000));
          const alive = (await debug('name')) != null;
          let verdict = 'ok';
          if (thrown > before) verdict = `THREW\t${lastThrown.slice(0, 200)}`;
          else if (!alive) verdict = 'DEAD\tthe app stopped answering';
          appendFileSync(out, `${app}\t${tab}\t${tip}\t${verdict}\n`);
          if (verdict !== 'ok') { console.log(`${app}\t${tab}\t${tip}\t${verdict}`); await open(true); await showTab(); continue; }
          await escape();
          if ((await debug('name')) !== name) await open(true);
        }
        // What each button opened: a dialog's or a menu's own controls.
        if (process.env.SUB !== '0') {
          for (const tip of tips) {
            await showTab();
            const base = await controls();
            const c = base.find((d) => d.kind === 'tip' && d.label === tip);
            if (!c) continue;
            await click(c.x, c.y); await sleep(+(process.env.STEP_MS || 1000));
            const opened = appeared(base, await controls()).length;
            await escape();
            // A menu or a dialog goes away on Escape; what stays (a new
            // sheet's tab, AutoSave's on/off) changed the document instead.
            const stayed = appeared(base, await controls()).length;
            if ((await debug('name')) !== name) await open(true);
            // One changed text (a zoom %, a font size) is not a menu.
            if (opened < 2 || stayed > 0) continue;
            await probe(`${tab} > ${tip}`, async () => {
              await showTab();
              const b = (await controls()).find((d) => d.kind === 'tip' && d.label === tip);
              if (b) { await click(b.x, b.y); await sleep(+(process.env.STEP_MS || 1000)); }
            });
          }
        }
      }
      // The File backstage: every entry in it, one at a time.
      if (process.env.FILE !== '0') {
        await probe('File', async () => {
          const f = (await controls()).find((c) => c.kind === 'text' && c.y < 140 && c.label === 'File');
          if (f) { await click(f.x, f.y); await sleep(+(process.env.STEP_MS || 1000)); }
        });
      }
      // The right-click menu on the document (the middle of the window).
      if (process.env.CONTEXT !== '0') {
        await probe('Right-click', async () => {
          const x = W / 2, y = H / 2;
          await mouse('mouseMoved', x, y);
          await send('Input.dispatchMouseEvent', { type: 'mousePressed', x, y, button: 'right', buttons: 2, clickCount: 1 });
          await sleep(60);
          await send('Input.dispatchMouseEvent', { type: 'mouseReleased', x, y, button: 'right', buttons: 0, clickCount: 1 });
          await sleep(+(process.env.STEP_MS || 1000));
        });
      }
    } else if (op === 'downloads') {
      await send('Browser.setDownloadBehavior', { behavior: 'allow', downloadPath: args.shift(), eventsEnabled: true });
    } else if (op === 'wait') {
      await sleep(+args.shift());
    } else if (op === 'canvas') {
      const data = await evaluate('document.querySelector("canvas").toDataURL("image/png")');
      writeFileSync(args.shift(), Buffer.from(data.split(',')[1], 'base64'));
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
