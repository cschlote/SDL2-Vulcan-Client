# Demo UI And Engine Plan

This document tracks the current plan for the demo UI and the reusable engine UI layer.

## Product Direction

The repository serves two purposes:

1. Build a small D game-engine foundation with SDL2, Vulkan, font rendering, retained UI, settings, input, and basic scene rendering.
2. Keep a learning/demo application around that exercises the engine pieces until the reusable code is ready to split into an Engine-only D module.

After the engine shape is stable, the demo-specific parts should stay in the executable project while the reusable parts can be published as a package.

## Current Status

Implemented or partially implemented:

- SDL2 bootstrap and window wrapper
- Vulkan instance, device, swapchain, render pass, pipelines, buffers, descriptors, and synchronization
- selectable placeholder 3D meshes
- filled, textured, wireframe, and hidden-line render modes
- FreeType-backed bitmap font atlases
- retained UI widgets: windows, labels, buttons, image placeholders, spacers, surface boxes, HBox/VBox layout
- `UiScreen` as experimental generic screen/window owner
- `DemoUiScreen` as the current demo-specific UI screen
- INI settings load/save model
- generic `UiOverlayGeometry` and `UiWindowDrawRange` names for renderer-facing UI draw data

Known migration debt:

- `source/demo/demo_ui.d` still contains an old stateless HUD construction and dispatch block.
- `DemoUiScreen` duplicates logic that should move into or use `UiScreen`.
- settings are currently too close to automatic persistence in some paths.

## UI Design Direction

The UI should evolve toward a small retained framework inspired by Qt and Amiga Magic User Interface:

- font-sensitive sizing
- automatic layout
- reusable widgets
- local event ownership
- signal/callback style communication
- generic screen/window management
- app-specific screens built outside the UI engine

Hard-coded rectangles can exist temporarily in the demo, but final windows should derive their minimum and preferred sizes from fonts, content, and layout hints.

## Planned Widget Set

The retained UI already has windows, labels, buttons, image placeholders, spacers, surface boxes, and row/column containers.

Next widgets:

- checkbox / toggle
- slider
- text field
- combo box / dropdown
- tab bar
- progress bar
- list box or selection list
- separator or divider
- icon/image widget backed by real texture data

The first implementation should favor simple, composable widgets over a large framework.

## Demo Window Structure

The demo should evolve from a test shell into a small application with clear windows:

- Main/demo control window: opens tools, exits the app, and exposes common demo actions.
- Status window: app version, frame rate, active scene, current render mode, and viewport state.
- Widget demo window: interactive examples for buttons, toggles, sliders, dropdowns, and text fields.
- Controls/log window: keyboard and mouse help first, then diagnostics or command output later.
- Settings window: display, controls, gameplay, audio, and UI options.
- Presets/shortcuts window: common layouts, render profiles, and UI actions.

The four corner windows should serve different roles so the UI reads like a real demo app rather than a fixed debug HUD.

The `D` hotkey toggles a retained UI bounds overlay. When enabled, every visible widget paints a semi-transparent outline after its normal render pass so layout and nesting are inspectable at runtime. Layout containers use distinct colors for vertical stacks, horizontal rows, surface boxes, grids, and spacers.

`UiWindow` body content is laid out through the internal content root. A direct content widget should receive the full padded body area, and nested layout containers decide how their children consume that space.

## Settings Policy

Settings are loaded from `~/.config/sdl2-vulcan-demo/config`.

Expected behavior:

- load defaults when the file does not exist
- keep a stable, human-readable INI layout
- Apply updates the running app state only
- Save writes settings to disk
- closing the app should not silently persist changed settings
- parsing and serialization should stay small and dependency-free for now

This keeps temporary experimentation local until the user explicitly saves.

## Cleanup Plan

Renderer-facing draw data now uses generic UI names. The old stateless HUD construction path has been removed from the demo UI module, so `demo_ui.d` now builds overlay geometry from retained `UiScreen`/`UiWindow` state only.

Completed legacy cleanup:

- removed the old stateless `buildHudOverlayVertices` path
- removed the old `buildHudLayout` and `HudLayoutState` bridge
- removed the old `hudDispatch...` helpers
- kept only retained screen/window/widget construction in `DemoUiScreen`

Use `UiScreen` properly:

- demo windows are registered through generic `UiScreen` helpers
- `registerWindowInteractionHandlers` owns common drag/resize wiring
- `UiScreen` owns generic window iteration, hit testing, layout, and viewport clamping
- demo-specific window creation, text, and callbacks stay in `DemoUiScreen`

## Implementation Order

1. Update documentation and plans to reflect the engine-first direction. Done.
2. Rename renderer-facing HUD data types to generic UI names. Done.
3. Remove the old stateless HUD helper block from `demo_ui.d`. Done.
4. Refactor `DemoUiScreen` to use `UiScreen` helpers consistently. Done.
5. Fix settings persistence so only explicit Save writes to disk. Done.
6. Add missing controls for a real settings dialog: toggle, slider, dropdown, text field. Done.
7. Rebuild the settings window around Apply and Save. Done.
8. Rework demo windows into clear app roles. Done.
9. Review which modules are reusable enough for the first Engine-only package boundary. Done.

## Public Package Preparation

Before publishing on code.dlang.org, decide the package boundary:

- reusable renderer modules
- reusable UI modules
- font atlas support
- SDL2/Vulkan bootstrap helpers
- demo-only executable and sample assets

The public module should not expose demo-specific names, HUD naming, sample window text, or placeholder-only settings keys as engine APIs.
