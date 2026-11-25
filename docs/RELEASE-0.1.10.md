# OMANOVA 0.1.10 — expanded Sky Finder and observing instruments

- **Sky Finder now covers 109 Messier targets and five landmarks.** Search by name, Messier number or constellation, check local viewing windows against your saved horizon, and add a target directly to My Night. Catalogue additions come from [OpenNGC](../observatory/field/OPENNGC.md).
- **Comets refreshed.** Four JPL Horizons tracks now cover 25 November 2026 to **9 January 2027 at 00:00 UTC**. The app shows observation dates alongside the COBS brightness estimates.
- **Local skyglow estimates.** Choose a World Atlas 2015 GeoTIFF and use GDAL to sample modelled artificial skyglow for the active location, Trip Home or destination. Manual sky preferences still drive suggestions.
- **Offline plate solving.** Use Astrometry.net and local index files to solve a FITS, JPEG or PNG sky image and retrieve its centre coordinates, pixel scale and orientation.
- **INDI telescope controls.** Read mount coordinates and explicitly request Go To or stop from a local INDI server. Go To uses the active site, astronomical darkness, a 20° minimum altitude and the saved horizon. Each Go To requires confirmation.

Find the tools in **Sky → Sky Finder → Observing instruments**. GDAL and the atlas, Astrometry.net and its indexes, and the INDI tools and server each need separate setup. The installer leaves those components optional. [Instrument setup](../README.md#sky-finder-observing-instruments)

The skyglow lookup was checked with GDAL and a test raster, the plate solver with an Astrometry.net demo image, and the mount controls with the INDI telescope simulator. Physical mount operation still needs testing.

**Rolling back to 0.1.9:** remove any newly added catalogue targets from My Night in 0.1.10 before restoring 0.1.9. The earlier version needs its own catalogue entries to render the plan. Save a copy of your plan first if you want to keep those picks for a later upgrade.

[View the release screenshots](SCREENSHOTS-0.1.10.md)
