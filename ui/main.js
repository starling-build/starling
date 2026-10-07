(() => {
  const slides = [...document.querySelectorAll('main > .slide')];
  const previous = document.getElementById('previous');
  const next = document.getElementById('next');
  const dots = [...document.querySelectorAll('[data-slide]')];
  const action = document.getElementById('slide-action');
  const dialogs = [...document.querySelectorAll('dialog')];
  let index = 0;
  function go(to) {
    index = Math.max(0, Math.min(slides.length - 1, to));
    slides.forEach((slide, i) => { slide.hidden = i !== index; });
    const slide = slides[index];
    previous.disabled = index === 0;
    next.disabled = index === slides.length - 1;
    dots.forEach((dot, i) => i === index ? dot.setAttribute('aria-current', 'step') : dot.removeAttribute('aria-current'));
    document.getElementById('position').textContent = `${String(index + 1).padStart(2, '0')} / ${String(slides.length).padStart(2, '0')}`;
    action.href = slide.dataset.href;
    action.replaceChildren(document.createTextNode(`${slide.dataset.action} `));
    const arrow = document.createElement('span');
    arrow.textContent = '↗'; arrow.setAttribute('aria-hidden', 'true'); action.append(arrow);
    document.body.dataset.slide = slide.id;
    history.replaceState(null, '', `#${slide.id}`);
  }
  function openDialog(id) {
    const dialog = document.getElementById(id);
    if (!dialog) return;
    dialogs.forEach(item => { if (item.open && item !== dialog) item.close(); });
    if (!dialog.open) dialog.showModal();
  }
  function route(hash) {
    const name = hash.replace(/^#/, '');
    if (['film', 'desktop-film', 'install', 'desktop-install'].includes(name)) {
      go(slides.findIndex(slide => slide.id === 'desktop'));
      openDialog(name.includes('film') ? 'desktop-film' : 'desktop-install');
      return;
    }
    const named = slides.findIndex(slide => slide.id === (name === 'perspectives' ? 'desktop' : name));
    go(named >= 0 ? named : /^\d+$/.test(name) ? Number(name) - 1 : 0);
  }
  document.body.classList.add('is-presentation');
  route(location.hash);
  previous.addEventListener('click', () => go(index - 1));
  next.addEventListener('click', () => go(index + 1));
  window.addEventListener('hashchange', () => route(location.hash));
  document.addEventListener('click', event => {
    const link = event.target.closest('a[href^="#"]');
    if (!link || link.getAttribute('href') === '#main') return;
    const hash = link.getAttribute('href');
    if (slides.some(slide => `#${slide.id}` === hash) || ['#film', '#install'].includes(hash)) {
      event.preventDefault(); route(hash);
    }
  });
  window.addEventListener('keydown', event => {
    if (event.defaultPrevented || dialogs.some(dialog => dialog.open) || event.altKey || event.ctrlKey || event.metaKey || event.target.closest('input,textarea,select,[contenteditable]')) return;
    const movement = {ArrowRight: 1, ArrowDown: 1, PageDown: 1, ArrowLeft: -1, ArrowUp: -1, PageUp: -1};
    if (event.key in movement) { event.preventDefault(); go(index + movement[event.key]); }
    if (event.key === 'Home') { event.preventDefault(); go(0); }
    if (event.key === 'End') { event.preventDefault(); go(slides.length - 1); }
  });
  let touchStart;
  const main = document.getElementById('main');
  main.addEventListener('pointerdown', event => {
    if (event.pointerType !== 'touch' || event.target.closest('a,button,video')) return;
    touchStart = {x: event.clientX, y: event.clientY};
  });
  main.addEventListener('pointerup', event => {
    if (!touchStart) return;
    const dx = event.clientX - touchStart.x, dy = event.clientY - touchStart.y;
    touchStart = null;
    if (Math.abs(dx) > 55 && Math.abs(dx) > Math.abs(dy) * 1.3) go(index + (dx < 0 ? 1 : -1));
  });
  main.addEventListener('pointercancel', () => { touchStart = null; });
  dialogs.forEach(dialog => {
    dialog.querySelector('.dialog-close').addEventListener('click', () => dialog.close());
    dialog.addEventListener('click', event => {
      if (event.target !== dialog) return;
      const rect = dialog.getBoundingClientRect();
      if (event.clientX < rect.left || event.clientX > rect.right || event.clientY < rect.top || event.clientY > rect.bottom) dialog.close();
    });
  });

  const modes = {
    '2d': {src: 'img/desktop-2d.webp', alt: 'Starling’s 2D desktop, with a sunset city wallpaper, status bar, and app dock.', label: 'YOUR FAMILIAR WORKSPACE', caption: 'The desktop you know. A familiar place to begin.'},
    '3d': {src: 'img/desktop-3d.webp', alt: 'Starling’s 3D desktop, a walkable waterfront city.', label: 'THE CITY IS YOUR WORKSPACE', caption: 'Step into the city. Change your point of view.'}
  };
  const image = document.getElementById('desktop-image');
  document.querySelectorAll('[data-mode]').forEach(button => {
    button.disabled = false;
    button.addEventListener('click', () => {
      const mode = modes[button.dataset.mode];
      image.src = mode.src; image.alt = mode.alt;
      document.getElementById('scene-name').textContent = mode.label;
      document.getElementById('mode-caption').textContent = mode.caption;
      document.querySelectorAll('[data-mode]').forEach(item => item.setAttribute('aria-pressed', String(item === button)));
    });
  });
  const video = document.getElementById('demo-video');
  const playButton = document.getElementById('film-play');
  playButton.hidden = false;
  let pendingSeek;
  async function playFilm(time) {
    playButton.hidden = true;
    const playback = video.play();
    if (pendingSeek) video.removeEventListener('loadedmetadata', pendingSeek);
    if (typeof time === 'number') {
      const seek = () => { video.currentTime = time; pendingSeek = undefined; };
      if (video.readyState > 0) seek();
      else { pendingSeek = seek; video.addEventListener('loadedmetadata', seek, {once: true}); }
    }
    try { await playback; } catch { playButton.hidden = false; }
  }
  playButton.addEventListener('click', () => { video.focus({preventScroll: true}); playFilm(); });
  video.addEventListener('play', () => { playButton.hidden = true; });
  video.addEventListener('ended', () => { playButton.hidden = false; });
  video.addEventListener('error', () => { playButton.hidden = true; });
  document.getElementById('desktop-film').addEventListener('close', () => video.pause());
  document.querySelectorAll('[data-time]').forEach(link => link.addEventListener('click', event => {event.preventDefault(); playFilm(Number(link.dataset.time));}));
  if (['starling.build', 'www.starling.build'].includes(location.hostname)) {
    const analytics = document.createElement('script');
    analytics.src = 'https://static.cloudflareinsights.com/beacon.min.js';
    analytics.defer = true;
    analytics.dataset.cfBeacon = JSON.stringify({token: '44d0e97496854c03b38f4c06ed50f5a8'});
    document.head.append(analytics);
  }
})();
