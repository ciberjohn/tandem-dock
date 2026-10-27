# Tandem Dock for Cinnamon

A small, centered dock for the Cinnamon desktop that **mirrors the pinned
apps of your main panel's grouped window list in real time**.

Pin an app on your panel — the dock gains it. Unpin it — the dock loses it.
No dock preferences to maintain: the grouped window list stays the single
source of truth.

- **Live mirroring** of the grouped-window-list pin list (file-monitor based,
  near-instant updates, no restarts)
- **macOS-style hover zoom** — the hovered icon scales up with a Gaussian
  falloff to its neighbours (pure GPU transform, hit targets untouched)
- **Hover preview popup** — lists the app's open windows with their titles;
  click a row to focus a window, click `x` to close it
- **Running indicator** — a small dot under icons whose app has open windows
- **Click** to focus the most recent window or launch the app;
  **middle-click** for a new window; **right-click** opens the preview

Built and tested on Cinnamon 6.6 (Linux Mint 22.3).

## Requirements

- Cinnamon 6.4+ with the **grouped window list** applet on a panel (the
  stock Cinnamon taskbar). Tandem Dock reads that applet's per-instance
  settings file (`~/.config/cinnamon/spices/grouped-window-list@cinnamon.org/<id>.json`)
  and mirrors its `pinned-apps` key.

## Install

```bash
./install.sh                # applet files only
./install.sh --with-panel   # also add a bottom auto-hide panel with the dock centered
```

Then, if you did not use `--with-panel`: right-click the panel → *Panel* →
*Add panel* (bottom edge), and add Tandem Dock to its center zone via
*Applets*. Restart Cinnamon if the applet list does not show it.

To keep the dock visually "floating", set the panel's auto-hide to
*Auto-hide* (dock reveals when the pointer reaches the bottom edge) and give
it a modest height (45-50px works well with 40px icons).

## Settings

| Setting | Default | Description |
|---|---|---|
| Icon size | 40px | Dock icon size |
| Running dot | on | Dot under icons with open windows |
| GWL settings file | auto | Which grouped-window-list instance to mirror; `auto` picks the most recently modified |
| Zoom factor | 1.25x | Hovered icon scale |
| Zoom time | 0.15s | Zoom animation duration |
| Preview popup | on | Window list popup on hover |
| Preview delay | 350ms | Hover delay before the popup appears |

## How the mirroring works

The grouped window list keeps its pinned apps in a JSON settings file inside
`~/.config/cinnamon/spices/grouped-window-list@cinnamon.org/`. Tandem Dock
watches that file with a `Gio.FileMonitor` and rebuilds its launchers on
change (events are coalesced, since the panel applet rewrites the file more
than once per pin operation). Pinned ids resolve through
`Cinnamon.AppSystem` exactly the way the grouped window list itself resolves
them, including the `:flatpak` suffix.

Caveat: if the grouped window list applet instance is removed from the panel,
Cinnamon deletes its settings file — the dock then has nothing to mirror
until the applet is re-added.

## License

MIT — see [LICENSE](LICENSE).
