# OMANOVA 0.1.8 — installer fixes and Mission Control battery controls

This release fixes widget installation on Omarchy 4.5, improves recovery during setup and adds battery-aware animation controls for Mission Control. The hidden observing worker and Mission Control wallpaper have separate login settings, both Off by default on a fresh installation.

## Omarchy 4.5 compatibility

The widget package uses direct QML imports and contains no symbolic links.
Omarchy 4.5 rejected the previous package when adding the widget. The installer fix was verified on x86-64 and on an ARM M1 Air. [Issue #1 test results](https://github.com/shaggyrs6-netizen/omanova/issues/1)

## Upgrading from the marketplace's 0.1.1 snapshot

Back up your OMANOVA data and stop the old foreground worker. Keep the original runtime checkout where it is, switch it to the new release tag, and run `./install` there. Refresh the Omarchy shell and reopen the Observatory. See the [in-place upgrade instructions](../README.md#upgrading-an-existing-installation). The listed 0.1.1 snapshot predates the updater. Newer managed installations can use **Settings → Check for updates** after the release is published.

If guided dependency setup fails, the installer restores the previous Python environment and tries to restart an already-active worker. The checkout stays at the source revision you chose. If the worker cannot use the restored environment, follow the installer's diagnostic and the recovery advice in the upgrade instructions.

## Mission Control

The wallpaper is optional. **Set up Mission Control** builds the renderer locally for your user. The README lists Qt system packages that you may install separately. The wallpaper and **Start at login** stay Off after setup. [Mission Control instructions](../README.md#mission-control-live-wallpaper) · [Wallpaper screenshots](SCREENSHOTS-0.1.8.md)

In **Settings → Appearance → Mission Control wallpaper**, choose **Smooth** (30 FPS), **Balanced** (15 FPS), **Battery saver** (5 FPS), or **Still**. The default battery cap limits animation to 5 FPS while the battery is discharging. Still pauses continuous animation and keeps the sky data refreshing. On AC power the wallpaper returns to your usual setting.

If you already set up Mission Control in 0.1.7, use **Restore desktop** in its control window if it is running, then choose **Update Mission Control** in Settings. This rebuilds the optional renderer and keeps your existing login preference.

Mission Control draws on the primary monitor. If Omarchy Pulse is running and Mission Control opens with an empty background layer, stop Pulse before starting Mission Control again.

Before removing OMANOVA or restoring an earlier version without Mission Control controls, turn off the wallpaper and its **Start at login** setting. The updater prompts for this when needed. The [removal instructions](../README.md#remove) also include a terminal command that stops the wallpaper and disables its login entry. The observing worker has its own startup setting.

The app still requires additional user setup for the Python runtime and observing worker. The optional Qt setup is separate.

The bundled comet snapshot covers 18 November 2026 to 2 January 2027 at 00:00 UTC. The README now reflects those dates.
