# OMANOVA 0.1.5 — in-app updates and live sky satellites

This release adds two practical controls to the existing Observatory:
**Settings → OMANOVA updates** and **Sky → Star Chart → Live satellites**.
All previous features, private saved-data formats, bar and compact fallback
remain available. This is a GitHub release only: **marketplace stays on hold**.
Withdrawn #14863 is not reopened and the existing listing is unchanged.

## New: check, download and install updates

- Press **Check for updates** to query the official repository's latest stable
  published release. Checks are cached for five minutes. No automatic startup
  checks, background update schedule, prereleases or moving-main installs.
- Read expandable release notes or open the official release page. A same or
  older version cannot overwrite local development changes.
- Save your work and explicitly choose **Download & install**. An unfinished
  observing-log draft blocks installation and recovery. No real observations,
  location settings or log contents are sent to GitHub.
- Downloads use fixed official HTTPS sources, size/time limits and SHA-256
  verification. The archive's version and source identity are checked against
  the official release tag, with path/link validation and source comparison.
  Checksums provide integrity, not an independent publisher signature.
- Prepare a separate runtime with pinned Python dependencies and the existing
  checksum-bound JPL kernel before changing the running installation. The
  managed source/widget baseline refuses later local edits. No silent sudo or
  distribution package-manager installation.
- Preserve the old runtime/widget, saved-data locations, bar identity and login
  startup preference. Restart only an already-active managed worker and check
  its new snapshot identity. A foreground worker or differing service unit
  requires review. Inactive workers stay inactive; autostart is not enabled.
- Failed activation restores previous files/alias. Interrupted updates expose
  **Restore previous installation**; completed updates can also be restored
  while managed files remain unmodified. A failed detached-process launch no
  longer leaves an endless running status. Work survives closing the window;
  keep the login session active during installation.
- Guided setup registers the initial baseline. Existing unregistered/custom
  installs need review rather than an automatic overwrite. The updater finds
  the real `~/.config` widget even though Observatory has a private Quickshell
  config directory. Receipts/logs/retained copies stay under the local
  `omasky/updates/` data directory; no automatic backup cleanup.
- After success, close/reopen Observatory and reload the shell to refresh bar
  code. The app does not silently restart the whole desktop shell for you.

## New: switchable live satellites on the Star Chart

- Turn **Live satellites · Off** to **On**. This selects current time and
  recomputes locally every five seconds while the chart is open. Turning it
  off or leaving the view stops the layer calculations; ordinary worker/feed
  opt-ins retain their existing behaviour.
- Overlay calculated ISS, Tiangong and selected watchlist objects from already
  cached orbital elements. No new downloads, feed opt-ins, geolocation request
  or location transmission. Missing cache entries remain explicitly unavailable.
- Choose **Potentially visible only** or **All above horizon**. Active location,
  Trip Home and destination choices use their saved manual/terrain horizons.
- Tap a satellite diamond for true bearing, elevation, slant range in your
  km/mile preference, element age and visibility caveats. Selection survives
  refresh. Short trails show 30 seconds before to 90 seconds after calculation.
  The detail caption has reserved space to keep compass labels readable.
- Withhold elements beyond 48 h old or 6 h in the future, propagation errors,
  and layer calculations older than 15 seconds. Explain zero-marker states.
- “Potential” is geometry: sunlit, at least 10° up, above saved obstructions,
  Sun at/below −6°. Brightness, weather and actual visibility remain unconfirmed.
  Positions are SGP4 calculations, not telemetry, and never confer GO.

[New native screenshots](SCREENSHOTS-0.1.5.md) · [Full options/setup](../README.md) ·
[Changelog](../CHANGELOG.md) · [0.1.4 features and screenshots](RELEASE-0.1.4.md)

## Existing functionality retained

ISS/Tiangong predictions and informative bar; ordinary Orbit/Live Orbit and sky
compasses; bright/custom satellite watchlists and Starlink trains; Moon phases,
illumination and named full Moons; meteors, planets/conjunctions, comets,
eclipses and unconfirmed station transits; launches/webcasts, launch following
and opt-in delay/scrub alerts, uncertain twilight plumes and aurora; opt-in
weather; regional/destination dark-sky sites; Trip Planner with both zones,
manual/terrain horizons and observing height; equipment preferences; calendar
export and immutable offline guides; local observing log, I saw it drafts and
CSV export; desktop theme and normal/dim/red modes; guided setup, hidden worker,
optional default-off login startup, privacy and stale-data safeguards.

## Install / upgrade

```sh
git clone --branch v0.1.5 https://github.com/shaggyrs6-netizen/omanova.git
cd omanova
./install
```

Optional login startup: `./install --autostart`. New installations default off;
existing preferences are preserved. Existing 0.1.4 users must first follow the
README's normal guided upgrade, including saved-data backup, worker stop,
checkout in the existing runtime directory, `./install`, shell reload and
Observatory reopen. The new update button becomes available with this release;
it was not in the older public 0.1.4 package. The official archive contains exact
SOURCE-COMMIT identity and matching-tag widget installation. Custom/legacy
installs may need review rather than being forced into an incompatible layout.

## Validation and limits

**231 Python tests and 11 JavaScript checks passed** for the feature build.
Isolated synthetic tests cover update/rollback/interruption, source changes,
archive/tag/checksum guards, source clock, foreground workers, active/inactive
service preservation, detached completion and failed process launch. Native
checks cover the draft guard, simulated availability/install without real
changes, satellite marker/trail/details, refresh-stable selection, layer off,
wide and 440×700/red layouts. Maintainer live acceptance verified the actual
GitHub check and cached geometry while preserving saved data/bar and the same
active/enabled worker. No real future public upgrade was installed by those
fixture tests; receiving a release does not prove real-world observing accuracy.

Release packaging also validates extracted source, exact source identity, pinned
runtime setup and source-only contents. Real iMac reboot/login and sleep/resume
were earlier tests, not repeated for every feature release. Ordinary calendar
imports, printing/intended offline-device readability and live launch-change
experience retain their existing practical limits. No unsolicited notification
test or new desktop-shell/platform work.

Comet catalogue coverage remains **2026-12-12T00:00Z**; the satellite layer does
not refresh unrelated catalogues. Transit candidates remain UNCONFIRMED and
solar optical safety guidance remains in force. Published screenshots use
isolated public sample data. A simulated 0.1.6 in updater images is a UI fixture,
not an announcement or download of that version. Old 0.1.4 assets and galleries
remain unchanged.
