# Demo UI And Engine Plan

This document tracks the current plan for the demo UI and the reusable engine UI layer.

## Product Direction

The repository serves two purposes:

1. Build a small D game-engine foundation with SDL2, Vulkan, font rendering, retained UI, settings, input, audio, and basic scene rendering.
2. Keep a learning/demo application around that exercises the engine pieces until the reusable code is ready to split into an Engine-only D module.

After the engine shape is stable, the demo-specific parts should stay in the executable project while the reusable parts can be published as a package.

## Current Status

Implemented or partially implemented:

- SDL2 bootstrap and window wrapper
- Vulkan instance, device, swapchain, render pass, pipelines, buffers, descriptors, and synchronization
- selectable placeholder 3D meshes
- filled, textured, wireframe, and hidden-line render modes
- FreeType-backed bitmap font atlases
- retained UI widgets: windows, labels, text blocks, buttons, image placeholders, spacers, content/frame boxes, HBox/VBox/Grid layout, scroll areas, toggles, sliders, dropdowns, and text fields
- widget documentation that covers existing widgets and planned widgets
- `UiScreen` as experimental generic screen/window owner
- `DemoUiScreen` as the current demo-specific UI screen
- chrome-less left-edge demo sidebar with compact 32 px style launcher buttons
- Demo window documentation that maps current and planned windows to reusable UI classes and regression checks
- INI settings load/save model
- generic `UiOverlayGeometry` and `UiWindowDrawRange` names for renderer-facing UI draw data in `vulkan.ui`
- D-key debug bounds overlay with color-coded widget and layout outlines
- generic keyboard focus dispatch, SDL text input routing, and editable single-line text fields
- audio settings data for master, music, and effects volumes

Remaining migration debt:

- The renderer still imports `DemoUiScreen`, even though renderer-facing UI draw data and traversal are generic.
- popup/menu behavior is not yet implemented, so `UiDropdown` currently cycles values on click.
- keyboard navigation and tab traversal are not yet implemented for retained controls.
- settings tabs and broader settings categories are still planned demo work.
- reusable sidebar/icon-button classes, expanded sidebar labels, tooltips, and real icon assets are still planned.
- context-sensitive system mouse cursors exist for current controls and window chrome; monochrome custom bitmap cursor registration is available for theme overrides and is exercised by the widget demo probe boxes.
- audio output, audio events, and music playback are still planned engine work.
- UI animation scheduling, animated media widgets, and animated window open/close transitions are planned engine work.

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

The retained UI already has windows, labels, text blocks, buttons, image placeholders, spacers, content/frame boxes, row/column/grid containers, scroll areas, toggles, sliders, dropdowns, and text fields.

Next widgets:

- tab bar
- progress bar
- list box or selection list
- separator or divider
- left-edge sidebar or dock bar
- icon button for sidebar and toolbar actions
- tooltip for collapsed icon-only controls
- scroll area with viewport, clipping, and horizontal/vertical scrollbars
- icon/image widget backed by real texture data
- menu or popup list backing for dropdowns

The first implementation should favor simple, composable widgets over a large framework.

Detailed widget notes live in [UI Widgets](ui-widgets.md). Each existing or planned widget should have documented purpose, behavior, demo coverage, and remaining work there.

## Demo Window Structure

The demo should evolve from a test shell into a small application with clear windows:

- Main/demo control window: opens tools, exits the app, and exposes common demo actions.
- UI sidebar: a left-edge icon launcher that shows or raises demo windows and can optionally expand to show text labels next to the icons.
- Status window: app version, frame rate, active scene, current render mode, and viewport state.
- Widget demo window: currently a layout probe window; it should become an interactive control gallery for buttons, toggles, sliders, dropdowns, text fields, and future widgets.
- Chrome demo window: runtime toggles for sizeable, closable, dragable, and stackable window chrome so content-root insets and independent chrome interactions can be checked against active chrome elements.
- Help Desk window: keyboard and mouse help first, then searchable help topics and a later AI-agent style question interface.
- Settings window: display, controls, gameplay, audio, and UI options.
- Presets/shortcuts window: common layouts, render profiles, and UI actions.
- Input demo window: focus traversal, activation keys, pointer capture, disabled states, and modal focus behavior.
- Selection demo window: popup-backed dropdowns, list selection, placement, dismissal, and keyboard selection.
- Media demo window: texture-backed images, animated images, and later video-like widgets.
- Animation demo window: widget-local animation, progress animation, panel transitions, and window pop-in/close-out behavior.
- Audio demo window: UI sound events, effect preview, bus volume controls, music loop/fade/crossfade behavior, and settings preview.

The four corner windows should serve different roles so the UI reads like a real demo app rather than a fixed debug HUD.

Detailed per-window maintenance notes live in [Demo Windows](demo-windows.md). Every visible demo window should have documented purpose, covered UI classes, regression checks, and planned extensions there.

The `D` hotkey toggles a retained UI bounds overlay. When enabled, every visible widget paints a semi-transparent outline after its normal render pass so layout and nesting are inspectable at runtime. Layout containers use distinct colors for vertical stacks, horizontal rows, content/frame boxes, grids, and spacers.

`UiWindow` body content is laid out through the internal content root. A direct content widget should receive the full padded body area, and nested layout containers decide how their children consume that space. The content root must stay clear of chrome controls and the resize ring so window grips never overlap application widgets.

The former `UiSurfaceBox` role is now split into clearer `UiContentBox` and `UiFrameBox` names. `UiContentBox` is the padded content-root container used by `UiWindow`, while `UiFrameBox` is the visible framed variant for grouping content. Neither should absorb scrolling behavior. Oversized content should use a dedicated `UiScrollArea` with a viewport, clipping, `scrollX`, `scrollY`, and optional horizontal and vertical scrollbars.

The planned UI sidebar should be implemented as a chrome-less `UiWindow` variant first. `UiWindow` now supports independent header visibility, title visibility, border visibility/thickness, and content padding. Close and resize chrome are controlled by `closable` and `sizeable`; programmatic close, move, and resize remain ordinary API operations. With header, resize chrome, and border disabled, the content root can fill the whole docked window and stack 32 x 32 icon actions vertically. If a border is enabled, the content root starts inside that border. Expanded mode adds labels beside the icons, so the same content can be represented as compact icon-only actions or wider icon-plus-text rows.

Layout measurements must keep intrinsic preferred sizes separate from the current arranged size. Resizing a window larger must not permanently turn the expanded child size into the preferred size, otherwise later shrink layouts cannot reduce the content again.

Size hints and grow policy should be treated as separate layout inputs. A widget reports its natural minimum and preferred size from content, while the parent container may stretch it only when maximum size and flex growth allow that. Sidebar action buttons use this policy to keep a stable compact icon slot but still fill the full sidebar width in both collapsed and expanded modes.

The current sidebar still uses ordinary `UiButton` instances as temporary text-placeholder actions. Their centered internal label row is good enough for bootstrapping, but the planned launcher control should be a dedicated `UiIconButton`, `UiSidebarAction`, or equivalent row with a fixed 32 px icon slot and a separate expanded label region. That later widget should replace the current "icon marker plus label text in one centered caption" approach.

The sidebar should use the layout system for grouping instead of manually placing buttons. Primary demo-window actions live at the top, then a vertically growable `UiSpacer` consumes the remaining height, and bottom system actions such as Help, Settings, and Exit stay attached to the lower edge. This keeps the sidebar responsive to viewport height changes and exercises the same flex layout model future toolbars and docks should use.

The number of directly visible sidebar actions should stay limited while the minimum SDL window size is small. When the demo grows more windows than the sidebar can display comfortably, the upper launcher group should become scrollable by mouse wheel and use fade-out indicators to show that more entries exist above or below. The bottom system group should remain pinned and should not scroll with the launcher actions. The initial `UiScrollArea` already supports retained scroll offsets and wheel routing, but it still needs renderer clipping and visible scroll indicators before it should be used for this sidebar launcher group.

Interactive controls that drag, such as sliders, need local pointer capture after button-down so move and button-up events keep updating the active control until the gesture ends.

Settings-style dialogs should split the window body into a growable content area and a fixed bottom action row. The action row remains attached to the lower edge of the content root while the upper area consumes extra space.

`UiScreen` owns the 2D window stack. Windows are ordered by their position in the screen list; drawing that list from back to front is enough for layering, so no separate z value is needed. Middle-clicking ordinary stackable window chrome outside the content root toggles a window between front and back, and newly shown demo windows can be moved to a non-overlapping free position. This stacking behavior is independent of the dragable header flag. Dedicated chrome controls and resize grips receive middle and right mouse buttons before this stacking fallback so future controls can assign button-specific behavior.

`UiScreen` also owns the current keyboard focus target. Primary clicks choose the deepest focusable widget in the visible window stack; clicks on non-focusable space clear focus. The renderer forwards mapped key events and SDL text input to that focus owner before global demo shortcuts run. `UiTextField` is the first focusable text control and supports caret rendering, UTF-8 insertion, Backspace/Delete, and Home/End/Left/Right cursor movement.

Context-sensitive custom cursors should be resolved through `UiScreen`. Window chrome should report move and resize cursors, text fields should report a text insertion cursor, clickable controls should report an action cursor, and the application should fall back to the scene cursor outside UI. The SDL window layer should own platform cursor handles so widget code only reports cursor intent.

UI elements should also leave room for future animation. Local widget animation should cover state changes such as hover, press, caret blink, progress, animated images, and validation feedback. Window-level animation should cover opening, closing, and modal presentation without changing the logical layout or hit-test model unexpectedly. The current plan is captured in [UI Animation Plan](ui-animation-plan.md).

## Audio Direction

The engine should add a reusable audio system after the current UI fundamentals settle. The first target is a small SDL-backed audio service with an event queue, a mixer, short sound effects, and streamed music.

The usual split is:

- audio device ownership for SDL callback setup, sample format, buffer size, and shutdown
- audio events for play, stop, fade, and bus-volume changes
- audio mixer for active voices and bus routing
- preloaded clips for UI and game sound effects
- streamed music tracks with fade and loop support
- master, music, effects, and possibly UI buses

Gameplay and UI code should emit audio events instead of calling backend playback APIs directly. This keeps sound policy reusable, testable, and independent from `DemoUiScreen` and `VulkanRenderer`.

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

Renderer-facing draw data now uses generic UI names and lives in `vulkan.ui`. The old stateless HUD construction path has been removed from the demo UI module, so `demo_ui.d` now builds overlay geometry from retained `UiScreen`/`UiWindow` state only.

Completed legacy cleanup:

- removed the old stateless `buildHudOverlayVertices` path
- removed the old `buildHudLayout` and `HudLayoutState` bridge
- removed the old `hudDispatch...` helpers
- kept only retained screen/window/widget construction in `DemoUiScreen`

Use `UiScreen` properly:

- demo windows are registered through generic `UiScreen` helpers
- `registerWindowInteractionHandlers` owns common drag/resize wiring
- `UiScreen` owns generic window iteration, hit testing, layout, viewport clamping, and overlay geometry traversal
- demo-specific window creation, text, and callbacks stay in `DemoUiScreen`

## Planned Class And Module Order

The next work should continue from reusable engine foundations toward demo polish. A useful order is:

1. UI render boundary: move `UiOverlayGeometry` and `UiWindowDrawRange` into a reusable UI module, then let `UiScreen` expose generic render traversal. Done.
2. Cursor model: add a `UiCursorKind` enum, per-widget cursor queries, `UiScreen` cursor resolution, SDL cursor handle ownership, and optional bitmap overrides. Done for SDL system cursors and monochrome custom cursors.
3. Window chrome variants: add configurable header/title/close/resize/border/content padding so chrome-less dock/sidebar windows can be built from `UiWindow`. Done for behavior and visibility flags.
4. UI sidebar: add a left-edge icon launcher that can show, raise, or spawn demo windows and optionally expand to icon-plus-text mode. Done for demo composition with temporary `UiButton` text placeholders and bottom system actions.
5. Content box naming: rename `UiSurfaceBox` toward `UiContentBox` or `UiFrameBox` before the API becomes more public. Done by splitting the role into `UiContentBox` and `UiFrameBox`.
6. Scroll area: add viewport clipping, scroll offsets, and horizontal/vertical scrollbars for oversized content. Partial for retained offsets and wheel handling.
7. Popup primitives: add popup roots, popup placement, outside-click dismissal, and stack handling before changing dropdown behavior.
8. Selection widgets: implement popup-backed dropdowns first, then list boxes or selection lists using the same selection model.
9. Tabs and grouped settings: add a tab bar or segmented page selector, then split settings into display, controls, gameplay, audio, and UI pages.
10. Keyboard navigation: add focus traversal order, Tab and Shift-Tab movement, activation keys, and modal focus containment.
11. Dialog and modal support: add modal windows, disabled-background routing, default buttons, cancel buttons, and cursor feedback for blocked regions.
12. Demo control gallery: replace the current layout probe role with a real widget demo that exercises buttons, toggles, sliders, dropdowns, text fields, tabs, lists, and progress.
13. Demo window expansion: add Input, Selection, Media, Animation, and Audio demo windows so new UI classes are visible through realistic workflows.
14. UI animation foundation: add frame-time dispatch, widget-local animation hooks, window transition states, and renderer-facing alpha/transform data.
15. Audio foundation: add audio device ownership, event queue, bus definitions, mixer, clips, and settings-to-bus volume hookup.
16. Audio behavior: add UI click sounds, demo sound events, music streams, loop/fade/crossfade support, and an audio settings preview.
17. Asset and package boundary: decide which cursor, texture, font, shader, mesh, and audio asset conventions belong in the reusable engine package.

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
10. Add keyboard focus and single-line text editing for retained controls. Done.
11. Correct documentation and package metadata for the CC-BY-NC-SA 4.0 license, current controls, and current UI/debug behavior. Done.
12. Move renderer-facing UI geometry types from the demo module into `vulkan.ui`. Done.
13. Move generic overlay traversal from `DemoUiScreen` into `UiScreen`. Done.
14. Remove the renderer's direct dependency on `DemoUiScreen` when a reusable app/screen boundary is ready.
15. Add context-sensitive cursor intent to widgets, window chrome, `UiScreen`, and the SDL window layer. Done for SDL system cursors.
16. Add theme/custom bitmap cursor support for project-specific cursor artwork. Done for monochrome bitmap overrides.
17. Add a real theme/asset loading path for cursor definitions when the asset pipeline exists.
18. Add configurable `UiWindow` chrome attributes for header-less, title-less, border-only, and docked window roles. Done for header, title, border, and content insets.
19. Add the left-edge UI sidebar with compact 32 x 32 icon actions, optional expanded labels, window show/raise/spawn actions, and bottom Help/Settings/Exit actions. Done with temporary `UiButton` text-placeholder actions.
20. Rename or split `UiSurfaceBox` into clearer `UiContentBox` or `UiFrameBox` semantics. Done.
21. Add `UiScrollArea` for oversized content with viewport clipping, scroll offsets, wheel handling, and X/Y scrollbars. Partial for retained offsets and wheel handling.
22. Add popup/menu infrastructure so dropdowns can open real option lists instead of cycling on click.
23. Turn the current layout probe into a real widget demo/control gallery.
24. Replace temporary sidebar `UiButton` rows with `UiIconButton`, `UiSidebarAction`, or an equivalent launcher row once icon assets or placeholder icon widgets are ready.
25. Add dedicated demo windows for input/focus, selection/popups, media/images, animation, and audio coverage.
26. Add keyboard navigation, tab traversal, and modal focus behavior.
27. Add settings tabs or grouped settings panes for display, controls, gameplay, audio, and UI.
28. Add UI animation scaffolding: frame-time dispatch, widget-local tick hooks, window transition states, and renderer-facing animation parameters.
29. Add animated `UiImage` or media-widget coverage once texture-backed image rendering exists.
30. Add audio architecture scaffolding: device owner, event queue, buses, mixer, clips, and volume settings hookup.
31. Add UI and demo audio events, such as button click feedback and settings volume preview.
32. Add music playback with stream support, loop handling, fade in/out, and crossfade.
33. Review package boundaries again after UI cursors, first animation support, and the first audio service exist.

## Public Package Preparation

Before publishing on code.dlang.org, decide the package boundary:

- reusable renderer modules
- reusable UI modules
- font atlas support
- reusable audio device, event, mixer, clip, and music modules
- SDL2/Vulkan bootstrap helpers
- demo-only executable and sample assets

The public module should not expose demo-specific names, HUD naming, sample window text, or placeholder-only settings keys as engine APIs.
