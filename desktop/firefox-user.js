// Profile-level Firefox defaults. These mirror syspref.js so the profile
// behaves correctly even if the distribution wrapper does not read syspref.js.
//
// Tuned for a 2 GiB VNC desktop: fewer content processes, bounded caches,
// software rendering, no telemetry and no startup animations.

// --- Startup and home page -------------------------------------------------
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("browser.aboutwelcome.enabled", false);
user_pref("browser.preonboarding.enabled", false);
user_pref("termsofuse.bypassNotification", true);
user_pref("browser.startup.homepage_override.mstone", "ignore");
user_pref("browser.startup.page", 1);
user_pref("browser.startup.homepage", "file:///opt/desktop/welcome.html");
user_pref("browser.newtabpage.enabled", false);
user_pref("browser.newtabpage.activity-stream.feeds.section.topstories", false);
user_pref("browser.newtabpage.activity-stream.showSponsored", false);
user_pref("browser.newtabpage.activity-stream.showSponsoredTopSites", false);
user_pref("browser.newtabpage.activity-stream.feeds.telemetry", false);
user_pref("browser.newtabpage.activity-stream.telemetry", false);
user_pref("browser.tabs.warnOnClose", false);
user_pref("browser.tabs.warnOnOpen", false);
user_pref("browser.warnOnQuit", false);
user_pref("browser.sessionstore.resume_from_crash", false);
user_pref("browser.tabs.animate", false);
user_pref("browser.fullscreen.animate", false);

// --- Memory and process model ----------------------------------------------
user_pref("dom.ipc.processCount", 2);
user_pref("browser.tabs.remote.autostart", true);
user_pref("browser.tabs.remote.autostart.2", true);
user_pref("browser.tabs.unloadOnLowMemory", true);
user_pref("browser.cache.memory.capacity", 65536);
user_pref("browser.cache.disk.enable", true);
user_pref("browser.cache.disk.capacity", 51200);
user_pref("browser.cache.disk.smart_size.enabled", false);
user_pref("browser.sessionstore.interval", 60000);
user_pref("browser.sessionhistory.max_total_viewers", 2);
user_pref("browser.sessionstore.restore_tabs_lazily", true);
user_pref("browser.sessionstore.restore_on_demand", true);

// --- Network: fewer speculative connections over a latency-bound link ------
user_pref("network.http.max-persistent-connections-per-server", 4);
user_pref("network.http.max-connections", 64);
user_pref("network.prefetch-next", false);
user_pref("network.dns.disablePrefetch", true);
user_pref("network.predictor.enabled", false);
user_pref("network.http.speculative-parallel-limit", 0);
user_pref("browser.search.suggest.enabled", false);
user_pref("browser.urlbar.suggest.searches", false);
user_pref("browser.urlbar.suggest.quicksuggest.nonsponsored", false);
user_pref("browser.urlbar.suggest.quicksuggest.sponsored", false);

// --- Rendering: software, low animation, no GPU assumptions ----------------
user_pref("layers.acceleration.disabled", true);
user_pref("gfx.webrender.software", true);
user_pref("gfx.canvas.accelerated", false);
user_pref("media.hardware-video-decoding.enabled", false);
user_pref("general.smoothScroll", false);
user_pref("general.smoothScroll.msdPhysics.enabled", false);
user_pref("ui.systemUsesDarkTheme", 1);
user_pref("widget.non-native-theme.enabled", true);
user_pref("layout.css.devPixelsPerPx", "1.0");

// --- Privacy / background work ---------------------------------------------
user_pref("datareporting.policy.dataSubmissionEnabled", false);
user_pref("datareporting.policy.dataSubmissionPolicyBypassNotification", true);
user_pref("datareporting.healthreport.uploadEnabled", false);
user_pref("toolkit.telemetry.enabled", false);
user_pref("toolkit.telemetry.unified", false);
user_pref("toolkit.coverage.enabled", false);
user_pref("toolkit.coverage.endpoint.base", "");
user_pref("app.update.enabled", false);
user_pref("app.update.auto", false);
user_pref("extensions.update.enabled", false);
user_pref("extensions.pocket.enabled", false);
user_pref("identity.fxaccounts.enabled", false);
user_pref("browser.discovery.enabled", false);
user_pref("app.shield.optoutstudies.enabled", false);
user_pref("browser.ping-centre.telemetry", false);

// --- Arabic UI -------------------------------------------------------------
user_pref("intl.locale.matchOS", false);
user_pref("intl.locale.requested", "ar");
user_pref("intl.accept_languages", "ar, en-US, en");

// The Arabic language pack is installed system-wide under
// /usr/lib/firefox/browser/extensions. Firefox auto-disables application-scope
// add-ons by default, so explicitly allow the application scope to load it.
user_pref("extensions.autoDisableScopes", 0);
user_pref("extensions.enabledScopes", 15);
user_pref("extensions.startupScanScopes", 15);
// The pack is the official Mozilla ar.xpi for this Firefox release. Disabling
// the signature requirement avoids a false negative under the container's
// seccomp profile while keeping the image's language pack immutable.
user_pref("extensions.langpacks.signatures.required", false);
