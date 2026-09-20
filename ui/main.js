(() => {
  if (['starling.build', 'www.starling.build'].includes(location.hostname)) {
    const analytics = document.createElement('script');
    analytics.src = 'https://static.cloudflareinsights.com/beacon.min.js';
    analytics.defer = true;
    analytics.dataset.cfBeacon = JSON.stringify({token: '44d0e97496854c03b38f4c06ed50f5a8'});
    document.head.append(analytics);
  }
  const modes = {
    '2d': {src: 'img/desktop-2d.webp', alt: 'Starling’s empty 2D desktop, with a sunset city wallpaper, status bar, and familiar app dock.', label: 'YOUR FAMILIAR WORKSPACE', caption: 'The desktop you know. A familiar place to begin.'},
    '3d': {src: 'img/desktop-3d.webp', alt: 'Starling’s empty 3D desktop: a walkable city overlooking the waterfront and a red suspension bridge.', label: 'THE CITY IS YOUR WORKSPACE', caption: 'Step into the city. Change your point of view.'}
  };
  const image = document.querySelector('#desktop-image');
  document.querySelectorAll('[data-mode]').forEach(button => {
    button.disabled = false;
    button.addEventListener('click', () => {
      const mode = modes[button.dataset.mode];
      image.src = mode.src;
      image.alt = mode.alt;
      document.querySelector('#scene-name').textContent = mode.label;
      document.querySelector('#mode-caption').textContent = mode.caption;
      document.querySelectorAll('[data-mode]').forEach(item => item.setAttribute('aria-pressed', String(item === button)));
    });
  });
  const video = document.querySelector('#demo-video');
  const playButton = document.querySelector('#film-play');
  playButton.hidden = false;
  let pendingSeek;
  async function playFilm(time) {
    playButton.hidden = true;
    // Start playback inside the click gesture so mobile browsers can allow sound.
    const playback = video.play();
    if (pendingSeek) video.removeEventListener('loadedmetadata', pendingSeek);
    if (typeof time === 'number') {
      const seek = () => { video.currentTime = time; pendingSeek = undefined; };
      if (video.readyState > 0) seek();
      else {
        pendingSeek = seek;
        video.addEventListener('loadedmetadata', seek, {once: true});
      }
    }
    try { await playback; } catch { playButton.hidden = false; }
  }
  playButton.addEventListener('click', () => {video.focus({preventScroll: true}); playFilm();});
  video.addEventListener('play', () => {playButton.hidden = true;});
  video.addEventListener('ended', () => {playButton.hidden = false;});
  video.addEventListener('error', () => {playButton.hidden = true;});
  document.querySelectorAll('[data-time]').forEach(button => button.addEventListener('click', event => {event.preventDefault(); playFilm(Number(button.dataset.time));}));
  document.querySelectorAll('[data-film-time]').forEach(link => link.addEventListener('click', () => playFilm(Number(link.dataset.filmTime))));
})();
