// System-wide Firefox defaults for the cloud desktop.
// Keep this file in sync with desktop/firefox-user.js.

// --- Startup and home page -------------------------------------------------
pref("browser.shell.checkDefaultBrowser", false);
pref("browser.aboutwelcome.enabled", false);
pref("browser.startup.homepage_override.mstone", "ignore");
pref("browser.startup.page", 1);
pref("browser.startup.homepage", "file:///opt/desktop/welcome.html");
pref("browser.newtabpage.enabled", false);
pref("browser.newtabpage.activity-stream.feeds.section.topstories", false);
pref("browser.newtabpage.activity-stream.showSponsored", false);
pref("browser.newtabpage.activity-stream.showSponsoredTopSites", false);
pref("browser.newtabpage.activity-stream.feeds.telemetry", false);
pref("browser.newtabpage.activity-stream.telemetry", false);
pref("browser.tabs.warnOnClose", false);
pref("browser.tabs.warnOnOpen", false);
pref("browser.warnOnQuit", false);
pref("browser.sessionstore.resume_from_crash", false);
pref("browser.tabs.animate", false);
pref("browser.fullscreen.animate", false);

// --- Memory and process model ----------------------------------------------
pref("dom.ipc.processCount", 2);
pref("browser.tabs.remote.autostart", true);
pref("browser.tabs.remote.autostart.2", true);
pref("browser.tabs.unloadOnLowMemory", true);
pref("browser.cache.memory.capacity", 65536);
pref("browser.cache.disk.enable", true);
pref("browser.cache.disk.capacity", 51200);
pref("browser.cache.disk.smart_size.enabled", false);
pref("browser.sessionstore.interval", 60000);
pref("browser.sessionhistory.max_total_viewers", 2);
pref("browser.sessionstore.restore_tabs_lazily", true);
pref("browser.sessionstore.restore_on_demand", true);

// --- Network: fewer speculative connections over a latency-bound link ------
pref("network.http.max-persistent-connections-per-server", 4);
pref("network.http.max-connections", 64);
pref("network.prefetch-next", false);
pref("network.dns.disablePrefetch", true);
pref("network.predictor.enabled", false);
pref("network.http.speculative-parallel-limit", 0);
pref("browser.search.suggest.enabled", false);
pref("browser.urlbar.suggest.searches", false);
pref("browser.urlbar.suggest.quicksuggest.nonsponsored", false);
pref("browser.urlbar.suggest.quicksuggest.sponsored", false);

// --- Rendering: software, low animation, no GPU assumptions ----------------
pref("layers.acceleration.disabled", true);
pref("gfx.webrender.software", true);
pref("gfx.canvas.accelerated", false);
pref("media.hardware-video-decoding.enabled", false);
pref("general.smoothScroll", false);
pref("general.smoothScroll.msdPhysics.enabled", false);
pref("ui.systemUsesDarkTheme", 1);
pref("widget.non-native-theme.enabled", true);
pref("layout.css.devPixelsPerPx", "1.0");

// --- Privacy / background work ---------------------------------------------
pref("datareporting.policy.dataSubmissionEnabled", false);
pref("datareporting.healthreport.uploadEnabled", false);
pref("toolkit.telemetry.enabled", false);
pref("toolkit.telemetry.unified", false);
pref("toolkit.coverage.enabled", false);
pref("toolkit.coverage.endpoint.base", "");
pref("app.update.enabled", false);
pref("app.update.auto", false);
pref("extensions.update.enabled", false);
pref("extensions.pocket.enabled", false);
pref("identity.fxaccounts.enabled", false);
pref("browser.discovery.enabled", false);
pref("app.shield.optoutstudies.enabled", false);
pref("browser.ping-centre.telemetry", false);

// --- Arabic UI -------------------------------------------------------------
pref("intl.locale.requested", "ar");
pref("intl.accept_languages", "ar, en-US, en");
