# OMANOVA 0.1.6 — plan a night and frame the sky

Put a night's observing picks in one place, see when to go out, and check what
fits through your eyepiece or camera. The Observatory still opens from the bar
with the compact panel available as a fallback.

## My Night and the timing chart

- Open **Plan → My Night**. Add targets or events from Tonight, Events, or Sky
  Finder. The list holds up to 24 picks and stays on your machine.
- Plan for the active location, Trip Home, or a trip destination and date.
  Catalogue targets recalculate for that night. Timed events retain their
  original location and window. Expired events remain available to inspect.
- See **Begin / Best / End** in local time, altitude, obstructions from the saved
  manual or terrain horizon, darkness, and cached cloud information when
  available. Timing is sampled. A timed event without a continuous path shows
  its source window, including whether a station pass is geometric only.
- Save eligible picks as an offline guide. Stale or unsupported picks are
  withheld from the export. **I saw it** opens a pre-filled observing-log draft
  at the matching place for you to review and save.

## Expanded Sky Finder

- Search 25 Messier targets and five existing constellation landmarks by name,
  constellation, or Messier number. Cards include finding hints, equipment
  guidance, local windows, and **Add to My Night**.
- Use **Show field-of-view overlay** on a deep-sky target to compare its
  approximate catalogue width with your setup. The overlay calls out a
  comfortable fit, a tight fit, or possible clipping.

## Telescope and camera framing

- In **My Equipment and Sky**, enter a manual true field or estimate it from
  telescope focal length, eyepiece focal length, and eyepiece apparent field.
- Save up to 12 named telescope or camera setups. Camera setups use active sensor
  width and height in millimetres plus the actual focal length. Select a setup
  from the dropdown in Sky Finder or My Night. **Manual / last estimate**
  switches back to the unnamed field.
- In **Sky → Star Chart**, turn on **Camera framing** and select a saved camera.
  Tap the sky or choose a catalogue target to centre the frame. Use the slider
  or **+90°** to turn the camera around the centre. At 0°, the top of the frame
  points toward celestial north.
- The whole-sky footprint and magnified camera view show the same framing.
  Dashed circles approximate catalogue target sizes. The close-up shows nearby
  chart stars and target centres. Actual object shape, lens distortion, camera
  angle, faint stars, and observing conditions affect the real image.
- The original equipment profile stays readable by 0.1.5 after rollback.
  Named setups, telescope optics, and manual fields narrower than 0.1° are
  stored separately, ready for 0.1.6. The 0.1.6-only My Night list likewise
  remains on disk across rollback.

## Comet catalogue

Four dated tracks were refreshed from [NASA/JPL Horizons](https://ssd.jpl.nasa.gov/horizons/),
with 541 two-hour samples per target from 18 November 2026 UTC to
**2 January 2027 at 00:00 UTC**. Comet recommendations use the bounded position
table and stop at expiry. The bundled visual magnitude estimates are dated
[COBS observations](https://cobs.si/) and can change as the comet evolves.

| Target | Visual magnitude | Observation date |
| --- | --- | --- |
| 161P/Hartley-IRAS | 11.2 | 14 November 2026 |
| 10P/Tempel | 11.9 | 9 November 2026 |
| C/2026 A2 (Bok) | 12.6 | 13 November 2026 |
| 220P/McNaught | 13.2 | 13 November 2026 |

See [data sources and attribution](../DATA-SOURCES.md) for provider details.
Catalogue refreshes are maintainer actions. The app uses the bundled tracks
locally.

## Install, upgrade and rollback

- A clean install uses the matching tagged source or release archive with
  `./install`. Worker login startup defaults off. Pass `--autostart` to opt in.
- On an unmodified managed 0.1.5 installation, use **Settings → OMANOVA updates**
  once the release is public. Save any log draft first. Close and reopen the
  Observatory and reload the shell after a successful update.
- The updater guards local edits, unrecognised layouts and custom worker units.
  For a development overlay or an older alias-based service, use a reviewed
  manual upgrade with backups. Keep existing service and login choices.
- **Restore previous installation** switches the managed runtime and widget back.
  Saved data lives outside the runtime. Newer planning and framing data remains
  available when returning to 0.1.6.
- The package is versioned and source-only. Compare `SHA256SUMS` and
  `SOURCE-COMMIT.txt` with the chosen archive and its matching tag.

[Sample app screenshots](SCREENSHOTS-0.1.6.md) · [Full documentation](../README.md)
