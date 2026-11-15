# OMANOVA 0.1.4 — final sky tools and easier observing

This release brings the final four sky tools together with the usability and
observing-log improvements made since 0.1.3. It is a GitHub release only.
**Marketplace is on hold:** withdrawn #14863 stays closed and the existing
listing is unchanged. No new marketplace submission accompanies this release.

## New since 0.1.3

- **Star Chart:** a whole-sky, zenith-centred map at a chosen location/time.
  920 bright catalogue stars, proper motion, selected constellation guide lines,
  plus Sun, Moon, Mercury, Venus, Mars, Jupiter and Saturn above the geometric
  horizon. Active location / Trip Home / Trip destination, saved manual and
  enabled terrain horizons, tap-to-inspect bearing/elevation. North up, east
  left when looking up. Daylight/visibility caveats; no telescope-pointing claim.
- **Live Orbit:** calculated ISS/Tiangong footprints and surrounding ground
  tracks; recomputed from cached elements every ten seconds while open.
  True bearing, elevation, slant range in preferred units, sunlight/sky state,
  epoch and age. Stale (>48 h) or future (>6 h) elements withhold markers.
  This is SGP4 propagation, not telemetry. Ordinary Orbit retains its pass
  selection, tracks and scrubber. Obstructions/weather remain separate here.
- **Polar Alignment:** true pole direction/altitude, Polaris or southern
  Sigma Octantis / Polaris Australis offset, date-of-observation orientation
  and upright sky diagram. For EQ mounts/star trackers, with near-equatorial,
  faint southern reference and optical inversion/rotation limits. Shows a
  blocked reference star. Not an optical reticle, plate solver or mount control.
- **Station Transits:** explicit local search for exact-site Sun/Moon
  alignments using cached ISS/Tiangong elements. Up to 24 h, curtailed at each
  station's 24 h element-age limit; reject elements >1 h in the future.
  Show close approaches within 2° separately from model disc crossings.
  Apparent topocentric rays, station light time, model contacts/duration,
  local-zone and UTC times, bearing/elevation and saved horizons. All crossings
  remain **UNCONFIRMED**. No calibrated timing/location accuracy or reliable
  ground corridor. Numerical 2 ms refinement does not imply real-world accuracy.
  Appropriate front-mounted solar optical filters and independent rechecks
  are required; eclipse glasses alone are unsafe through optics.
- **Navigation:** all 28 views in six groups, stable page identifiers and a
  narrow-window selector. Existing event and numeric IPC references retained.
- **Overview:** local Sun/Moon night strip, sunset/sunrise, matching cached
  cloud cover and up to five eligible recommendations, best first then time
  order. Unknown/stale gaps remain explicit. No new network requests; the
  strip does not apply saved active-location horizons or promise visibility.
- **Consistent interface:** shared headings/actions/pass sliders, padded
  compact fallback, expandable ranking/estimate details and one header display
  selector. Ctrl+D cycles normal/dim/red without changing desktop brightness.
- **Runtime clarity:** installed/running version, source revision, snapshot
  and planning freshness. Detect clock/build mismatches. Guided setup and
  archives record source identity; a fresh snapshot is not proof every feed
  is fresh. Source identity is support metadata, not an authenticity guarantee.
- **I saw it:** Overview and unified Events open editable drafts using the
  active place and actual click time/UTC offset. Explicit Save is required;
  no scheduled pass becomes a confirmed observation automatically. Drafts
  survive page navigation, with keep/replace choice for another event. Save
  before closing; crash/close draft persistence is not implemented.
- **CSV export:** export saved log rows only to private, unique local UTF-8
  files. Unicode/multiline quoting, BOM, formula-cell escaping in export only,
  no source-log mutation or overwrite. Contains private places/notes; sharing
  is separate. Relative export receipts avoid displaying personal full paths.

## All existing functionality retained

- Informative bar with next station pass and poor-weather/status fallbacks;
  left-click Observatory, middle-click compact panel, kilometre/mile option.
- ISS/Tiangong and bright/custom LEO watchlists, pass directions/scrubbing,
  sunlight/darkness tests, Starlink train uncertainty and opt-in pass alerts
  with configurable lead times and quiet hours. Stale inspection never GO.
- Moon phase graphic/illumination/rise/set, named full Moons and
  supermoon/micromoon classification, meteors including activity dates/peaks,
  planets/conjunctions, dated comets and solar/lunar eclipses with local windows.
- Launch schedules, uncertain twilight plumes, launch favourites and opt-in
  delay/hold/explicit scrub alerts, change history and provider webcast links.
  Launch-following monitoring requires the Observatory open.
- NOAA aurora guidance with missing/stale uncertainty; broader weather
  assessments using opt-in forecasts, source age and conservative visibility.
- Manual/saved/temporary locations and explicitly requested online place lookup;
  no automatic geolocation. Coordinates/settings on bounded stdin, not argv.
- Trip Planner destination/date versus Home comparison, both time zones,
  manual trees/buildings, observing height and separately opted-in terrain.
- Regional/destination dark-sky sites with distances/access/darkness evidence;
  curated samples, not complete global coverage or access permission.
- Equipment preferences and manual sky quality, optional aperture/FOV/binocular
  power/camera context, explained filters across Overview/calendar/cards.
- Calendar `.ics` snapshots with explicit selection and optional reminders;
  no calendar account, automatic invitations or live subscriptions.
- Immutable offline night cards, JSON and printable self-contained HTML,
  directions/times/equipment and explicit aged timing/weather; Trip sources
  and saved matching horizons. Old guides never silently recompute.
- Local observing log, theme following and normal/dim/red appearance.
- Guided automatic runtime/widget setup, checksum-bound NASA kernel and pinned
  Python dependencies, hidden worker, readiness/discovery checks and optional
  login startup. New installs default autostart **off**; upgrades preserve choice.

[Full options and setup](../README.md) · [Changelog](../CHANGELOG.md) ·
[Ten new native screenshots](SCREENSHOTS-0.1.4.md) ·
[Previous gallery including terrain](SCREENSHOTS-0.1.3.md)

## Install and upgrade

```sh
git clone --branch v0.1.4 https://github.com/shaggyrs6-netizen/omanova.git
cd omanova
./install
```

Optional login startup: `./install --autostart`. Existing users: back up local
saved data, stop worker/close Observatory, check out the release in the existing
runtime checkout, then `./install`. This restarts the hidden worker with matching
source. Reload the shell and reopen Observatory. Follow the full README upgrade
instructions for modified widgets/custom units; do not discard local changes.
An extracted official package uses the matching version tag for widget setup.

## Validation and limits

207 Python tests and 11 JavaScript checks passed. Numerical fixtures cover
published Vallado SGP4 vectors, an independent WGS84 ray/ellipsoid construction
for both solar ISS and lunar Tiangong alignments, a separate 1 ms transit scan,
contacts, saved obstructions, stale/future suppression, moving positions and
both hemispheres. These are engineering checks, **not observed-transit accuracy
validation**. Public orbits can be kilometres out at epoch: all candidates stay
unconfirmed and require independent current verification before real observing.

Native checks cover all four views, rapid navigation, 440×700 layout, normal/red
readability and public-sample screenshots. New installer/archive identity checks
and existing simulated clean/upgrade/default-off/opt-in tests are included.
Release archive extraction, real isolated pinned-runtime setup, archive tests
and saved-data-preserving upgrade checks are recorded with the local release.
No physical reboot/suspend was repeated: the earlier iMac login and maintainer
sleep/resume checks remain the existing evidence. Real calendar imports/reminders,
printing/offline-device readability and live launch changes still depend on
ordinary use. Synthetic notification visual confirmation remains tentative;
no unsolicited notifications were sent for this release.

Comet data coverage remains **2026-12-12T00:00Z**, checked in-date for this release;
brightness is a dated estimate, not a live measurement. Normal feed/catalogue,
site evidence, dependency and compatibility maintenance continues. No further
feature programme or desktop-shell work is included.

## Licence

Original code: MIT. Bright-star subset: adapted HYG v4.0 by David Nash /
Astronexus, **CC BY-SA 4.0**, separately attributed in
[HYG-LICENSE.md](../observatory/final_sky/HYG-LICENSE.md).
Other data/dependencies retain their existing attribution in DATA-SOURCES.md.
