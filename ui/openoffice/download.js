// Progressive enhancement only: every download works without JavaScript.
// Browser OS hints do not reliably identify the CPU or Linux distribution.
(() => {
  const ua = navigator.userAgent || "";
  const platform =
    navigator.userAgentData?.platform || navigator.platform || "";
  const hint = document.getElementById("platform-hint");
  const tabletMac = /Mac/i.test(platform) && navigator.maxTouchPoints > 1;
  const mobile =
    /Android|iPhone|iPad|iPod/i.test(ua) ||
    tabletMac ||
    navigator.userAgentData?.mobile;

  if (mobile || /CrOS/i.test(ua)) {
    hint.textContent =
      "Use Office in your browser on this device. Desktop downloads are below.";
    document.getElementById("browser-option").hidden = false;
    return;
  }

  let os;
  if (/Win/i.test(platform) || /Windows/i.test(ua)) os = "windows";
  else if (/Mac/i.test(platform) || /Macintosh/i.test(ua)) os = "macos";
  else if (/Linux/i.test(platform) || /Linux/i.test(ua)) os = "linux";
  if (!os) return;

  const card = document.querySelector(`[data-platform="${os}"]`);
  card.dataset.detected = "true";
  card.querySelector(".download-match").hidden = false;
  card.parentElement.prepend(card);
  const messages = {
    macos:
      "Using macOS? Download the Apple silicon build below. Intel Macs can use the browser apps.",
    windows: "Using Windows? Download the 64-bit Intel / AMD package below.",
    linux:
      "Using Linux? Choose a DEB or Flatpak below for a 64-bit Intel / AMD computer.",
  };
  hint.textContent = messages[os];
})();
