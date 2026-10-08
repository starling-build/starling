const descriptions = [
 'One desktop. Many possibilities. A fast native desktop, built-in tools, agent workspaces, and room to explore.',
 'One program. Every window. Dock, menus and windows in one widget tree. Compiled Swift and GPU rendering, built on the Starling SDK.',
 'Real apps. Real work. Native Wayland and X11 support. Chrome, VS Code and Linux apps. Files, Terminal, Settings and an App Store.',
 'Watch it work. Step in anytime. Dedicated agent workspaces keep the agent and its live apps together.',
 'Your desktop. Your perspective. A familiar 2D desktop and a living 3D city are two features of a much bigger desktop.',
 'Built in the open. Yours to explore. Early preview for Ubuntu and Windows through WSL2. Free, open source, Apache 2.0.',
];
const lastSlide = descriptions.length - 1;
// The published controller URL carries the content revision for the whole deck.
// Keep previews and PPTXs together across cached deployments.
const slideVersion = new URL(import.meta.url).searchParams.get('v') || String(Date.now());
const slideAsset = name => `slides/${name}?v=${slideVersion}`;
const actions = [
 ['Explore Desktop', '#2'],
 ['Explore the SDK', 'https://github.com/starling-build/starling/tree/office/sdk'],
 ['Get Desktop', 'https://starling.build/#install'],
 ['Explore the source', 'https://github.com/starling-build/starling/tree/office/shell'],
 ['Watch the film', 'https://starling.build/#film'],
 ['Get Desktop', 'https://starling.build/#install'],
];
const canvas = document.getElementById('starling');
const stage = document.getElementById('stage');
const poster = document.getElementById('poster');
const status = document.getElementById('load-status');
const repositoryLink = document.getElementById('repository-link');
const prev = document.getElementById('previous'), next = document.getElementById('next');
const dots = [...document.querySelectorAll('[data-slide]')];
let app, index = Math.max(0, Math.min(lastSlide, (Number(location.hash.slice(1)) || 1) - 1));
let portrait;
const isPortrait = () => canvas.clientWidth < canvas.clientHeight;
// Match the deck's repository text, including the slide's letterboxing.
function positionRepositoryLink() {
  repositoryLink.hidden = true;
  const tall = isPortrait(), deckWidth = tall ? 450 : 1280;
  const width = canvas.clientWidth, height = canvas.clientHeight;
  const scale = Math.min(width / deckWidth, height / 720);
  const left = (width - deckWidth * scale) / 2;
  const top = (height - 720 * scale) / 2;
  Object.assign(repositoryLink.style, {
    left: `${left + ((tall ? 32 : 72) - 4) * scale}px`,
    top: `${top + ((tall ? 494 : 510) - 4) * scale}px`,
    width: `${(tall ? 300 : 460) * scale}px`,
    height: `${(tall ? 32 : 44) * scale}px`,
  });
}
function update() {
  poster.querySelector('source').srcset = slideAsset(`tall-${index + 1}.png`);
  // Use the canvas's aspect ratio, which excludes the HTML controls.
  poster.querySelector('source').media = isPortrait() ? 'all' : 'not all';
  poster.querySelector('img').src = slideAsset(`wide-${index + 1}.png`);
  poster.querySelector('img').alt = descriptions[index];
  document.getElementById('slide-description').textContent = descriptions[index];
  canvas.setAttribute('aria-label', `Slide ${index + 1} of ${descriptions.length}: ${descriptions[index]}`);
  document.getElementById('position').textContent = `0${index + 1} / 0${descriptions.length}`;
  prev.disabled = index === 0; next.disabled = index === lastSlide;
  dots.forEach((dot, i) => i === index ? dot.setAttribute('aria-current', 'step') : dot.removeAttribute('aria-current'));
  const action = document.getElementById('slide-action');
  action.href = actions[index][1];
  action.innerHTML = `${actions[index][0]} <span aria-hidden="true">↗</span>`;
  stage.style.background = ['#165b46', '#f1f7f3', '#fbf1e5', '#edf2ff', '#f4f0fa', '#165b46'][index];
  document.getElementById('download-deck').href = slideAsset(`landing-${isPortrait() ? 'tall' : 'wide'}.pptx`);
  positionRepositoryLink();
  history.replaceState(null, '', `#${index + 1}`);
}
function go(to) {
  index = Math.max(0, Math.min(lastSlide, to));
  app?.swift.office_landing_go(index);
  update();
}
prev.addEventListener('click', () => go(index - 1));
next.addEventListener('click', () => go(index + 1));
dots.forEach(dot => dot.addEventListener('click', () => go(Number(dot.dataset.slide))));
window.addEventListener('hashchange', () => go((Number(location.hash.slice(1)) || 1) - 1));
window.addEventListener('keydown', event => {
  if (event.altKey || event.ctrlKey || event.metaKey || (app && event.target === canvas)) return;
  if (['ArrowRight', 'ArrowDown', 'PageDown'].includes(event.key)) { event.preventDefault(); go(index + 1); }
  if (['ArrowLeft', 'ArrowUp', 'PageUp'].includes(event.key)) { event.preventDefault(); go(index - 1); }
  if (event.key === 'Home') { event.preventDefault(); go(0); }
  if (event.key === 'End') { event.preventDefault(); go(lastSlide); }
});
// Navigation works on the rendered slide previews while the live app starts.
let touchStart;
stage.addEventListener('pointerdown', event => { if (!app) touchStart = { x: event.clientX, y: event.clientY }; });
stage.addEventListener('pointerup', event => {
  if (app || !touchStart) return;
  const dx = event.clientX - touchStart.x, dy = event.clientY - touchStart.y;
  touchStart = null;
  if (Math.abs(dx) > 40 && Math.abs(dx) > Math.abs(dy)) go(index + (dx < 0 ? 1 : -1));
});
stage.addEventListener('pointercancel', () => { touchStart = null; });
new ResizeObserver(() => {
  const nextPortrait = isPortrait();
  if (portrait !== nextPortrait) {
    portrait = nextPortrait;
    app?.swift.office_landing_portrait(portrait ? 1 : 0);
    update();
  }
  positionRepositoryLink();
}).observe(canvas);
update();
document.getElementById('retry').addEventListener('click', () => location.reload());
try {
  const response = await fetch('runtime.json', { cache: 'no-cache' });
  if (!response.ok) throw new Error(`Presentation runtime: ${response.status}`);
  const config = await response.json();
  const { startStarling } = await import(`./${config.base}starling.js`);
  app = await startStarling({
    canvas, captureTab: false, app: `${config.base}app.wasm.gz`, skwasmBase: `${config.base}skwasm/`,
    fonts: `${config.base}fonts/manifest.json`,
    initialRoute: `/office-landing${isPortrait() ? '/portrait' : ''}`,
    initialFiles: [
      { name: 'landing-wide.pptx', url: slideAsset('landing-wide.pptx') },
      { name: 'landing-tall.pptx', url: slideAsset('landing-tall.pptx') },
    ],
    onPhase: () => { status.textContent = 'Starting live slides…'; },
    onFontStatus: ({ pending, failed }) => {
      if (app) status.textContent = failed.length ? 'A font could not load. Refresh to retry.' : pending.length ? 'Loading presentation fonts…' : '';
    },
  });
  window.starling = app;
  // Wait for the Swift widget tree before sending embed controls.
  const deadline = performance.now() + 15000;
  while (!app.debug('landing')) {
    if (performance.now() > deadline) throw new Error('Presentation did not become ready');
    await new Promise(resolve => setTimeout(resolve, 50));
  }
  app.swift.office_landing_portrait(isPortrait() ? 1 : 0);
  await new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)));
  app.swift.office_landing_go(index);
  await new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)));
  stage.classList.add('live');
  status.textContent = '';
  document.title = 'Starling Desktop — one desktop, many possibilities';
  setInterval(() => {
    const state = JSON.parse(app.debug('landing'));
    if (state && state.index !== index) { index = state.index; update(); }
  }, 100);
} catch (error) {
  console.error(error);
  status.textContent = 'Slide previews are available. Live playback could not start.';
  document.getElementById('retry').hidden = false;
}
