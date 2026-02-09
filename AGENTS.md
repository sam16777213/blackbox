# Black Box Agent Guide

## Scope
- This guide covers the Vala code under `src/` for Black Box `0.13.0`.
- Primary stack: GTK4 + libadwaita + VTE (`vte-2.91-gtk4`) + GSettings.

## Architecture Map
- Entry point: `src/main.vala`
- App bootstrap and app-level actions: `src/Application.vala`
- CLI parsing (`-c`, `-w`, `--`): `src/CommandLine.vala`
- Main window and window actions: `src/widgets/Window.vala`
- Headerbar/tab UX: `src/widgets/HeaderBar.vala`
- Per-tab container: `src/widgets/TerminalTab.vala`
- Terminal widget (spawn, theme/colors, key handling, DnD): `src/widgets/Terminal.vala`
- Preferences UI and bindings: `src/widgets/PreferencesWindow.vala` + `src/gtk/preferences-window.ui`
- Search bar: `src/widgets/SearchToolbar.vala` + `src/gtk/search-toolbar.ui`
- Shortcuts model/editor/dialog: `src/services/Shortcuts.vala`, `src/widgets/ShortcutEditor.vala`, `src/widgets/ShortcutDialog.vala`
- Theme loading and app recoloring: `src/services/ThemeProvider.vala`, `src/services/Scheme.vala`
- Global settings wrapper: `src/services/Settings.vala`, `src/services/PQSettings.vala`
- Shared CSS and helpers: `src/resources/style.css`, `src/utils/*.vala`

## Data Flow Patterns
- GSettings keys are defined in `data/com.raggesilver.BlackBox.gschema.xml`.
- `src/services/Settings.vala` exposes each key as a property.
- UI widgets bind to settings in `PreferencesWindow.bind_data()`.
- Runtime consumers (window/terminal/headerbar/etc.) react via `settings.notify[...]` or property bindings.

## Change Checklist
- Adding/changing a setting:
1. Update `data/com.raggesilver.BlackBox.gschema.xml`.
2. Add/update property in `src/services/Settings.vala`.
3. Bind it in `src/widgets/PreferencesWindow.vala`.
4. Add UI control in `src/gtk/preferences-window.ui` if needed.
5. Wire behavior in consumer widgets (`Window`, `Terminal`, `HeaderBar`, etc.).

- Adding/changing a window/tab action:
1. Add constant in `src/services/Shortcuts.vala`.
2. Register action in `src/Application.vala` or `src/widgets/Window.vala`.
3. Add default accelerator in `Keymap` (`Shortcuts.vala`).
4. Add human label in `ShortcutEditor` action map.

- Theme or transparency changes:
1. Keep app-wide CSS selectors scoped (avoid broad `window { ... }` unless intentional).
2. Terminal opacity should affect terminal background, not UI text.
3. Theme integration logic lives in `ThemeProvider.apply_theming()`.

## Build and Verify
- Configure: `meson setup build` (or `meson setup --reconfigure build`)
- Compile: `meson compile -C build`
- Run: `./build/src/blackbox`
- If schema changed, ensure schema validation passes (`meson test -C build` includes schema checks when available).

## Practical Notes
- `build/` contains generated artifacts; do not hand-edit generated C.
- Resource-backed UI files are loaded via `GtkTemplate` paths from `src/blackbox.gresource.xml`.
- Sixel support path is wired in code:
  - setting key `use-sixel` (gschema/settings/preferences),
  - bound in `TerminalTab` to VTE property `enable-sixel`.
  - Runtime support still depends on VTE being built with sixel support.
