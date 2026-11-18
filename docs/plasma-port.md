# Tandem Dock for Plasma — Port Roadmap

Project record, decided 2026-11-18. **Status: spec + roadmap only — no
implementation yet.** Behavior is defined by [SPEC.md](../SPEC.md); this
page is the plan for the second frontend.

## Why

Two machines in the fleet (`ciberjohn-kratos`, `ciberjohn-nucboxk15`) run
Kubuntu 26.04 with Plasma 6.6 on Wayland, on stock plasmashell since the
2026-11-09 Caelestia revert. The goal is the same bar/dock experience as the
Cinnamon reference (vostro), not the same desktop environment.

- Native Plasma widgets/panels are already restored on both machines; the
  only missing piece is the dock itself.
- Stock Plasma task manager gives pin mirroring, previews and running
  indicators, but no macOS-style magnification; Latte Dock is unmaintained.
- Re-enabling the reverted Caelestia dock would reintroduce the CPU spin
  that caused the revert.

## Target

Plasma 6.6 / Qt 6 (Kubuntu 26.04), Wayland session, as a QML plasmoid
(`PlasmaCore`/`PlasmaComponents`/Tasks QML API). First machine for
verification: nucboxk15 (the lab machine), then kratos.

## Phases

| Phase | Deliverable | Notes |
|---|---|---|
| P1 | Pin mirroring | Read the Plasma task manager's launchers config; resolve via services; live rebuild on change, coalesced |
| P2 | Magnification | Hover grow to full size, Gaussian falloff, 0.15s; QtQuick transforms, hit targets unchanged |
| P3 | Glass tray | Smoky-glass pill, top sheen, rounded corners, shadow, squashed icon reflections |
| P4 | Previews + dots | Window-list hover popup (focus / close per row), 350ms delay, running dots |
| P5 | Pack + settings | Settings gear, `install.sh --plasma`, install/verification on both machines |

## Binding map (CJS applet → QML plasmoid)

| Concern | Cinnamon reference | Plasma port |
|---|---|---|
| Pin store | GWL applet JSON settings file | task manager applet config (launchers) |
| Watch | `Gio.FileMonitor` | file watch / tasks model change signals |
| App resolution | `Cinnamon.AppSystem` + `:flatpak` suffix | ApplicationModel / services |
| Windows/previews | applet window tracking | Tasks applet QML API |
| Animation | Clutter/St | QtQuick + effects |

## Decisions taken (2026-11-18)

- Live in **this** repo (monorepo, brand unchanged); no separate repo.
- Spec-first: SPEC.md is normative; this roadmap is not a fork of behavior.
- Verification on real machines only before calling a phase done.
