# OMANOVA — release validation and maintenance

## Current release: 0.1.3 — 14 November 2026

The completed feature build is authorised for GitHub publication. See
[0.1.3 release notes](docs/RELEASE-0.1.3.md), [CHANGELOG](CHANGELOG.md) and the
[new screenshot gallery](docs/SCREENSHOTS-0.1.3.md). Marketplace update request
#14863 was withdrawn and closed; the existing listing is not changed. This
release does not submit a replacement marketplace request.

187 Python tests and five JavaScript checks passed. Release archives are
tracked-source-only, version 0.1.3, with matching source commit and checksums.
The archive installer uses tag v0.1.3; it must not be distributed as v0.1.2.
Private state, caches, venv and downloaded ephemeris stay out of the package.
No main-PC worker/autostart setting is changed by release preparation.

Remaining practical limits: calendar import/reminders depend on the receiving
client; actual printing/offline-device readability and live launch changes
need ordinary use. Synthetic notification delivery/deduplication passed, but
visual confirmation was tentative. Previous physical iMac startup and
maintainer-confirmed sleep/resume checks are retained, not newly repeated.
Comet coverage ends at 2026-12-12T00:00Z; this release does not extend it.

## Historical 0.1.2 validation record

The record below concerns the earlier release, not the current publication state.

12 November 2026. The accepted terrain integration completes this feature pass.
GitHub source and release publication are authorised; marketplace submission
or update is not. This document records validation limits and maintenance
follow-up. The complete user-facing change list is in [CHANGELOG.md](CHANGELOG.md).

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

- Sleep/resume: passed, confirmed by the maintainer on 12 November 2026. Removed from
  the outstanding list. This records his hands-on check; no additional
  instrumented suspend/resume test was run in this documentation update.

## Validation and maintenance follow-up

1. The terrain preview was accepted and installed for local use. Preserve
   manual horizons and saved data during upgrades; terrain downloads remain explicit.
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
6. GitHub publication is authorised for 0.1.2. Do not submit, comment on or
   update the marketplace as part of this release. Any later marketplace
   action needs a separate instruction.

## Local packaging

Run `./package-local` from a clean committed checkout. It archives tracked
files from HEAD only; no private settings, logs, terrain tiles, `.preview`,
virtual environment or downloaded ephemeris are included. The output is a
new directory under `.preview/release-candidates/`, containing the source
archive, SHA256 checksum, exact source commit and included-file inventory.
It does not install, start services, access a remote or publish anything.

The archive includes the automatic installer. The archive installer obtains its
matching version tag and compares widget bytes. Before publishing a new tag,
test from a local Git checkout rather than relying on an unpublished remote tag. Tests stub external system
services and exercise real local Git/file operations. A local archive is not
proof of a published version or full clean-machine acceptance.
