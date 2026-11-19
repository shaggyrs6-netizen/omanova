# OMANOVA 0.1.8 — upgrade and wallpaper recovery

This maintenance release improves recovery during installation and clarifies how to switch back to a normal desktop. The hidden observing worker and Mission Control wallpaper have separate login settings, both Off by default on a fresh installation.

## Omarchy 4.5 compatibility

The widget package uses direct QML imports and contains no symbolic links.
Omarchy 4.5 rejected the previous package when adding the widget.

## Upgrading from the marketplace's 0.1.1 snapshot

Back up your OMANOVA data and stop the old foreground worker. Keep the original runtime checkout where it is, switch it to the new release tag, and run `./install` there. Refresh the Omarchy shell and reopen the Observatory. See the [in-place upgrade instructions](../README.md#upgrading-an-existing-installation). The listed 0.1.1 snapshot predates the updater. Newer managed installations can use **Settings → Check for updates** after the release is published.

If guided dependency setup fails, the installer restores the previous Python environment and tries to restart an already-active worker. The checkout stays at the source revision you chose. If the worker cannot use the restored environment, follow the installer's diagnostic and the recovery advice in the upgrade instructions.

## Mission Control

The wallpaper is optional. **Set up Mission Control** builds the renderer locally for your user. The README lists Qt system packages that you may install separately. The wallpaper and **Start at login** stay Off after setup. [Mission Control instructions](../README.md#mission-control-live-wallpaper) · [Wallpaper screenshots](SCREENSHOTS-0.1.7.md)

Before removing OMANOVA or restoring an earlier version without Mission Control controls, turn off the wallpaper and its **Start at login** setting. The updater prompts for this when needed. The [removal instructions](../README.md#remove) also include a terminal command that stops the wallpaper and disables its login entry. The observing worker has its own startup setting.

The app still requires additional user setup for the Python runtime and observing worker. The optional Qt setup is separate.
