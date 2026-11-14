# OMANOVA 0.1.3 — observing at home and away

OMANOVA 0.1.3 adds tools for choosing what to observe, following launches and
taking a viewing plan outside. It includes the existing guided installer,
hidden worker, optional login startup, Trip Planner and terrain horizons.

This is a **GitHub release only**. Marketplace update request #14863 has been
withdrawn while the newer build was tested. The existing marketplace listing
is unchanged; this release does not submit a replacement review request.

## New since 0.1.2

- **Desktop theme support:** opt into the current Omarchy palette in the
  Observatory and compact fallback. Changes are watched; missing/invalid
  colours fall back safely. Normal/dim/red display controls preserve readable
  text and status labels. No desktop-theme or monitor-brightness changes.
- **Launch Following:** favourite up to five missions; separately opt into
  downloads and delay/hold/explicit scrub or cancellation alerts. View change
  history and provider-supplied HTTPS webcasts. Cache limits, retry budgets,
  baseline resets and duplicate suppression prevent catch-up spam. A missing
  launch or changed time is not treated as a scrub. **The Observatory must
  remain open for this monitoring**; it is separate from worker viewing alerts.
- **My Equipment and Sky:** choose naked eye, binoculars, telescope and/or
  camera; describe expected sky quality manually; choose filtering and whether
  to inspect uncertain/excluded entries. Add optional aperture, field of view,
  binocular magnification and wide-field/tracked camera context. These are
  conservative preferences, not measured sensitivity or exposure guarantees.
- **Shared equipment preferences:** new Overview recommendations, calendar
  selections and offline cards honour the profile. Filters cannot turn stale,
  poor-weather or unsafe events into GO. The bar and worker-alert rules retain
  their established behaviour. Invalid profiles do not silently widen matches.
- **Calendar Export:** choose events and create a private local `.ics` file.
  Includes UTC/DST-safe times, named-zone context, tentative status, equipment,
  look direction and safety/uncertainty notes. Optional 5/15/30/60-minute
  reminders start off each session. Import is manual; no calendar account,
  invitation, subscription or automatic schedule update. Up to 50 events/file.
- **Offline Cards:** save a night's guide as private immutable JSON and
  self-contained printable HTML. Reopen without live sources or network;
  capture local/UTC times, direction-at-time and equipment. Timing and weather
  age separately, with ended/stale/unknown warnings. New HTML has normal/dim/red
  controls. Existing guides keep their original context and are never rewritten.
- **Trip-aware exports/guides:** choose active location, Trip Home or Trip
  destination. Trip windows use the saved matching comparison and its manual
  and enabled terrain horizon clipping. Changed/legacy comparisons must be
  recalculated. Both zone context and UTC are explicit; raw coordinates,
  addresses and place names are omitted from exports. No implicit downloads.
- **Destination Sites:** 12 curated examples across the USA, UK, New Zealand
  and Australia; straight-line distances from active/Trip locations in km or
  miles, optional 500 km view, dated darkness/access evidence and official
  links. Not comprehensive worldwide search, driving directions or permission.
- **Small Sky Finder:** five constellation landmarks plus M31, M42, M45, M13
  and M57. Local viewing windows, a single-target compass, time-specific bearing
  and elevation, Sun/Moon context, equipment/FOV guidance and saved horizon
  clipping. Darkness estimates show astronomical and Moon-free hours, **not
  address-derived Bortle/SQM measurements**. Actual visibility stays unconfirmed.
- **Reliability:** missing planner data cannot lock away saved-guide libraries;
  creation/export revalidates sources; archive reopening never recomputes old
  predictions. Distance units update reactively in Destination Sites. Regression
  fixtures no longer depend on a maintainer's private equipment profile.

[New screenshot gallery](SCREENSHOTS-0.1.3.md) · [Full changelog](../CHANGELOG.md) ·
[All features/options and privacy details](../README.md)

## Existing features retained

ISS and Tiangong schedules/ground tracks; Moon phases, named full Moons and
size class; meteor activity/peaks; planets/conjunctions; dated comets; local
solar/lunar eclipses and safety advice; launch schedules/twilight plumes;
bright/custom satellite watchlists and Starlink trains; aurora; unified Events,
ranking and event-window weather; regional dark-sky sites; local observing log;
saved locations, city/postcode lookup and miles/km; configurable opt-in alerts,
quiet hours and lead times; Home/destination planning with both time zones;
manual horizons, observing height and opt-in terrain estimates; meaningful bar
status, poor-weather ISS labels and stale-pass inspection without GO.

## Installation and upgrades

```sh
git clone --branch v0.1.3 https://github.com/shaggyrs6-netizen/omanova.git
cd omanova
./install
```

Use `./install --autostart` only if you want login startup. Fresh installations
default off; existing choices are preserved. The guided installer prepares
pinned Python packages and the checksum-verified NASA kernel, installs the
matching widget, starts the hidden user worker and checks its fresh snapshot.
It asks before installing the distribution's uv package if absent. The separate
runtime/setup requirement remains; the bar widget alone is not the full app.

For upgrades, back up existing local data, stop the worker and close the
Observatory, fetch/check out v0.1.3 **in the existing runtime checkout**, and run
`./install`. Then run `omarchy restart shell` and reopen the Observatory. Do not
replace customised/divergent widget or service files blindly. Keep the existing
`omasky` compatibility data paths and the separate Trip, launch-follow,
equipment, calendar and offline directories. Detailed commands and limits are
in the [upgrade instructions](../README.md#upgrading-an-existing-installation).

The source archive includes the matching installer; its widget checkout is
bound to tag v0.1.3 and checked against the bundled files. The `.venv`, saved
locations/logs/favourites/guides, terrain cache and downloaded kernel are not
included. Setup obtains dependencies/kernel separately. SHA256SUMS and
SOURCE-COMMIT.txt accompany the release archive. Existing v0.1.2 assets and tag
are preserved.

## Validation and practical limits

187 Python tests and five JavaScript checks passed. Tests cover privacy,
stale-data suppression, equipment parity across 624 fixtures, theme contrast,
trip signatures/time zones/horizons, local calendar output, immutable offline
reopening and installer control flow. Installer tests substitute external
package/session services and run real local Git/lock/file operations; they are
not a new physical clean-machine certification. Extracted-archive, runtime
setup and checksum checks are recorded alongside this release.

Previous real iMac click/reboot/login checks and the maintainer-confirmed
sleep/resume test remain completed for the installer/worker. No fresh reboot
of every new feature is claimed. Native sample screenshots were inspected;
real calendar-client reminder behaviour, physical printing/field readability,
and live launch changes depend on the client, device and provider. Synthetic
notification delivery/deduplication passed; earlier visual confirmation was
tentative. No unsolicited test alerts are sent by release preparation.

Comet positions currently end at **12 December 2026, 00:00 UTC**; brightness is
approximate. Terrain, plumes, trains, aurora and all viewing guidance retain
source-age and uncertainty limits. No confirmed sighting, surveyed horizon,
precise light-pollution measurement or universal instrument model is promised.
