# Changelog

## Unreleased — local observing completion

Held locally on a separate branch; the submitted/public 0.1.2 snapshot is unchanged.

- Follow desktop theme, plus readable normal/dim/red modes in the Observatory and compact fallback. The normal display restores the chosen theme; screen brightness remains a device setting. New portable guides have their own display controls.
- Launch following: favourites, explicit download/alert consent, delay/hold/scrub distinctions, validated webcast links, bounded cache/request budgets and no catch-up alerts. Monitoring requires the Observatory to remain open.
- My Equipment and Sky: additive equipment choices, manual sky description, optional aperture/FOV/binocular power/camera context, explicit uncertainty and profile exclusions. Overview and new calendar/offline selections now honour those preferences; bar and existing alert rules are unchanged. No invented limiting magnitude or exposure guarantee.
- Calendar Export: local private .ics snapshots, explicit event selection, UTC/DST-safe times, safety/uncertainty labels and per-session opt-in reminders. No calendar account, invitation or live subscription.
- Offline Cards: immutable private JSON/self-contained printable HTML guides with local/UTC times, direction-time labels, equipment guidance, separate timing/weather age checks and offline reopening. Saved guides retain their original context.
- Trip Home/destination sources for calendar/cards use an explicitly saved comparison, including manual and enabled terrain horizon clipping. A configuration/terrain signature rejects changed or legacy comparisons until recomputed. No implicit new network calls. Exported data omit place names, addresses and coordinates.
- Destination Sites: 12 curated regional/international examples, ordered by local straight-line distance from active/Trip locations, with dated darkness/access evidence and official links. Not a comprehensive search, driving route or access guarantee.
- Sky Finder: five constellation landmarks and five starter deep-sky targets, local windows/directions, a single-target compass, Moon context, equipment/FOV notes and saved-horizon clipping. Geometry remains unconfirmed for actual visibility.
- Estimated astronomical/Moon-free darkness is calculated locally. Background light pollution/Bortle/SQM remains unknown unless separately documented; manual sky quality is retained.
- Missing planner data does not lock away saved guide libraries. New guide creation and export revalidate source age; archive reopening never silently recalculates predictions.

Source/runtime/installer remain local. A new version/tag/public archive requires a later release decision; no update to marketplace review scope is implied.

## 0.1.2 — 12 November 2026

OMANOVA 0.1.2 adds destination planning, manual and terrain horizons, a broader
observing timeline, configurable alerts and a guided installer with a hidden
worker. It also fixes bar status, stale-data recommendations, worker recovery
and a location-privacy issue present in the 0.1.1 release.

This is the full change list relative to **v0.1.1**. The privacy fix was already
backported to `main`; 0.1.2 is the first tagged release containing it. This
GitHub release does not include a marketplace submission or review request.

### Trip Planner and My Horizon

- New integrated **Trip Planner** tab in the Observatory, with destination,
  dates, manual location entry and optional explicit place-name search.
- Compare Home and a destination over **1–14 observing nights**. Each column
  uses its own local noon-to-noon night, rather than assuming identical UTC
  intervals or a fixed 24-hour day.
- Show viewing times in **both named time zones**, including dates and UTC
  offsets. Daylight-saving transitions and repeated clock hours are handled.
- Calculate astronomical darkness, Moon-free darkness, Moon illumination,
  and viewing windows/directions for the Moon and five bright planets.
- Include station passes only where cached orbital elements remain valid;
  future dates outside that coverage ask for newer data. Meteor activity
  dates and cached launches provide additional context; neither becomes a
  guaranteed local viewing opportunity.
- Optional trip forecasts are a separate opt-in, use rounded coordinates,
  and only cover available forecast dates. Consent resets when reopening.
- Separate manual horizon profiles for observing points: name trees/buildings,
  enter true-bearing sectors and their angular height, then edit or remove
  them. North-crossing sectors are supported; overlaps use the higher edge.
- Add **observing height above ground**, defaulting to 1.7 metres. Manual
  obstruction angles are retained when height changes and should be checked
  from the new viewpoint.
- Add an opt-in **terrain horizon estimate** from public Mapzen/Tilezen Skadi
  elevation tiles. Calculation is local; the provider receives coarse regional
  tile identifiers, not an entered place name or exact coordinates.
- Display terrain in amber and manual obstructions in cyan. The higher angle
  at each bearing controls the trip's viewing window. Terrain can be disabled
  without removing manual trees or buildings.
- Cache terrain tiles and profiles for offline reuse. Changing location or
  observing height selects a different profile. Missing/invalid coverage is
  reported, not silently converted to a clear horizon.
- Terrain includes spherical Earth curvature, sampling 100 m–50 km at 100 m
  intervals and 0.5° bearings, on a nominal one-arc-second grid. This first
  version supports 70°S–70°N. It does not model atmospheric refraction,
  guarantee terrain accuracy or capture all nearby/narrow/distant obstacles.
- Trip state stays local and separate from the active observing location,
  worker alerts and observing log. Horizon masks currently affect **trip
  comparisons**, not the worker's active-location alert calculations.
- Keep standalone trip and terrain previews for isolated testing.

### Broader observing plan and weather

- Add a unified Events timeline covering station/satellite passes, Moon,
  meteors, planets, conjunctions, comets, eclipses, launches, plumes,
  Starlink trains and aurora, with event-type/time-range filtering.
- Add cross-category recommendations in Overview and the bar, with explicit
  reasoning based on timing, elevation, weather, rarity and short windows.
- Add observing-interest and minimum-elevation preferences. Globally
  interesting launches without local geometry remain unconfirmed.
- Assess weather across the event window, including longer/midnight-crossing
  windows. Missing, expired or future-dated forecasts remain uncertain.
- Run broader planning in a separate bounded process so station refreshes
  stay responsive. Reassess event freshness/weather regularly and invalidate
  planning data when the observing location changes.
- Extend the meteor catalogue to **20 selected showers**, with activity
  start/end dates and peaks through December 2027. Activity periods are
  shown alongside the existing local viewing guidance.
- Refresh the comet ephemeris catalogue through **12 December 2026, 00:00 UTC**,
  with independently dated COBS magnitude observations. Add a maintainer
  refresh tool and retain frozen regression fixtures. Magnitudes remain
  estimates; catalogue coverage is finite and needs maintenance.

### Settings, watchlists and alerts

- Add a saved **kilometres/miles** preference for supported distance displays,
  including station range and regional dark-sky-site distances. Terrain range
  and observing-height controls retain their explicit km/metre labels.
- Add explicitly requested city/postcode lookup through Open-Meteo/GeoNames,
  including time zones for Trip Planner. No automatic location tracking.
- Add named custom low-Earth-orbit satellite watchlists, up to **20 unique
  NORAD IDs**. Unknown brightness stays unconfirmed; adding an object does
  not promise it will be visible.
- Expand opt-in alerts to selected event categories, with **1–120 minute
  lead times**, a 15-minute default, minimum elevation, weather threshold
  and optional quiet hours in the computer's local time.
- Preserve station-only/favourable-weather defaults. Broader alert categories
  require explicit selection; globally unconfirmed events do not trigger
  local viewing alerts.
- Suppress stale, started and duplicate/overlapping alerts for the same
  object/location, and respect the earlier station-alert history on upgrade.
- Keep new checkbox labels readable and style new fields, spinners and
  Add/Remove controls consistently with the dark Observatory interface.
- Detect incompatible older worker capabilities before attempting newer
  settings commands, providing an upgrade message instead of failing blindly.
- Validate feed opt-ins strictly, add launch/aurora controls to shared
  settings, and keep disabled-source behaviour explicit.

### Bar, data freshness and worker reliability

- Keep meaningful bar text even when there is no viewing opportunity:
  waiting for data, setup needed, downloads paused, stale data or no window.
- Keep the next eligible ISS pass inspectable during poor weather, with
  **Poor visibility** labelling rather than a misleading favourable status.
- Preserve stale passes for geometric inspection while preventing them from
  becoming **GO** recommendations. Apply freshness safeguards to the
  Observatory, compact fallback and planner-derived recommendations.
- Recover from transient refresh errors with bounded retry backoff instead
  of allowing the foreground worker to exit after one failed update.
- Prevent duplicate workers for the same state directory with a watch lock.
  A duplicate exits with a dedicated status that the service will not loop
  trying to restart.
- Add a hidden **systemd user worker**, so a terminal window need not remain
  open. Foreground operation remains available for troubleshooting.
- Keep the redesigned compact panel as the middle-click/failure fallback.

### Guided installation and upgrades

- Add **`./install`** to prepare the Python runtime and checksum-verified NASA
  ephemeris, install/enable the matching widget, configure the hidden worker
  and verify that it produces a fresh snapshot.
- If `uv` is missing, ask before installing the distribution package. Python
  dependencies remain pinned; setup does not download an arbitrary Python
  interpreter or execute downloaded provider code.
- Login autostart is **off by default for new installs**, optional through
  **`./install --autostart`**. Existing login preferences are preserved.
- Install widget code from the exact source revision, not a moving remote
  HEAD. Release archives use their matching version tag and compare widget
  files before installing them.
- Refuse conflicting foreground workers, incompatible data/config paths,
  dirty installed widget checkouts and divergent histories without silently
  discarding changes. Installation is locked against concurrent runs.
- Wait for Omarchy to discover the widget before enabling it. This addresses
  the delayed-discovery timing observed in the iMac reboot/login tests.
- Check worker readiness before reporting success or enabling requested
  autostart. Document worker restart and shell reload during upgrades.
- Preserve saved locations, preferences and observing logs. The historical
  `omasky` data-directory name remains for compatibility; trip settings and
  horizons live separately in `omanova-trips`.

### Privacy and release tooling

- **Fix location data in process arguments:** observing-place names and
  full-precision coordinates are passed to the worker over bounded standard
  input, preventing recovery through that settings command's argument list.
  Manual/offline settings changes do not require a location download.
- Validate bounded location/preference requests and retain private local
  storage. Explicit weather/lookup/terrain requests still have their
  documented provider disclosures; this is not a claim of anonymous networking.
- Add repeatable local packaging with source commit, file inventory and
  SHA256 checksum. Release archives exclude saved locations/logs, terrain
  caches, virtual environments, preview state and the downloaded ephemeris.
- Include terrain attribution and updated source/privacy documentation.

### Validation and current limits

- The release contains **100 automated tests**, including installer control
  flow, stale-data suppression, preferences, notifications, trip dates/time
  zones, manual/terrain horizons and preservation boundaries.
- Runtime setup has been exercised in an isolated test home with fresh pinned
  dependencies and the checksum-verified local ephemeris. Installer tests
  substitute external package/session services; they are not a substitute
  for testing every Linux installation.
- Real iMac default-off/explicit-on reboot/login checks covered the installer
  timing fix. Sleep/resume was subsequently confirmed by the maintainer on
  the live PC. This does not imply every later feature was reboot-tested on
  the iMac.
- Synthetic notification delivery and deduplication passed; final visual
  confirmation remains desktop-dependent and was tentative in the local trial.
- Plume, train and aurora guidance remains experimental; missing/stale data
  stays uncertain. The dark-sky catalogue remains a regional sample, not a
  worldwide site directory. Terrain estimates are planning aids, not surveys.
- Existing astronomy views remain available: ISS/Tiangong schedules and
  ground tracks; Moon phases, illumination, named full Moons and size class;
  meteors; planets/conjunctions; comets; eclipses; launches/plumes; bright
  satellites/Starlink; aurora; dark-sky sites; and the local observing log.

### Installing or upgrading

Use the tagged [0.1.2 release](https://github.com/shaggyrs6-netizen/omanova/releases/tag/v0.1.2)
and the [README installation/upgrade instructions](README.md#install).
Existing users should back up local data, update their existing clean runtime
checkout, run `./install`, then run `omarchy restart shell` and reopen the
Observatory. Do not run an additional foreground worker alongside the service.
