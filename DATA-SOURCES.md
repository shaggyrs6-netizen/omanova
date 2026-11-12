# Data sources and credits

The MIT licence covers the original OMANOVA code and documentation. Provider
data and dependencies retain their own terms. OMANOVA is an independent project.

| Source | Use |
| --- | --- |
| [CelesTrak](https://celestrak.org/usage-policy.php) | Station, bright-satellite and Starlink orbit elements. The station and satellite fixtures are small dated excerpts for reproducible tests. |
| [NASA Spot the Station](https://www.nasa.gov/spot-the-station/) | NASA/JSC trajectory samples for an independent ISS pass regression check. |
| [NASA/JPL Solar System Dynamics](https://ssd.jpl.nasa.gov/faq.html) | DE440s ephemeris and the dated Horizons positions in the comet catalogue. |
| [Open-Meteo](https://open-meteo.com/en/terms) | Opt-in forecasts and explicitly requested city/postcode search using [GeoNames](https://www.geonames.org/) place data via the [geocoding API](https://open-meteo.com/en/docs/geocoding-api). The free hosted service is for non-commercial use. |
| [The Space Devs](https://thespacedevs.com/llapi) | Launch Library 2 schedule. The test schedule and plume trajectory are fictional. |
| [NOAA Space Weather Prediction Center](https://www.swpc.noaa.gov/) | OVATION aurora model and Kp outlook. |
| [Natural Earth](https://www.naturalearthdata.com/about/terms-of-use/) | Public-domain 1:110m land data for the orbit map. |
| [International Meteor Organization](https://www.imo.net/resources/calendar/) | Factual meteor-shower dates and radiant data. |
| [COBS Comet Observation Database](https://cobs.si/help/data_policy/) | Selected magnitude estimates and observing dates, attributed by comet page, observation date and observer code. This extracted data in `observatory/comets/catalog.json` remains under [CC BY-NC-SA 4.0](https://creativecommons.org/licenses/by-nc-sa/4.0/). Values are presented with OMANOVA’s formatting and NASA/JPL positional data. |
| [OpenStreetMap contributors](https://www.openstreetmap.org/copyright) and [OSRM](https://project-osrm.org/) | Dated routing estimates from a public town centre to the regional dark-sky sites. Park and sky-quality evidence is linked per site. |
| [Royal Observatory Greenwich](https://www.rmg.co.uk/stories/space-astronomy/full-moon-calendar-2026) and [timeanddate](https://www.timeanddate.com/astronomy/moon/super-full-moon.html) | Common full-Moon names and the orbit-relative distance rule used for size classes. |

Python dependencies are installed separately with uv. The plugin uses the
Omarchy shell and Quickshell interfaces. The cover was generated for OMANOVA.

CelesTrak adapters cache a given query for at least two hours and stop
requesting it on an HTTP error. Investigate before resuming. For station
predictions use `.venv/bin/python worker.py resume-orbits`. For the optional
watchlist or Starlink views, close the Observatory, back up the affected
cache file under `.preview/satellites/cache` or `.preview/trains/cache`,
and move it out of the cache directory before reopening the view.

The 12 November comet refresh used Horizons API v1.3 geocentric observer
tables (quantities 1 and 2), through 12 December 2026 UTC, and qualified COBS
API observations. `observatory/comets/refresh_catalog.py` is an explicit
maintainer staging command, not an automatic user download. It validates
timestamps, coverage, response bounds and coordinates before writing a new
file. Existing frozen comet fixtures are preserved separately for regression
checks. Meteor activity dates and selected 2027 peaks use IMO calendar Table 5.
