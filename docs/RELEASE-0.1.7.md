# OMANOVA 0.1.7 — Mission Control

Mission Control brings the Observatory's local sky and satellite tracking to an optional live wallpaper for Omarchy. Wallpaper and **Start at login** both default to **Off**.

## What's new

- A mission-control display with a rotating Earth, a chart of your local sky, and ISS and Tiangong viewpoints and orbital tracks. The display can include Moon, next-pass, weather and launch context when the local cache has current data.
- Smoother Earth rotation, with reduced motion available in the Mission Control view. The wallpaper runs behind your desktop windows and can keep running after you close the Observatory.
- A **Mission Control wallpaper** section under **Settings → Appearance** with optional setup, current status, on/off and a separate login setting. Mission Control login startup uses the desktop's startup-app control and is separate from the OMANOVA background worker.
- **Turn wallpaper off** gives you your normal desktop back and disables Mission Control login startup. **Restore desktop** in Mission Control restores it for the current session and keeps your saved login preference.

## Install and try it

1. Install OMANOVA from this release or use **Settings → Check for updates** in your existing Observatory.
2. Under **Settings → Appearance → Mission Control wallpaper**, choose **Set up Mission Control**. This builds the optional renderer for your account. Follow the [README setup instructions](../README.md#mission-control-live-wallpaper) if you need the Qt build tools, or run `./install-mission-control` from the release checkout.
3. Choose **Turn wallpaper on**. If you want it at future logins, check **Start at login** separately.

Mission Control targets the primary monitor in an Omarchy/Hyprland session. It reads OMANOVA's existing local data and uses your current download preferences. If the feed or orbital elements are stale or unavailable, live markers are withheld. A track or pass estimate cannot confirm visible conditions.

The optional setup uses local Qt build tools and makes no download or privileged installation request. Logs are written to `${XDG_DATA_HOME:-$HOME/.local/share}/omasky/mission-control-build.log`. Existing observing locations, equipment, My Night, log, feeds and worker preferences are carried over by the core update.

[View native screenshots](SCREENSHOTS-0.1.7.md) · [Full changelog](../CHANGELOG.md) · [Installation and upgrade instructions](../README.md#install)

Earth imagery: NASA Goddard [Blue Marble](https://science.nasa.gov/earth/earth-observatory/the-blue-marble-true-color-global-imagery-at-1km-resolution/). This is a GitHub release. The Omarchy marketplace listing is unchanged.
