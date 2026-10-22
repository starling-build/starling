// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

#if !arch(wasm32)
/// The publication's HTML remains usable independently of the web runtime.
/// This small host adapter switches views; document rendering stays in Swift.
enum SiteReaderFallback {
    static let markup = """
    <style>
      body.starling-publication { background:#f8f9fc; color:#192235; height:auto; min-height:100vh; }
      .starling-publication #starling-text { max-width:76ch; margin:auto; padding:28px 24px 64px;
        font:18px/1.65 system-ui,sans-serif; overflow-wrap:anywhere; }
      .starling-publication a { color:#2449ce; }
      .starling-publication a:focus-visible,.starling-publication button:focus-visible {
        outline:3px solid #2449ce; outline-offset:4px; }
      .starling-publication #starling-text nav { border-bottom:1px solid #dbe0eb; padding-bottom:12px; }
      .starling-publication #starling-text aside { color:#4e5c73; border-bottom:1px solid #dbe0eb; }
      .starling-publication #starling-text h1,.starling-publication #starling-text h2,
      .starling-publication #starling-text h3 { line-height:1.25; }
      .starling-publication #starling-article > p,.starling-publication #starling-article > h1,
      .starling-publication #starling-article > h2,.starling-publication #starling-article > h3 { white-space:pre-wrap; }
      .starling-publication #starling-text li { margin:8px 0; }
      .starling-publication #starling-text .starling-downloads { font-size:16px; }
      .starling-publication:not(.starling-interactive) #starling { position:fixed; inset:0; visibility:hidden; }
      .starling-publication #loading { display:none; }
      .starling-publication:not(.starling-interactive) #font-status { display:none; }
      #starling-reader-controls { max-width:76ch; margin:auto; padding:16px 24px 0;
        font:18px/1.5 system-ui,sans-serif; }
      #starling-reader-controls button { font:15px/1.5 system-ui,sans-serif; background:#fff; color:#192235;
        border:1px solid #bdc7dc; border-radius:6px; padding:8px 12px; cursor:pointer; }
      #starling-reader-controls p { margin:8px 0; font-size:15px; }
      .starling-interactive #starling-text { position:absolute; width:1px; height:1px;
        overflow:hidden; clip:rect(0 0 0 0); white-space:nowrap; padding:0; }
      .starling-interactive #starling-reader-controls { position:fixed; bottom:12px; left:12px;
        z-index:10; padding:0; }
      .starling-interactive #starling-reader-status { display:none; }
      @media print {
        .starling-publication #starling,.starling-publication #starling-reader-controls,
        .starling-publication #font-status { display:none; }
        .starling-publication #starling-text { position:static; width:auto; height:auto;
          clip:auto; overflow:visible; white-space:normal; padding:0; }
      }
    </style>
    <div id="starling-reader-controls">
      <p id="starling-reader-status" role="status">Text view. Use the document downloads for the original page layout.</p>
      <button id="starling-reader-toggle" type="button" hidden>Keep reading text</button>
    </div>
    <script>
    (() => {
      const body = document.body;
      const button = document.getElementById('starling-reader-toggle');
      const status = document.getElementById('starling-reader-status');
      let ready = false, failed = false;
      let keepText = new URLSearchParams(location.search).get('reader') === 'text';
      // Only the reader's own scrolling pins the text view: the browser's
      // jump to a #p= anchor is not a choice, and the interactive reader
      // reveals that paragraph itself.
      let userInput = false;
      for (const kind of ['pointerdown', 'wheel', 'keydown', 'touchstart']) {
        window.addEventListener(kind, () => { userInput = true; }, { capture:true, passive:true });
      }
      button.hidden = false;
      status.textContent = 'Opening the interactive reader. You can read the text now or use the downloads for the original page layout.';
      const preserveTextNavigation = () => {
        for (const link of document.querySelectorAll('#starling-text nav a, #starling-article a')) {
          const url = new URL(link.href);
          if (!link.closest('nav') && !(url.origin === location.origin && /^#p=[0-9]+$/.test(url.hash))) continue;
          url.searchParams.set('reader', 'text');
          link.href = url.href;
        }
      };
      const pinText = () => {
        if (!body.classList.contains('starling-interactive')) {
          keepText = true;
          preserveTextNavigation();
        }
      };
      document.addEventListener('pointerdown', event => {
        if (event.target.closest('#starling-text')) pinText();
      });
      document.addEventListener('focusin', event => {
        if (event.target.closest('#starling-text')) pinText();
      });
      window.addEventListener('scroll', () => { if (userInput && window.scrollY > 0) pinText(); }, { passive:true });
      button.addEventListener('click', () => {
        if (body.classList.contains('starling-interactive') || !ready) {
          pinText();
          keepText = true;
          body.classList.remove('starling-interactive');
          preserveTextNavigation();
          status.textContent = 'Text view. Use the document downloads for the original page layout.';
          button.textContent = ready ? 'Open interactive reader' : 'Waiting for interactive reader…';
          button.disabled = !ready;
        } else {
          body.classList.add('starling-interactive');
          button.textContent = 'Read text';
          window.scrollTo(0, 0);
        }
      });
      window.addEventListener('starling-reader-ready', () => {
        if (failed) return;
        ready = true;
        button.disabled = false;
        if (!keepText) { body.classList.add('starling-interactive'); window.scrollTo(0, 0); }
        else preserveTextNavigation();
        button.textContent = body.classList.contains('starling-interactive') ? 'Read text' : 'Open interactive reader';
        status.textContent = 'Text view. Use the document downloads for the original page layout.';
      });
      window.addEventListener('starling-reader-failed', () => {
        failed = true;
        ready = false;
        body.classList.remove('starling-interactive');
        button.hidden = true;
        preserveTextNavigation();
        status.textContent = 'The interactive reader could not open. You can keep reading the text and use the document downloads.';
      });
      // A failed module import prevents the host module itself from running.
      window.addEventListener('error', event => {
        if (event.target instanceof HTMLScriptElement) {
          window.dispatchEvent(new Event('starling-reader-failed'));
        }
      }, true);
      if (keepText) {
        document.addEventListener('DOMContentLoaded', preserveTextNavigation, { once:true });
      }
    })();
    </script>
    """
}
#endif
