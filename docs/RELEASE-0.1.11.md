# OMANOVA 0.1.11

This release makes it easier to decide when to get outside, save the plan, and use it at the telescope.

- **Tonight summary.** See the best current suggestion, its window, where to look and what the forecast supports. The actions are keyboard-accessible. Stale predictions and poor conditions can leave Tonight without a recommendation.
- **Share as image.** Save a PNG observing card locally when Tonight has a timed suggestion. The card includes the time, direction when available and forecast context. It omits the saved observing-site name and coordinates.
- **Dew risk.** Tonight and Conditions can show an estimate based on air temperature and dew point from the existing weather opt-in. Actual condensation depends on your optics and surroundings.
- **Clear-sky observing alerts.** Opt in to alerts for selected event types and choose the optional clear-and-dark filter. It requires a favourable, current forecast and astronomical darkness. Quiet hours and duplicate suppression still apply.
- **Stellarium handoff.** Open a supported Sky Finder object in a running local Stellarium with Remote Control enabled on loopback at port 8090. OMANOVA selects and centres the target while preserving Stellarium’s site and clock. Stellarium is a separate optional install.
- **Jupiter’s moons.** Find approximate Galilean moon and shadow transits under **Sky → Planets**. Local windows account for darkness, altitude and any matching saved horizon. An independent comparison for Io on 1 December found contact times around 2–4½ minutes later than IMCCE’s prediction. Use a dedicated ephemeris for contact timing.
- **Comets.** Four refreshed geocentric tracks cover 27 November 2026 through 11 January 2027 at 00:00 UTC (10 January at 6 p.m. Central). The app shows dated COBS brightness estimates and starts warning two weeks before expiry. Expired tracks stop yielding observing windows.

## Install or upgrade

Download **omanova-0.1.11.tar.gz** and verify it with **SHA256SUMS**. For a managed install, use **Settings → Updates & runtime**. [Install and upgrade instructions](../README.md#upgrading-an-existing-installation)

Check the [sample screenshot gallery](SCREENSHOTS-0.1.11.md) for the new views. The local PNG export passed with sample data. A repeat with a current live observing pick remains pending.

**Astrophotography testers wanted.** If you use a camera and telescope on Omarchy, feedback on field-of-view framing, offline plate solving or the Stellarium handoff would help. Please include your equipment and what worked or got in the way when [opening an issue](https://github.com/shaggyrs6-netizen/omanova/issues).
