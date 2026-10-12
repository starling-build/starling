// Native links, scrolling, and text work without JavaScript. Keep old public
// presentation URLs useful now that Desktop has a regular web page of its own.
(() => {
  const legacy = {
    film: "film",
    "desktop-film": "film",
    install: "install",
    "desktop-install": "install",
    perspectives: "perspectives",
  };
  const target = legacy[location.hash.slice(1)];
  if (target) location.replace(`desktop/#${target}`);
  if (["starling.build", "www.starling.build"].includes(location.hostname)) {
    const analytics = document.createElement("script");
    analytics.src = "https://static.cloudflareinsights.com/beacon.min.js";
    analytics.defer = true;
    analytics.dataset.cfBeacon = JSON.stringify({
      token: "44d0e97496854c03b38f4c06ed50f5a8",
    });
    document.head.append(analytics);
  }
})();
