# Tandem Dock — Behavior Specification

Single source of truth for every Tandem Dock frontend. The Cinnamon applet
(threshold version 1.3.0) is the reference implementation; the Plasma plasmoid
(planned) implements this same spec against KDE Plasma 6. Any behavior change
is specced here first, then implemented per frontend.

## Identity

Tandem Dock lives on a bar (the "host") and shows a centered dock of
launchers that **mirrors the host's task manager pin list in real time**.
The pin list stays the single source of truth: the dock never manages pins
of its own.

The dock makes its own host bar fully transparent (scoped so other bars on
the machine keep their theme look), so the dock appears to float.

## Pin mirroring

- Read the host task manager's pinned-launcher list from its configuration
  store.
- Watch the store live and rebuild the dock launchers on change; coalesce
  rapid consecutive events (the task manager rewrites its config more than
  once per pin operation).
- Resolve launcher ids to applications the same way the host task manager
  resolves them, including desktop-environment-specific suffix handling.
- If the mirrored task manager instance is removed (its config store
  deleted), the dock shows nothing until it is re-added.

## Magnification

- Icons rest at a fraction of full size (default 0.5x, full size default
  40px).
- On hover the icon grows to full size with a Gaussian falloff towards its
  neighbours — pure UI transforms so hit targets stay at the rested layout.
- Animation duration default 0.15s. Icons grow upward from the tray floor.

## Glass tray

- Icons stand on a smoky-glass shelf: deep glass body, bright top sheen,
  rounded corners, drop shadow.
- Each icon has a faint squashed reflection of itself in the glass
  (toggleable, default on).

## State indication and previews

- A small running-indicator dot under icons whose app has open windows
  (toggleable, default on).
- A preview popup on hover (default on, hover delay default 350ms): lists
  the app's open windows with titles; clicking a row focuses that window,
  clicking `x` closes it.

## Interactions

- Click: focus the app's most recent window, or launch the app if none.
- Middle-click: new window.
- Right-click: open the preview popup.
- Settings: an always-visible small gear on the right of the dock opens
  the frontend's settings.

## Settings (defaults)

| Setting | Default | Description |
|---|---|---|
| Icon size | 40px | Size the hovered icon magnifies to |
| Rest scale | 0.5x | Fraction of the icon size used while resting |
| Reflection | on | Icon reflection in the glass |
| Running dot | on | Dot under icons with open windows |
| Mirrored source | auto | Which task-manager instance to mirror |
| Zoom time | 0.15s | Magnification animation duration |
| Preview popup | on | Window list popup on hover |
| Preview delay | 350ms | Hover delay before the popup appears |

## Frontend bindings

Behavior is identical everywhere; only the bindings differ.

| Concern | Cinnamon (reference) | Plasma (planned) |
|---|---|---|
| Pin store | grouped-window-list applet JSON settings file | Plasma task manager launchers configuration |
| Store watching | `Gio.FileMonitor` | config-file watch / tasks model change signals |
| App resolution | `Cinnamon.AppSystem` (incl. `:flatpak` suffix) | ApplicationModel / services |
| Windows and previews | applet window tracking | Plasma Tasks QML API |
| Animation substrate | Clutter/St | QtQuick/QtQuick Effects |
| Install | applet copy + optional bottom autohide panel | plasmoid package install |

## Non-goals

- Not a replacement for the task manager/taskbar — only the mirrored dock.
- No dock-local pin management, no dock-local launchers-only mode.

License: MIT.
