# OMANOVA 0.1.12

- **Your sky over your actual skyline.** Under **Plan → Trip Planner & My Horizon → My Horizon**, see the Sun, Moon, planets and bright stars over your manual obstructions and any cached terrain. Inspect where an object is, whether it’s clear and when it next clears the skyline. Scrub the time for Home or a destination. The chart shows geometry, so daylight, cloud and local obstructions still matter.
- **Seeing and transparency.** Under **Tonight → Conditions**, compare the next 24 forecast hours. Seeing uses surface and upper-air winds as a rough turbulence indicator. Transparency uses cloud, humidity, horizontal visibility and precipitation. Both use the existing weather opt-in and are withheld when the forecast expires or inputs are missing.
- **NOAA solar wind.** Under **Sky → Aurora**, see upstream wind speed, proton density, total magnetic field and Bz, with a timestamp and primary spacecraft for each feed. Readings older than 15 minutes disappear. The panel uses the existing Aurora download opt-in and leaves the local visibility assessment independent.
- **149 new Sky Finder targets.** Search NGC and IC numbers, common names or constellations. Sky Finder now has **258 deep-sky targets and five landmarks**. The added objects support local horizon-aware observing windows, framing and My Night. [OpenNGC attribution](../observatory/field/OPENNGC.md)

## Install or upgrade

Download **omanova-0.1.12.tar.gz** and verify it with **SHA256SUMS**, or open **Settings → Updates & runtime** on a managed installation. [Install and upgrade instructions](../README.md#upgrading-an-existing-installation)

**Rolling back to 0.1.11:** If you added any of the new NGC or IC objects to My Night, save a copy of your plan and remove those picks before rolling back. The older version needs catalogue entries it recognises.

[View the sample screenshot gallery](SCREENSHOTS-0.1.12.md). The live PNG export check from 0.1.11 remains pending until Tonight offers a live pick.
