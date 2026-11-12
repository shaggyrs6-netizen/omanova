# OMANOVA 0.1.2 — held local candidate

12 November 2026. Terrain preview accepted for live local installation. No publication authorised. Lee has asked for the terrain
horizon to be the last feature update for now, followed by testing,
documentation and a release decision. Do not add further feature scope.

## Included in this source

- All existing Observatory views: station passes and Orbit, Moon/named full
  Moons, meteor showers, planets/conjunctions, comets, eclipses, launch
  schedules and twilight plumes, bright/custom satellites, Starlink trains,
  aurora, regional dark-sky sites and the local observing log.
- Expanded unified timeline and recommendation ranking, configurable alerts,
  weather assessments, interests, custom LEO watchlists, meteor activity
  periods, city/postcode lookup and refreshed comet catalogue.
- Miles/kilometres, stale-pass inspection without GO, persistent informative
  bar text and poor-weather labelling, compact fallback and location privacy
  fixes (private settings input on stdin rather than process arguments).
- Trip Planner, Home/destination dates, both time zones and manual horizons.
- Integrated terrain estimates and observing height, preserving manual sectors;
  the isolated preview remains available.
- Automatic setup: `install`, `setup-runtime`, pinned requirements and
  checksum-verified NASA ephemeris, matched widget revision, discovery timing
  retry from the iMac test, worker readiness checks and hidden user service.
  Login autostart is off by default on a new install, optional with
  `./install --autostart`; an existing preference is preserved.
- Upgrade instructions include restarting the worker through `./install`
  and reloading the shell/reopening the Observatory afterwards.

## Completed acceptance checks

- Sleep/resume: passed, confirmed by Lee on 12 November 2026. Removed from
  the outstanding list. This records his hands-on check; no additional
  instrumented suspend/resume test was run in this documentation update.

## Remaining gates

1. Local trial of the accepted terrain integration; preserve existing manual
   horizons and saved data. Terrain downloads remain explicit. No further
   feature additions are planned for this release.
2. Everyday trial and any resulting fixes.
3. Clear visual confirmation of a synthetic desktop notification. Delivery
   and deduplication were tested; the earlier visual answer was tentative.
4. Rebuild the final archive from the accepted committed source, rerun
   archive and isolated installer/upgrade checks. Existing iMac reboot
   evidence applies to the earlier installer candidate, not a reboot of
   every subsequently expanded feature.
5. Recheck catalogue validity and final source/licences/package contents.
   Comet positions currently end at 2026-12-12T00:00Z; do not ship expired
   coverage as fresh. Final thumbnail/release description must reflect the
   accepted scope and distinguish estimates from confirmed visibility.
6. Lee explicitly authorises GitHub upload/release and marketplace update.
   Do not push/tag/upload merely because a local package passes tests.

## Local packaging

Run `./package-local` from a clean committed checkout. It archives tracked
files from HEAD only; no private settings, logs, terrain tiles, `.preview`,
virtual environment or downloaded ephemeris are included. The output is a
new directory under `.preview/release-candidates/`, containing the source
archive, SHA256 checksum, exact source commit and included-file inventory.
It does not install, start services, access a remote or publish anything.

The archive includes the automatic installer. Until a matching release tag
exists publicly, test setup from a local Git checkout: the archive installer
normally obtains the matching version tag and compares widget bytes. Do not
run that remote-tag path for this held candidate. Tests stub external system
services and exercise real local Git/file operations. A local archive is not
proof of a published version or full clean-machine acceptance.
