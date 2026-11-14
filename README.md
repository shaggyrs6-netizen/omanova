# OMANOVA

![OMANOVA Observatory for Omarchy. Satellite passes and alerts, Moon, planets and sky events, launches, aurora and weather, dark-sky sites and observing log.](preview.png)

OMANOVA is a local astronomy Observatory and bar widget for Omarchy Quattro.
Left-click the widget to open the resizable Observatory. Middle-click for the
compact fallback. Set your observing location manually under **Settings**.

> **Version 0.1.2:** guided setup, hidden worker, broader observing controls, Trip Planner and terrain horizons. Read the [complete changelog](CHANGELOG.md) and [release notes](https://github.com/shaggyrs6-netizen/omanova/releases/tag/v0.1.2).

## Features and options

| Area | What it offers |
| --- | --- |
| Overview, Sky View and Conditions | ISS and Tiangong countdown, pass compass and scrubber, viewing direction and elevation, forecast and source age. |
| Events | Local station opportunities, all predicted passes, and a separate launch schedule with timing precision and webcast links when supplied. |
| Orbit | ISS and Tiangong ground tracks, observer position, pass scrubber, bearing, elevation and range. |
| Moon | Phase graphic, illumination, rise and set, named next full Moon, supermoon or micromoon class and local darker-sky windows. |
| Meteor Showers | Peaks, local viewing times, radiant direction and Moon interference. |
| Planets & Conjunctions | Naked-eye planet highlights, local times and directions, and close pairings. |
| Comets | Dated catalogue, local windows and finder coordinates, with rough equipment guidance. |
| Eclipses | Solar and lunar eclipses through 2029, local windows and solar-viewing safety links. |
| Launch Plumes | Twilight geometry when a sourced timed trajectory exists. Otherwise visibility is unconfirmed. |
| Watchlist and Starlink Trains | Potential sunlit passes for bright satellites and recently tracked Starlink groups. Missing train data leaves visibility unconfirmed. |
| Aurora | NOAA-based model sightlines and a separate global Kp outlook. Missing or stale data is uncertain. |
| Dark-Sky Sites | Regional sample catalogue for Middle Tennessee and nearby states, with driving estimates, access and darkness evidence. |
| Trip Planner & My Horizon | Destination/date comparison with Home, both time zones, manual obstruction profiles and observing height. Opt-in terrain estimates combine with manual obstructions; an isolated preview remains available. |
| Observing Log | Local entries with what you saw, place, time and notes. |
| Settings and alerts | Saved and temporary locations, explicit city/postcode search, feed controls, custom watchlists and opt-in observing alerts with configurable lead times and quiet hours. |

## Screenshots

[Browse the full feature gallery](docs/SCREENSHOTS.md) — 21 actual app captures,
including terrain estimation, observing height, Trip Planner, sky events,
satellite tracking, settings and the local log. Screenshots use public sample
locations and labelled demonstration data, not live forecasts or private observations.

| Terrain skyline and manual obstructions | Home versus destination |
| --- | --- |
| [![Terrain estimate with separate manual trees and buildings](docs/screenshots/terrain-horizon.png)](docs/SCREENSHOTS.md#terrain-horizon) | [![Trip comparison with both time zones](docs/screenshots/trip-comparison.png)](docs/SCREENSHOTS.md#trip-comparison) |
| ISS and Tiangong ground tracks | Moon and named full Moons |
| [![Station ground track and observer](docs/screenshots/orbit.png)](docs/SCREENSHOTS.md#orbit) | [![Moon phase and next named full Moon](docs/screenshots/moon.png)](docs/SCREENSHOTS.md#moon) |

## Unified observing plan

Overview and the bar select a next opportunity from local station/satellite,
Moon, meteor, planet/conjunction, comet, eclipse, plume, train and aurora
windows. Events offers a combined timeline with type/range filters; the
original station/launch detail view remains available. Globally interesting
launches without local geometry stay unconfirmed and cannot become a viewing
recommendation. Geometric-only and stale entries remain inspectable.

Ranking exposes its timing, elevation, weather, event-rarity and brief-window
weights, so an all-evening target does not automatically crowd out a short pass.
User interests and minimum elevation filter recommendations. Weather is
assessed for the entire event window using the same forecast rules as station
passes; poor conditions remain visible but do not receive a recommendation.
Missing forecasts stay uncertain. Experimental plume/train/aurora guidance
keeps its caveats. Suggested look times accompany their bearings.

The hidden worker starts a separate bounded planner process so station
refreshes remain responsive. Local geometry normally refreshes every thirty
minutes (five minutes with aurora enabled); event weather and freshness are
reassessed every minute. Source adapters retain their own rate limits and
opt-ins. Planning data is local, and a changed location invalidates old results.
The individual astronomy tabs retain their detailed geometry displays.

Optional city/postcode search sends the entered query to Open-Meteo only
when **Search online** is pressed. It never reads or sends the existing
observer coordinates. Results fill the form; saving remains explicit. Place
data are based on GeoNames. No automatic geolocation is performed.

## Install

Requires Omarchy Quattro with its Quickshell and Hyprland session, system
Python 3.12 or later with compatible wheels, Git, curl, uv, jq, flock, and
`notify-send` for optional desktop alerts. The setup installs the exact
Python package versions in [requirements.txt](requirements.txt) and downloads
the NASA/JPL DE440s ephemeris over HTTPS with a SHA-256 check.

From a terminal, choose a permanent directory for the checkout:

```sh
git clone --branch v0.1.2 https://github.com/shaggyrs6-netizen/omanova.git
cd omanova
./install
```

The installer asks before installing uv if needed. It prepares the runtime,
adds the matching widget and starts the hidden worker for this session.
To also enable login startup, use `./install --autostart`. New installs
keep autostart off without that option. Open Settings to enter a location
and opt into the feeds you want.

For manual setup, run `./setup-runtime` and
`omarchy plugin add https://github.com/shaggyrs6-netizen/omanova.git --enable`.
To run the worker in a terminal, stop the service first, then use this
command and press Ctrl+C to stop:

```sh
OPENBLAS_NUM_THREADS=1 .venv/bin/python worker.py watch
```

### Optional background worker

To run without a terminal window, stop the foreground worker first. Install
the bundled user unit from the runtime checkout. If the destination already
exists, keep your existing unit and review it before making any changes.

```sh
unit_dir="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
if [ ! -e "$unit_dir/omanova-worker.service" ] && [ ! -L "$unit_dir/omanova-worker.service" ]; then
    install -Dm644 systemd/omanova-worker.service "$unit_dir/omanova-worker.service"
fi
systemctl --user daemon-reload
systemctl --user start omanova-worker.service
```

- **Start automatically at login:** `systemctl --user enable --now omanova-worker.service`
- **Stop and turn off login startup:** `systemctl --user disable --now omanova-worker.service`
- **Read the log:** `journalctl --user -u omanova-worker.service`

Starting the service alone runs it for the current user session. Use either
the service or the foreground worker. Keep your normal data-home setting
available to the systemd user manager if you use a custom `XDG_DATA_HOME`.

For an offline first look, run `./preview-observatory` from the checkout.
The fixture uses public example locations.

### Guided setup

From a permanent runtime checkout, `./install` prepares the Python
environment and ephemeris, adds and enables the matching widget, installs
the user service and starts the hidden worker. Existing login preferences
are preserved unless you explicitly enable autostart.

The installer installs the widget from the runtime checkout's Git commit
(or the matching version tag for a release archive), and checks the widget
files match before enabling it. It waits for the worker to write a fresh
snapshot before reporting success. Stop an old foreground worker before
using it. Existing runtime
links or customised service units require review before switching them.
Custom `XDG_CONFIG_HOME` locations are currently unsupported by Omarchy's
plugin installer; leave it unset or set to `$HOME/.config`.

### Upgrading an existing installation

Back up `~/.local/share/omasky/` (locations, preferences and observing log)
and `~/.local/share/omanova-trips/` if present (trip settings, manual horizons
and terrain cache). Substitute `$XDG_DATA_HOME` if you use a custom data root.

1. Stop the worker and close the Observatory. Use Ctrl+C for the foreground
   worker or `systemctl --user stop omanova-worker.service` for the service.
2. Keep the runtime checkout in place. Fetch the tags, check out the new
   release tag from a clean worktree, and run `./install` there. This upgrades
   the matching widget and starts the hidden worker; existing login startup
   preferences are preserved. Modified or diverged widget checkouts are
   refused so local changes can be reviewed first.
3. Run `omarchy restart shell` to clear cached bar code, then reopen the
   Observatory. A plugin rescan alone may leave the old bar code running.
4. If you prefer a foreground worker, stop the service and run the foreground
   command above. Starting or stopping the service leaves its login startup
   setting in place.

If upgrading from Omasky 0.1.0, point the checkout's remote at the renamed
repository before fetching. Disable the old widget with
`omarchy plugin disable io.github.shaggyrs6-netizen.omasky`, then use the
install command above to add the new widget instead of updating it.
The data directory retains its original `omasky` name so existing locations,
preferences and observing logs remain available.

## Remove

Stop the foreground worker with Ctrl+C or disable and stop the background
service as described above. Close the Observatory, then run:

```sh
omarchy plugin remove io.github.shaggyrs6-netizen.omanova
```

The plugin command leaves your local log and profiles in
`${XDG_DATA_HOME:-$HOME/.local/share}/omasky`. To retire the runtime too,
check that its `runtime` link points to this checkout, then unlink it and
move the checkout out of the way. Keep the data directory to retain your log.

## Data and privacy

Location, logs and caches stay local. The location form sends private fields
to the worker over standard input. Only opted-in Open-Meteo requests
send observer coordinates, rounded to two decimal places. Orbital requests,
launch schedules and NOAA guidance send no observer coordinates. Launch
Library 2 and NOAA downloads each require their own opt-in under Settings.
Launch downloads cover schedules and Starlink deployment lookups. Reopen
the Observatory for launch changes or reopen the Aurora tab for aurora
changes. Paused feeds may show cached data. External links open on demand. See
[Data sources and licence notes](DATA-SOURCES.md).

### Maintenance

The dated comet catalogue expires on 12 December 2026 at 00:00 UTC. Dark-sky
access and travel estimates need occasional review. Launch schedules may use
cached data if a refresh fails. Weather and astronomy are estimates and
local terrain or obstructions can change what you see.

## Preview on Omarchy

From this directory, run:

```sh
./preview
```

This opens a separate Wayland window with the actual widget and panel. Click the
bar label to open the native popout, or use the full panel already in the window.
The countdown uses a frozen 9 November 2026 clock. The preview has two named
public test locations, Nashville and Sydney. Use Settings to switch locations
or enter a temporary one. Close the window or press Ctrl+C in the terminal
to finish. The preview uses only fixture elements and local state in
`.preview/`. Its orbital and weather network controls are disabled.

## Checks

```sh
OPENBLAS_NUM_THREADS=1 .venv/bin/python -m unittest discover -s tests -v
```

The ISS test compares Nashville pass rise, culmination and set against a
one-second interpolation of NASA/JSC's independently supplied trajectory.
Tolerance is 15 seconds, 1° peak elevation and 3° bearing. The Tiangong test
compares the Sydney pass to a separate one-second scan using the same published
CelesTrak elements. Additional cases cover partial shadow, high daylight
passes, low passes, stale and expired elements, event-time weather and UTC
midnight, rounding and opt-in, temporary locations, and a throttled feed.

The Wayland smoke test exercised the fixture label, popout open/close, compass,
temporary location and restoration to a saved location. This uses an isolated
preview bar host. The widget and Observatory also ran in a live Omarchy session.

For a clean manifest validation, run `./stage-plugin .preview/plugin-check`
with a new destination. It copies only the manifest and runtime QML, then
runs Omarchy’s validator. The Python runtime stays outside the plugin folder.
The setup script links the runtime from the OMANOVA data directory.

## Runtime

The workspace-local `.venv` is prepared with the pinned dependencies in
`requirements.txt`. If rebuilding, create a virtual environment with
`uv venv --python /usr/bin/python .venv` and install with
`uv pip install --python .venv/bin/python -r requirements.txt`.
Obtain the ephemeris from
[JPL DE440s](https://ssd.jpl.nasa.gov/ftp/eph/planets/bsp/de440s.bsp) and place it
in `assets/de440s.bsp`. The tested SHA-256 is
`c1c7feeab882263fc493a9d5a5b2ddd71b54826cdf65d8d17a76126b260a49f2`.

The worker supports `refresh` for one pass and `watch` for an independent
foreground refresh loop or the optional user service. In live mode it
uses `${XDG_DATA_HOME:-$HOME/.local/share}/omasky` by default. A worker lock
serialises refreshes and edits. Settings and snapshots are written atomically
and remain private to the local user. A temporary location lasts until
selecting or saving another place. Times display in the desktop's system zone.

Orbital downloads and weather both start off. Enabling orbital downloads
permits one CelesTrak station-group request every two hours. It sends no
observer coordinates. Non-200 responses pause the adapter. Investigate first,
then use the worker's `resume-orbits` command to resume. Enabling weather also
requires network refresh and sends the active location rounded to two decimal
places to Open-Meteo. It uses hourly data around the actual viewing interval
and marks expired or incomplete coverage uncertain. The free hosted forecast
API is for non-commercial use. The feeds require no account or API key.

Orbit geometry is provisional. The initial visibility heuristic uses a 10°
elevation floor and a Sun altitude of −6° or lower. Uncertain weather can
still appear in the bar with an explicit uncertain state. Poor conditions and
elements over 72 hours from the pass stay off the bar. Elements over seven
days from the pass are excluded. Nearby obstructions, actual cloud breaks and
recent station manoeuvres can affect the result.

## Fixture provenance

- [CelesTrak stations GP JSON](https://celestrak.org/NORAD/elements/gp.php?GROUP=stations&FORMAT=JSON),
  retrieved on 9 November 2026. Only the ISS and Tianhe records are retained
  locally in the fixture. See the [provider usage policy](https://celestrak.org/usage-policy.php).
- [NASA Spot the Station trajectory](https://www.nasa.gov/spot-the-station/),
  with five sample vectors from the 6 November 2026 NASA/JSC/FOD/TOPO OEM.
  The comparison uses the trajectory feed and does not duplicate NASA's
  published city-specific sighting filters.
- [Daylight](https://github.com/nixfred/daylight.omarchy) is the interaction
  reference. OMANOVA's QML and drawings are separate implementations.

## Observatory redesign preview

Run `./preview-observatory` for the resizable native window. It uses the same
offline orbital fixtures as the original preview, with a synthetic area
forecast for the public Nashville fixture. The countdown and forecast are
examples for design review.

Overview shows the first-look direction and viewing window. In Sky View,
drag the slider or focus it and use the arrow keys to move through the pass.
Conditions shows the forecast ranges used to assess the viewing window.
Narrow windows stack the sections vertically. The preview uses its own
workspace state and leaves the live bar and worker in place.

Run `./preview-observatory --live` to read the same local snapshot as the
live bar in a separate window. The window only reads snapshots. To refresh
them, keep the worker running. A stale badge appears
when a live snapshot is more than three minutes old. Launch without
`--live` to return to the fixture preview.

The live OMANOVA widget opens or focuses the Observatory on left-click.
Middle-click opens the compact panel for location and feed settings, and
the same panel opens if the launcher exits with an error. From a terminal,
`omarchy-shell io.github.shaggyrs6-netizen.omanova compact` also opens the compact panel.
The bar shows a status between passes. If poor weather leaves no recommended
pass, it can show the next ISS countdown with a **Poor visibility** label.
Stale predictions remain available as geometry without a viewing recommendation.

## Events preview

Run `./preview-events --live` and select **Events** to use the current station snapshot
and a Launch Library 2 schedule. Launch data is cached separately in the
workspace and checked on opening, at most hourly. No observer coordinates
are sent to the launch feed. Use `./preview-events --fixture` for offline
station predictions and sample launch statuses.

Local opportunities use predicted station geometry and weather; All station
passes also shows unsuitable or stale passes and explains why. Selecting a
station pass opens its track in Sky View. Rocket launches stay separate and
display local visibility as unconfirmed until trajectory data supports it.
The preview does not change the bar, its launcher, or the live worker.

Events is available in the Observatory opened by the live bar. The launch
schedule is checked when the window starts, with the same separate cache
and rate limit as the preview. Middle-click still opens the compact panel.

## Orbit preview

Run `./preview-orbit --live` for a separate map window using the saved
observer and cached CelesTrak station elements. It recomputes the track at
launch, offline. Choose ISS or Tiangong, pick a pass, then scrub from
geometric rise to set. Ground distance is an approximate surface arc to
the station footprint. Line-of-sight range is the distance to the station.
Viewing windows describe geometry and illumination. Weather remains in
Events and Conditions.

Use `./preview-orbit --fixture` for a public Nashville test point and fixed
clock. The preview state is private and stays in the ignored workspace
preview directory. Neither preview mode changes the bar or starts a worker.
The offline basemap uses [Natural Earth 1:110m land](https://www.naturalearthdata.com/downloads/110m-physical-vectors/110m-land/).

Orbit is also available in the Observatory opened from the bar. Opening
the tab recalculates tracks locally from the cached station elements.

## Notification preview

Run `./preview-notifications` to test opt-in desktop alerts against offline
ISS and Tiangong fixtures. Enable the preview checkbox, choose a scenario
and select **Simulate pass**. A favourable pass sends one desktop notification
labelled Preview. Repeat it to test deduplication, or select a poor, missing,
stale or ended scenario to test suppression. Closing the window ends the
trial. The live worker does not consume these settings or the preview ledger.

Live alerts are opt-in under **Conditions → Observing alerts**. Settings
selects event types, a 1–120 minute lead (default 15), weather threshold,
minimum elevation and optional quiet hours in system local time. Defaults
retain station-only alerts with favourable weather; broader alerts require
explicit selection. Unconfirmed visibility never triggers an alert. The
worker reassesses once per minute, suppresses stale or already-started
windows, and deduplicates overlapping windows for the same object/location.
Alert times describe the viewing-window start; suggested bearing/elevation
include their own look time. Local history is in `observing-alerts.json`.
Existing station alert history is respected during upgrades.

## Moon preview

Run `./preview-moon --live` for offline Moon phase, illumination, rise and
set, and darker-sky viewing windows at the saved observing point.
`./preview-moon --fixture` uses a fixed clock and public Nashville point.
Viewing windows require the Moon to be at least 5° up and the Sun at or
below −6°. They describe geometry without weather or terrain. The preview
calculates at launch. Both the standalone preview and the Observatory
show common North American full-Moon names, including the Harvest
Moon nearest the September equinox, the following Hunter’s Moon, and the
second full Moon in a local calendar month as a monthly Blue Moon. It measures
geocentric distance at exact full phase. The nearest tenth of the distance
range between the surrounding perigee and apogee is a supermoon, and the
farthest tenth is a micromoon. See [Royal Observatory Greenwich’s naming
calendar](https://www.rmg.co.uk/stories/space-astronomy/full-moon-calendar-2026)
and [the orbit-relative distance rule](https://www.timeanddate.com/astronomy/moon/super-full-moon.html).

Moon is available in the Observatory opened from the bar. Opening the tab
recalculates the phase diagram, illumination and viewing windows locally.

## Meteor shower preview

Run `./preview-meteors --live` from Wayland for the saved observing point, or
`./preview-meteors --fixture` for the fixed Nashville example. The separate
window calculates offline and does not require the foreground worker.

The bundled selection covers twenty peaks from November 2026 through December 2027,
using the [2026 IMO calendar](https://www.imo.net/files/meteor-shower/cal2026.pdf)
and [2027 IMO calendar](https://www.imo.net/files/data/calendar/cal2027.pdf).
It shows the published activity dates, active-now status and peaks separately
from local dark viewing windows within
roughly a day either side. Windows require a Sun altitude of −18° or lower
and a radiant altitude of 20° or higher. Radiant coordinates are fixed at
their peak values for this short span. The Moon rows show illumination at the
highest radiant and any stretches with the Moon below the horizon. Weather,
terrain and local light pollution are outside the calculation.

## Planets and conjunctions preview

Run `./preview-planets --live` to calculate from the saved observing point,
or `./preview-planets --fixture` for the frozen Nashville example. The
standalone preview uses the existing JPL ephemeris offline. It covers the
five naked-eye planets over the next 24 hours, plus planet–planet and
Moon–planet close approaches over 30 days.

Each pairing separates Earth-centred closest approach from a local viewing
window and suggested time. Pairing limits are 5° between planets and 8°
for Moon–planet pairs. Local windows require the Sun to be at least 6° below
the horizon and each target at least 10° up. The model uses sky geometry.
Clouds, obstructions and sky brightness can change what you see.

## Comet preview

Run `./preview-comets --live` for the saved observing point or
`./preview-comets --fixture` for the frozen Nashville example. This
standalone preview contains four selected targets. Its
[JPL Horizons](https://ssd.jpl.nasa.gov/horizons/) geocentric position snapshot
runs from 9 November 00:00 UTC through 12 December 00:00 UTC, 2026.
Positions and qualified dated brightness reports were refreshed on 12 November.
Fixture mode retains its separately frozen November catalogue.
It uses two-hour observer tables (quantities 1 and 2) and interpolates
coordinates locally. Observing windows require astronomical darkness and
at least 20° elevation. Finder coordinates are J2000.

Equipment tiers use dated visual or CCD reports from the
[Comet Observation Database](https://cobs.si/recent/) as rough dark-sky
guidance. Clouds, skyglow and the diffuse coma affect actual visibility.
The bundled data expire visibly. The preview sends no observing coordinates
and does not refresh automatically.

## Eclipse preview

Run `./preview-eclipses --live` for the saved observing point or
`./preview-eclipses --fixture` for Nashville. The separate preview searches
the local JPL ephemeris through 2029. Solar windows use local apparent
Sun/Moon disc overlap. Lunar windows use Earth's shadow contacts and the
local lunar horizon. Times assume an unobstructed horizon and are approximate.

The solar cards link to [NASA's eclipse safety guide](https://science.nasa.gov/eclipses/safety/).
The preview runs offline and does not require the foreground worker.

## Settings and compact panel preview

Run `./preview-settings` in Wayland. It opens the Observatory on Settings
using sample Nashville and Sydney profiles. Try saved or temporary locations,
the orbital-download switch, weather opt-in and a one-off refresh. Select
**Show compact panel preview** to try the same controls in the restyled panel.

The two windows share isolated fixture state under `.preview/settings`.
Download choices can be exercised there without making network requests.
The installed bar and its compact fallback remain separate.

## Twilight launch plume preview

Run `./preview-plumes --live` to check the next ten Launch Library 2 entries.
The window has a separate simulated example. Run `--fixture` for an entirely
offline demonstration. The launch feed receives no observer coordinates.

The preview requires a fresh schedule, a go-for-launch status and a minute-
or second-level planned liftoff. For a real viewing window, a reviewed
`observatory/plumes/verified-tracks.json` entry must match the launch UUID and
exact schedule timestamp. Each entry has `net` (normalised UTC timestamp),
`source` (HTTPS link to the mission-specific trajectory evidence) and
`points` (ordered arrays of elapsed seconds, WGS84 latitude and longitude in
degrees, and altitude in kilometres). Include only points where exhaust is
being produced. A pad location, generic flight profile or exclusion polygon
does not establish a timed plume track.

Samples must be sunlit, at least 5° above the observer's horizon and
against a sky with the Sun at or below −6°. Runs need two consecutive
qualifying samples no more than 20 seconds apart. The output describes the
sampled geometry at the planned liftoff, with no prediction of plume
brightness or persistence. Missing, stale or mismatched evidence leaves
visibility unconfirmed. No real trajectories are bundled.

## Bright satellite watchlist preview

Run `./preview-satellites --live` for the saved observing point or
`--fixture` for the frozen Nashville example. Settings starts with seven
objects and lets you save up to twenty named NORAD IDs. The current orbit
validator supports low-Earth orbits; higher or highly eccentric orbits are
reported unavailable. Known bright objects use CelesTrak's visual catalogue;
custom objects use bounded per-ID queries and keep brightness unconfirmed. It honours
the existing orbital-download setting and sends no observing coordinates.

Filter by satellite or see all upcoming windows. A window needs sunlight
on the satellite, a local Sun altitude at or below −6°, and a satellite
elevation of at least 10°. Forecasts span up to three days and exclude
windows ending more than 72 hours from the orbital epoch. The list gives
geometry, with no model for apparent magnitude, local obstructions or weather.

## Starlink trains preview

Run `./preview-trains --live` for the saved observing point or `--fixture`
for the simulated Nashville example. The separate preview honours orbital
download consent. Recent successful Starlink launches come from Launch
Library 2, with tentative launches read from the existing cached schedule.
CelesTrak's mission-specific supplemental data associates a group number
with an international launch designator. Predictions use separately
catalogued Starlink member elements for that designator. Deployment-stack
or single-satellite placeholders alone cannot establish a train.

The experimental screen checks launches up to 14 days old and the next 24
hours of viewing geometry. It uses orbital epochs within 36 hours of each
sample. A candidate needs at least three simultaneously sunlit members at
least 15° up in a six-degree radius around one member, with the local Sun
at or below −6°. It requires consecutive ten-second samples. This screens
for compact geometry and does not estimate apparent magnitude or guarantee
that the group appears as a line. Missing data leaves visibility unconfirmed.
Calculations are local and the sources receive no observing coordinates.

## Aurora preview

Run `./preview-aurora --live` for the saved observing point or `--fixture`
for the simulated storm. The separate window uses NOAA SWPC's public
OVATION grid and planetary Kp forecast. The source receives no observing
coordinates. **Refresh forecast** checks the feeds on demand.

The local screen tests model cells at an assumed 110 km emission altitude,
requiring multiple cells at least 3° above an unobstructed horizon and a
local Sun at or below −12°. Its suggested direction is a model sightline,
with no local probability or cloud prediction. Old or missing model runs
are marked uncertain. The next three dark periods show the strongest
overlapping global Kp block, as context for when to recheck OVATION.

## Dark-sky sites preview

Run `./preview-dark-sites` in Wayland. It opens a standalone list of five
observing destinations near Mount Juliet, sorted by estimated road distance.
The drop-in filter hides sites that require a programme or booking. Links
open the public destination pin, access information and darkness evidence.

The bundled catalogue was checked on 9 November 2026. Road mileage and
driving times come from OSRM/OpenStreetMap, using the public town centre as
origin and no live traffic. Ratings distinguish site measurements, park-wide
classifications and sites without a verified numerical rating. The preview
reads its catalogue offline and does not use the saved observing address.

## Observing log preview

Run `./preview-observing-log` in Wayland. Enter what you saw, where you
were, the local date and time, and optional notes. The form starts with
the current desktop time. Saved entries are sorted by observation time
and preserve the UTC offset that applied when entered.

The preview keeps entries in a private, persistent file under
`.preview/observing-log/data/`. It makes no network requests and does not
read the live observing location or write to the live Observatory.

## Trip Planner & My Horizon

The live Observatory includes a **Trip Planner** tab with destination/date
selection, **My horizon**, and Home/destination comparison. Trip settings
are stored privately under `$XDG_DATA_HOME/omanova-trips/` (normally
`~/.local/share/omanova-trips/`), separately from saved observing locations
and the observing log. Editing Home here changes the trip copy only.
Horizon masks currently affect trip comparisons, not worker alerts.
Forecast consent resets when the Observatory reopens.

The standalone preview remains available for isolated testing:


Run `./preview-trip-planner` for a separate window, or add `--fixture` for
public sample locations. Choose a destination and 1–14 observing nights,
check both IANA time zones, then **Save & compare**. Each observing night
runs from local noon to the following local noon at each place. Viewing
times show both zones, dates and UTC offsets, including daylight saving.

Home starts as a read-only copy of your saved location; its initial time
zone comes from this computer and should be checked. Destination lookup
is explicit and online; manual coordinates and time-zone entry also work.
Forecast downloads start off and require a separate opt-in. Forecasts use
rounded coordinates and cover only available near-term dates.

In **My horizon**, add named trees/buildings by true compass bearing and
height in degrees. North-crossing sectors and overlapping obstructions
are supported. Each place keeps its own mask. These manually estimated
masks trim target windows; they do not change astronomical darkness or
remove the Moon's contribution to sky brightness.

The comparison calculates Moon and five bright-planet windows, darkness
and Moon-free darkness. Fresh cached station elements can supply pass
windows within their validity range; this preview does not download new
elements. Meteor entries show activity dates, not a radiant prediction.
Cached launches remain context with local visibility unconfirmed. Missing
or stale data must not be interpreted as a visibility promise.

Trip settings, horizons and results stay locally in `.preview/trip-user/`
(fixture mode uses `.preview/trip-fixture/`). **Save & compare** persists
edits; forecast consent resets when reopening. The preview does not alter
live locations, the observing log, bar integration, worker or autostart.

## Terrain horizon estimates

Terrain and observing height are available under **Trip Planner → My horizon**
in the Observatory. Downloads remain explicit and manual obstructions are preserved.

For isolated testing, run `./preview-terrain` (or `--fixture` for public sample locations). It opens
an isolated window and copies the existing trip settings read-only on first
use, including manual tree/building sectors. Live locations, the observing
log, bar, worker and autostart are not changed. State stays in the ignored
`.preview/terrain-user/` directory; fixture state is separate.

Under **My horizon**, choose Home or destination, enter observing height
above ground in metres and press **Apply height**. The default is 1.7 m;
include any balcony/platform height. Existing manual obstruction angles are
kept and should be checked from the new height. Enable the one-time terrain
download and press **Estimate terrain**. If the tiles/profile are cached,
estimation works offline without download consent. An amber skyline shows
the estimate; manual sectors remain cyan. **Use estimated terrain in
comparison** controls the extra layer, and **Save & compare nights** stores
the choice. The larger of the manual and terrain angles blocks each bearing.

The provider receives coarse 1° tile identifiers, not names or exact
coordinates. Calculation is local, with at most 16 bounded tile downloads
and a 180-second overall attempt limit. Downloads and forecasts are separate
opt-ins; neither is scheduled by this preview. Cache/profile keys include
location and observing height. Changing height invalidates the selected
estimate without deleting manual sectors or the old cached estimate.

This first version samples from 100 m to 50 km every 100 m at 0.5° bearing
steps, using nominal 1 arc-second Skadi grids. It accounts for spherical
Earth curvature, with no atmospheric-refraction correction. Narrow ridges,
nearby ground features and mountains beyond 50 km can be missed. Data age
and source accuracy vary; sample spacing is not an accuracy guarantee.
Coverage is bounded to 70°S–70°N. Missing/invalid tiles never become a flat
skyline: the operation reports unavailable and keeps manual obstructions.
Enabled terrain with a missing profile blocks comparison until recalculated
or disabled. Trees, roofs and actual visibility still need local judgement.

Data source/attribution: [Terrain Tiles](https://registry.opendata.aws/terrain-tiles/),
[provider notices](assets/terrain-attribution.txt) and [data sources](DATA-SOURCES.md).

## Desktop theme preview (local development)

This branch adds **Settings → Appearance → Follow desktop theme** to the
Observatory and compact panel. It starts with the original Observatory
colours unless explicitly enabled. Theme colours are read from Omarchy's
current `colors.toml`; watched file changes and a two-second reread handle
symlink replacement during theme switches. Unavailable/incomplete colours
fall back to the original palette. No shell configuration or desktop theme
is changed. Text, controls and status roles are contrast-adjusted; labels
remain alongside observing verdicts. Moon surface illustrations keep their
scientific shading, and terrain also uses a dashed line to distinguish it
from manual obstructions.

Run `./preview-theme` in this checkout. It uses isolated public fixture data
under `.preview/settings/`, and appearance is saved only there. Choose
**Follow desktop theme**, then try **Your desktop theme**, **Sample light**
and **Sample dark**. Sample buttons only appear in this isolated trial and
do not change the desktop. Use **Show compact panel preview** to check the
fallback too. Toggle off to return to Observatory colours. Appearance mode
is stored separately from observing settings in `appearance.json`; there is
no worker restart or network request for this choice.

This preview is based on marketplace submission commit `e9bd3dc`. It is on
`codex/desktop-theme-preview` and has not been uploaded or installed live.
The existing marketplace request and immutable 0.1.2 release stay separate.
Preview approval is required before any deployment or publication.

Validation: `node tests/theme-colors.test.cjs` checks the actual colour parser
and contrast maths; `.venv/bin/python -m unittest discover -s tests` covers
appearance persistence without changing observing files and the existing
regressions. Native fixture checks cover theme-file/symlink changes,
fallback, mode persistence, both panels and screen loading.

## Launch-following preview (local development)

Run `./preview-launch-follow` to open a separate window. It inherits this
branch's accepted theme support; it does not change the live Observatory,
worker, location, viewing alerts or autostart. The marketplace submission
continues to target `e9bd3dc`; this work is local on a separate branch.

**Try the sample:** favourite the Falcon 9 demonstration, opt into desktop
alerts, then press **Delay 40 minutes**, **Hold** or **Explicit scrub**.
Repeating an unchanged scenario does not send another alert. **Change history**
shows what changed and whether delivery succeeded. Other scenarios demonstrate
cancellation, date-only timing, a missing feed entry and a provider outage.
The sample webcast button opens the YouTube homepage as a labelled example;
it is not a real mission broadcast. No synthetic desktop notification is sent
until alerts are explicitly enabled and an eligible sample change is requested.

Select **Live schedule · opt-in** to try actual missions, then enable launch
downloads and **Check schedule**. Favourite up to five launches; provider-supplied
HTTPS webcast links open only when clicked. A missing webcast is stated rather
than invented. This is launch-schedule following, not a claim that the launch
can be seen locally. Global schedule following needs no observing coordinates.

Downloads and master alerts start off on every launch of the preview. Favourites
and history persist separately for sample and live modes under the ignored,
private `.preview/launch-follow/` directory. The first fresh live observation
after restarting/re-enabling alerts establishes a baseline; it does not replay
missed alerts. Unfavouriting cancels pending alerts for that mission. Turning
alerts off clears pending deliveries and continues recording changes while
download monitoring remains enabled.

Upcoming LL2 data is cached for 15 minutes; favourites outside that feed are
checked individually at most hourly. This preview makes at most nine requests
per rolling hour, including errors; other applications share the provider's
quota. The window checks cached/eligible data once per minute while monitoring
is enabled, and stops when closed. Network failures preserve cached favourites;
HTTP 429 adds a one-hour cooldown. This is not a real-time launch-control feed.

A later precise NET is a **delay**. Other time/precision changes are labelled
**schedule changed**. A **hold** remains distinct from a scrub. Scrub/cancellation
alerts require explicit source status wording; a time shift, missing feed entry,
expired monitoring gap or provider failure never establishes a scrub. If LL2
only reports a hold or revised time, that is all the app can report. Completed
or in-flight mission updates do not become schedule alerts. Failed desktop
notifications are retried at most three times, and old pending updates expire.

Private requests travel to the local backend on bounded stdin. Provider data
and webcast URLs are validated. Live/simulated alerts are labelled Preview, and
simulated alerts are additionally marked simulated. The existing local worker
and its alert history are separate. This window creates no service, autostart,
schedule or background monitor outside its own lifetime.

Validation: tests cover consent, favourites, baseline/persistence, delay/status
classification, stale/out-of-order observations, deduplication, delivery retry,
source disappearance/outage, terminal missions, request caching/budgets,
corrupt-state preservation and notification/URL safety. Native fixture tests
exercise the actual QML/backend roundtrip without sending a desktop popup.
