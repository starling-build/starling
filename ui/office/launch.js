// Only the entry page is JavaScript. Editing uses the existing Swift/WASM app.
// A user-selected File is passed through an in-memory blob URL, never a server.
const config = JSON.parse(document.querySelector('#office-config').textContent);
const input = document.querySelector('#starling-file');
const card = document.querySelector('#drop-zone');
const error = document.querySelector('#file-error');
let starting = false;

function showError(message) {
  error.textContent = message;
  error.hidden = false;
}

async function launch(kind, mode, file) {
  if (starting) return;
  const app = config.apps[kind];
  if (!app) return;
  starting = true;
  // The runtime creates its own Open input with this ID.
  input.removeAttribute('id');
  document.querySelector('#website').hidden = true;
  document.querySelector('#editor').hidden = false;
  document.body.classList.add('editing');
  window.scrollTo(0, 0);
  const canvas = document.querySelector('#office-canvas');
  const loading = document.querySelector('#loading');
  let objectURL;
  function failed(event) {
    console.error(event?.error || event?.reason || event);
    loading.hidden = true;
    document.querySelector('#editor-error').hidden = false;
  }
  window.addEventListener('error', failed);
  window.addEventListener('unhandledrejection', failed);
  try {
    let initialFiles = [];
    let args = app.args;
    if (file) {
      objectURL = URL.createObjectURL(file);
      initialFiles = [{name: file.name, url: objectURL}];
      args = [file.name];
    } else if (mode === 'example') {
      initialFiles = [{name: app.example, url: '/examples/' + app.example}];
      args = [app.example];
    }
    const runtime = config.runtime;
    // Start the large downloads as soon as the user opens an editor. Waiting
    // for the host module and its imports adds several network round trips.
    // Pass the actual responses to the host: some browsers otherwise fetch
    // again after a <link rel=preload>, doubling these large downloads.
    let appURL = runtime.app;
    if (runtime.appBrotli) {
      try { new DecompressionStream('brotli'); appURL = runtime.appBrotli; } catch { /* use gzip */ }
    }
    const preloaded = {};
    for (const href of (runtime.preloadResponses ? [appURL, runtime.renderer + 'skwasm.wasm'] : [])) {
      const response = fetch(href);
      response.catch(() => {}); // the host handles errors after its import
      preloaded[new URL(href, document.baseURI).href] = response;
    }
    // Fetch the manifest alongside the host module and its imports, saving a
    // network round trip before the host can start the required font downloads.
    const [{startStarling}, fonts] = await Promise.all([
      import(runtime.host),
      fetch(runtime.fonts).then(response => {
        if (!response.ok) throw new Error('Could not load the font manifest.');
        return response.json();
      }),
    ]);
    const fontStatus = document.querySelector('#font-status');
    const retryFonts = fontStatus.querySelector('button');
    window.starling = await startStarling({
      canvas, app: runtime.app, appBrotli: runtime.appBrotli, preloaded, skwasmBase: runtime.renderer,
      fonts, args, initialFiles, initialRoute: location.pathname,
      onPhase(message) { document.querySelector('#loading-text').textContent = message; },
      onProgress(loaded, total) {
        const progress = document.querySelector('#loading-progress');
        if (total) { progress.max = total; progress.value = loaded; }
        else progress.removeAttribute('value');
      },
      onFontStatus({pending, failed}) {
        fontStatus.hidden = !pending.length && !failed.length;
        fontStatus.querySelector('span').textContent = failed.length
          ? 'Some fonts could not load. Text is using a fallback.' : 'Loading document fonts…';
        retryFonts.hidden = !failed.length;
      },
    });
    retryFonts.addEventListener('click', () => window.starling.retryFonts().catch(console.error));
    document.title = app.label + ' — Starling Office';
    requestAnimationFrame(() => requestAnimationFrame(() => {
      loading.hidden = true;
      canvas.focus();
      window.dispatchEvent(new Event('starling-reader-ready'));
    }));
  } catch (reason) {
    failed(reason);
  } finally {
    if (objectURL) URL.revokeObjectURL(objectURL);
  }
}

function openFiles(files) {
  if (!files.length) return;
  if (files.length !== 1) return showError('Please open one file at a time.');
  const file = files[0];
  const extension = file.name.split('.').pop().toLowerCase();
  const kind = {docx: 'writer', xlsx: 'sheets', pptx: 'slides'}[extension];
  if (!kind) return showError('Choose a .docx, .xlsx, or .pptx file. Older .doc, .xls, and .ppt files aren’t supported here.');
  if (!file.size) return showError('This file is empty. Please choose another file.');
  error.hidden = true;
  launch(kind, 'file', file);
}

input.disabled = false;
input.addEventListener('change', () => { openFiles(input.files); input.value = ''; });
// Prevent a dropped document from navigating away from the site.
for (const event of ['dragover', 'drop']) document.addEventListener(event, e => e.preventDefault());
card.addEventListener('dragover', () => card.classList.add('dragover'));
card.addEventListener('dragleave', e => { if (!card.contains(e.relatedTarget)) card.classList.remove('dragover'); });
card.addEventListener('drop', e => { card.classList.remove('dragover'); openFiles(e.dataTransfer.files); });
document.querySelectorAll('[data-start]').forEach(link => link.addEventListener('click', event => {
  if (event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
  event.preventDefault();
  launch(link.dataset.app, link.dataset.start);
}));
const start = new URLSearchParams(location.search).get('start');
if (config.kind && ['new', 'example'].includes(start)) launch(config.kind, start);
