// Use the existing starling.build Web Analytics property for both Office sites.
// Local previews do not report traffic, and an injected beacon is not duplicated.
(() => {
  if (!["office.starling.build", "openoffice.starling.build"].includes(location.hostname)) return;
  if (document.querySelector('script[data-cf-beacon]')) return;
  const analytics = document.createElement("script");
  analytics.src = "https://static.cloudflareinsights.com/beacon.min.js";
  analytics.defer = true;
  analytics.dataset.cfBeacon = JSON.stringify({
    token: "44d0e97496854c03b38f4c06ed50f5a8",
  });
  document.head.append(analytics);
})();
