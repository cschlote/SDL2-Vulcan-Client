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
- retained UI widgets: windows, labels, text blocks, buttons, image placeholders, spacers, content/frame boxes, HBox/VBox/Grid layout, scroll areas, toggles, sliders, dropdowns, text fields, tab bars, list boxes, progress bars, and separators
- widget documentation that covers existing widgets and planned widgets
- `UiScreen` as experimental generic screen/window owner
- `DemoUiScreen` as the current demo-specific UI screen
- chrome-less left-edge demo sidebar with compact 32 px style launcher buttons
- Demo window documentation that maps current and planned windows to reusable UI classes and regression checks
- INI settings load/save model
- generic `UiOverlayGeometry` and `UiWindowDrawRange` names for renderer-facing UI draw data in `vulkan.ui`
- D-key debug bounds overlay with color-coded widget and layout outlines
- generic keyboard focus dispatch, SDL text input routing, visible focus rings, focused-window title tinting, and editable single-line text fields
- audio settings data for master, music, and effects volumes
- backend-neutral audio bus/event scaffolding with settings-to-volume mapping

Remaining migration debt:

- The renderer still imports `DemoUiScreen`, even though renderer-facing UI draw data and traversal are generic.
- popup-backed dropdown behavior exists in the demo through transient popup windows and reusable `UiListBox` rows; a widget-level popup facade is still planned.
- keyboard traversal and focused control activation exist for retained controls; richer per-widget navigation policy is still planned.
- settings tabs exist for Display, UI, and Audio; Controls and Gameplay pages are still planned once those settings are editable.
- reusable sidebar container, shared tooltip popup policy, and richer icon assets are still planned; `UiSidebarAction` now covers fixed icon-slot sidebar rows with 26 x 26 images, animated expanded labels, active markers for singleton targets, collapsed-mode tooltip text hooks, and delayed demo-rendered tooltip popups placed above/right of the pointer.
- context-sensitive system mouse cursors exist for current controls and window chrome; monochrome custom bitmap cursor registration is available for theme overrides and is exercised by the widget demo probe boxes.
- asset pipeline decisions are documented: PNG should become the normal authored UI/image format, PPM remains fallback/test data, glTF/GLB should become the normal 3D model format, and gettext PO files should become the localization source format.
- asset-loaded clips, voice-limit policy, and music playback are still planned engine work; backend-neutral audio events, bus state, settings volume mapping, renderer-side settings application, SDL audio stream output, float block mixing, in-memory clips, simple voices, event-to-voice scheduling, and synthetic UI click events exist.
- UI animation scheduling, basic window transition state/geometry application, demo singleton open/close wiring, and API-level bounds transitions exist; animated media widgets and broader demo transition coverage are still planned engine work.

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

The retained UI already has windows, labels, text blocks, buttons, image placeholders, spacers, content/frame boxes, row/column/grid containers, scroll areas, toggles, sliders, dropdowns, text fields, tab bars, progress bars, list boxes, and separators.

Next widgets:

- reusable left-edge sidebar or dock bar
- icon button for sidebar and toolbar actions
- tooltip for collapsed icon-only controls
- draggable horizontal/vertical scrollbars for scroll areas
- icon/image widget backed by renderer texture data; asset-id draw intents, a fixed UI image atlas, atlas-region registry, and first file-backed low-resolution PPM demo assets exist; high-resolution authored PNG icons and package image loading remain planned
- widget-level popup/menu facade for dropdowns, context menus, and tooltips
- animated image/media widgets

The first implementation should favor simple, composable widgets over a large framework.

Detailed widget notes live in [UI Widgets](ui-widgets.md). Each existing or planned widget should have documented purpose, behavior, demo coverage, and remaining work there.

## Demo Window Structure

The demo should evolve from a test shell into a small application with clear windows:

- UI sidebar: a left-edge icon launcher that toggles singleton windows, spawns repeatable demo windows, exits the app, and can optionally expand to show text labels next to the icons.
- Status window: compact right-pinned overlay with configurable edge margins and fit-to-content sizing for app version, frame rate, active scene, current render mode, 3D object rotation, and viewport state.
- Widget demo window: first control gallery for layout probes, content/frame boxes, buttons, toggles, sliders, dropdowns, text fields, tabs, lists, progress bars, separators, and future widgets.
- UiWindow Demo window: runtime toggles, presets, and reset controls for sizeable, closable, dragable, stackable, passive chrome visibility, optional backfill, and viewport-edge pinning so content-root insets and independent chrome interactions can be checked against active chrome elements.
- Help Desk window: keyboard and mouse help first, then searchable help topics and a later AI-agent style question interface.
- Settings window: Display, UI, and Audio pages now; Controls and Gameplay pages are planned when editable settings exist.
- Presets/shortcuts window: common layouts, render profiles, and UI actions.
- Input demo window: focus traversal, activation keys, pointer capture, disabled states, and modal focus behavior.
- Selection demo window: popup-backed dropdowns, list selection, placement, dismissal, and keyboard selection.
- Media demo window: texture-backed images, animated images, and later video-like widgets.
- Animation demo window: widget-local animation, progress animation, panel transitions, and window pop-in/close-out behavior.
- Audio demo window: UI sound events, effect preview, bus volume controls, music loop/fade/crossfade behavior, and settings preview.

The visible demo windows should serve different roles so the UI reads like a real demo app rather than a fixed debug HUD.

Detailed per-window maintenance notes live in [Demo Windows](demo-windows.md). Every visible demo window should have documented purpose, covered UI classes, regression checks, and planned extensions there.

The `D` hotkey toggles a retained UI bounds overlay. When enabled, every visible widget paints a semi-transparent outline after its normal render pass so layout and nesting are inspectable at runtime. Layout containers use distinct colors for vertical stacks, horizontal rows, content/frame boxes, grids, and spacers.

Asset and localization format decisions live in [Asset And Localization Pipeline](asset-and-localization-pipeline.md). The short version is: authored UI images should use PNG and decode to engine-owned RGBA8 pixels, PPM should stay as fallback/test data, 3D models should use glTF 2.0 or GLB exported from Blender, and localized UI strings should use gettext-style PO catalogs behind a small engine lookup service.

`UiWindow` body content is laid out through the internal content root. A direct content widget should receive the full padded body area, and nested layout containers decide how their children consume that space. The content root must stay clear of chrome controls and the resize ring so window grips never overlap application widgets.

The former `UiSurfaceBox` role is now split into clearer `UiContentBox` and `UiFrameBox` names. `UiContentBox` is the padded content-root container used by `UiWindow`, while `UiFrameBox` is the visible framed variant for grouping content. Neither should absorb scrolling behavior. Oversized content should use a dedicated `UiScrollArea` with a viewport, clipping, `scrollX`, `scrollY`, and optional horizontal and vertical scrollbars.

The current UI sidebar is implemented as a chrome-less `UiWindow` composition. `UiWindow` now supports independent header visibility, title visibility, border visibility/thickness, backfill visibility/color, viewport-edge pinning, and content padding. Close and resize chrome are controlled by `closable` and `sizeable`; programmatic close, move, and resize remain ordinary API operations. With header, resize chrome, border, and backfill disabled, the content root can fill the whole docked window and stack 32 x 32 icon actions vertically. If a border is enabled, the content root starts inside that border. Expanded mode adds labels beside the icons, so the same content can be represented as compact icon-only actions or wider icon-plus-text rows.

Layout measurements must keep intrinsic preferred sizes separate from the current arranged size. Resizing a window larger must not permanently turn the expanded child size into the preferred size, otherwise later shrink layouts cannot reduce the content again.

Size hints and grow policy should be treated as separate layout inputs. A widget reports its natural minimum and preferred size from content, while the parent container may stretch it only when maximum size and flex growth allow that. Sidebar action buttons use this policy to keep a stable compact icon slot but still fill the full sidebar width in both collapsed and expanded modes.

The current sidebar uses dedicated `UiSidebarAction` rows. Each row keeps a fixed 32 px icon slot with 26 x 26 image content and a separate label region. In collapsed mode the caption is empty and only the icon is visible; in expanded mode the sidebar width animates and the same action reveals a clean text label beside the icon. Singleton targets such as Help Desk, Status, and Settings show a slim active marker while their window is open; Status starts visible and therefore active. Collapsed actions expose tooltip text through `UiScreen.tooltipAt`; the demo renders that text after a stable hover delay in a small frameless input-transparent tooltip window above/right of the pointer so it does not sit under the cursor. Once open, the tooltip remains visible while the pointer stays inside the same tooltip source region. This replaces the earlier temporary "icon marker plus label text in one centered caption" approach built from ordinary `UiButton` instances.

The sidebar should use the layout system for grouping instead of manually placing buttons. Primary demo-window actions live at the top, then a vertically growable `UiSpacer` consumes the remaining height, and bottom system actions such as Help, Status, Settings, Close All, and Exit stay attached to the lower edge. This keeps the sidebar responsive to viewport height changes and exercises the same flex layout model future toolbars and docks should use.

The current Close All sidebar action does not use `UiWindow.title` as an identity key because repeatable windows may later share visible titles. For now, the demo can use its known singleton references and repeatable-window ownership arrays: singleton windows are hidden, repeatable demo windows are removed. `UiWindow` also exposes a generated `windowId` and `UiScreen.windowById` for later engine code that needs stable handles without keeping GC-blocking object references around.

`UiWindow.title` is presentation text, not identity. The window identity model gives every `UiWindow` a stable generated id and exposes an opaque pointer-sized `userTag` for application integration. That opaque value can be a numeric tag or pointer-sized reference-style value, but it should not become the primary engine identity. Raw object or `void*` references can hide ownership and lifetime assumptions, especially when D call syntax makes `myFct(x, ...)` look like `x.myFct(...)`; this makes accidental coupling easy to miss. The safer default is: engine code searches by generated id or owned collections, application code may attach an opaque tag only when it owns the lifetime contract.

The number of directly visible sidebar actions should stay limited while the minimum SDL window size is small. At the current minimum SDL window height, the upper launcher group should stay at eight direct actions or fewer. When the demo grows more windows than the sidebar can display comfortably, the upper launcher group should become scrollable by mouse wheel and use fade-out indicators to show that more entries exist above or below. The bottom system group should remain pinned and should not scroll with the launcher actions. `UiScrollArea` already supports retained scroll offsets, wheel routing, child-geometry clipping, scrollbar thumbs, and edge overflow indicators, but it still needs direct scrollbar dragging before it should be used for this sidebar launcher group.

Interactive controls that drag, such as sliders, need local pointer capture after button-down so move and button-up events keep updating the active control until the gesture ends.

Settings-style dialogs should split the window body into a growable content area and a fixed bottom action row. The action row remains attached to the lower edge of the content root while the upper area consumes extra space.

`UiScreen` owns the 2D window stack. Windows are ordered by their position in the screen list; drawing that list from back to front is enough for layering, so no separate z value is needed. Middle-clicking ordinary stackable window chrome outside the content root toggles a window between front and back, and newly shown demo windows can be moved to a non-overlapping free position. This stacking behavior is independent of the dragable header flag. Dedicated chrome controls and resize grips receive middle and right mouse buttons before this stacking fallback so future controls can assign button-specific behavior.

`UiScreen` also owns the current keyboard focus target. Primary clicks choose the deepest focusable widget in the visible window stack; clicks on non-focusable space clear focus. The renderer forwards mapped key events and SDL text input to that focus owner before global demo shortcuts run. Focused controls draw a generic ring, and the owning window tints its title text so keyboard mode is visible without changing the header fill. `UiTextField` is the first focusable text control and supports caret rendering, UTF-8 insertion, Backspace/Delete, and Home/End/Left/Right cursor movement.

Context-sensitive custom cursors should be resolved through `UiScreen`. Window chrome should report move and resize cursors, text fields should report a text insertion cursor, clickable controls should report an action cursor, and the application should fall back to the scene cursor outside UI. The SDL window layer should own platform cursor handles so widget code only reports cursor intent.

UI elements should also leave room for future animation. Local widget animation should cover state changes such as hover, press, caret blink, progress, animated images, and validation feedback. Window-level animation should cover opening, closing, and modal presentation without changing the logical layout or hit-test model unexpectedly. The current plan is captured in [UI Animation Plan](ui-animation-plan.md).

## Audio Direction

The engine now has a first reusable audio-system scaffold for typed events, queued processing, master/music/effects/UI bus state, settings-to-bus volume mapping, renderer-side application of startup/Apply/Save settings, SDL audio stream output, a basic float block mixer, in-memory clips, simple active voices, event-to-voice scheduling for registered clips, and a synthetic UI click path for retained button activation. The next target is better short-sound behavior, asset-backed clips, and streamed music.

The usual split is:

- audio device ownership for SDL stream setup, sample format, buffer size, queueing, and shutdown; basic output exists
- audio events for play, stop, fade, and bus-volume changes; playClip/stopAll are wired to registered clips and voices
- audio mixer for active voices and bus routing; basic interleaved float block mixing with bus gain exists
- preloaded clips for UI and game sound effects; in-memory float clips exist, asset loading is planned
- streamed music tracks with fade and loop support
- master, music, effects, and UI buses; basic bus state exists

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

## Roadmap

The next work should be grouped by dependency, not by when the idea first appeared. The immediate priority is to close infrastructure gaps that affect many windows before adding more surface-level demo content.

### Priority 0: Completed Foundations

These items are considered baseline and should not be re-planned unless a regression appears:

- renderer-facing UI geometry lives in reusable `vulkan.ui` modules
- retained `UiScreen` owns generic window iteration, hit testing, layout, viewport clamping, focus, modal routing, popup windows, and overlay traversal
- `UiWindow` has configurable chrome, backfill, generated ids, optional user tags, backdrop layering, viewport-edge pinning, and transition state
- current widgets cover labels, text blocks, buttons, sidebar actions, images, spacers, content/frame boxes, row/column/grid layout, scroll areas, toggles, sliders, dropdowns, text fields, tabs, list boxes, progress bars, and separators
- demo windows cover widget, window, input/focus, selection/popup, audio, settings, status, and help workflows
- context-sensitive SDL cursors, monochrome custom cursor overrides, keyboard focus traversal, visible focus rings, title tinting, text input, and modal focus containment exist
- first audio scaffolding exists for SDL output, typed events, buses, volume settings, float mixing, in-memory clips, simple voices, synthetic UI clicks, and settings slider preview
- asset decisions are documented: PNG for authored 2D/UI images, PPM for fallback/test data, glTF/GLB for 3D models, and gettext PO for localization

### Priority 1: Layout, Popup, And Scroll Infrastructure

These items unblock several existing windows and should be addressed before expanding the demo with more content:

1. Add direct scrollbar dragging for `UiScrollArea`.
2. Use scroll areas in long Help Desk, Settings, Widget Demo, and future sidebar launcher overflow content.
3. Extract a widget-level popup facade from the current screen-owned dropdown popup path.
4. Move tooltip behavior onto that popup facade, including hover delay, placement, input transparency, and dismissal policy.
5. Keep dropdowns, context menus, and tooltips on one shared popup placement/focus/stacking model.
6. Add a modal/dialog demo slice covering default buttons, cancel buttons, blocked background routing, and focused-window title tinting.

Rationale: scroll clipping and popup ownership are structural. Without them, every new long panel, help page, menu, tooltip, or selection widget risks growing its own special case.

### Priority 2: Asset Pipeline And Visual Upgrade

This group should turn rough placeholder visuals into normal authored assets:

1. Add a neutral `ImageData` module with width, height, and RGBA8 pixels.
2. Keep the current PPM loader as a tiny fallback/test loader behind that interface.
3. Add PNG loading, preferably via SDL_image first because the project already uses SDL through BindBC.
4. Replace the rough sidebar/demo PPM placeholders with a coherent high-resolution PNG icon set.
5. Keep PPM files only as tests, fallback fixtures, or debug fixtures.
6. Route custom cursor artwork through the same asset boundary where practical.
7. Add a Media Demo pass for PNG-backed `UiImage` coverage and animated image preparation.

Rationale: this is the most visible polish step and also prepares the later model/material path, because glTF texture references should resolve through the same decoded image service.

### Priority 3: Demo Usability And Settings Coverage

Once scrolling and popup infrastructure are stable, the visible demo can grow safely:

1. Add Controls and Gameplay pages to Settings when there are real editable values.
2. Add the planned Presets/Shortcuts window after reusable command/action metadata exists.
3. Expand the Widget Demo with state variants: disabled, focused, hovered, active, long text, narrow layout, and overflow cases.
4. Expand the UiWindow Demo with modal/dialog examples and clearer presets for common window roles.
5. Add sidebar launcher scrolling only when the upper action count exceeds the current eight-action limit.
6. Continue keeping every demo window documented in [Demo Windows](demo-windows.md).

Rationale: this keeps demo growth tied to actual reusable capabilities instead of adding windows that immediately need ad hoc layout fixes.

### Priority 4: Audio Assets And Music

Audio can continue in parallel when it does not destabilize UI work:

1. Add asset-backed short clips for UI and demo sound effects.
2. Add voice-limit and replacement policy for overlapping effects.
3. Add streamed music tracks with loop, fade in/out, and crossfade support.
4. Add Music and Effects preview controls to the Audio Demo and Settings.
5. Keep the isolated idle UI-click latency issue documented until continuous playback or a callback-oriented backend clarifies whether it is an engine issue or desktop audio-stack behavior.

Rationale: the event/bus/mixer foundation exists. The next value comes from real assets and music behavior, not from more synthetic click tuning.

### Priority 5: 3D Asset Pipeline

This group replaces hand-written placeholder geometry with editor-authored models:

1. Add a glTF/GLB import spike that loads one static indexed triangle mesh.
2. Support positions, normals, UVs, indices, one material, and texture references.
3. Resolve glTF textures through the same image-loading path used by UI images.
4. Add node transforms and multiple meshes.
5. Add animation, skinning, cameras, and glTF extensions later.
6. Add a Model Demo or extend the existing scene selector with imported sample models and license/attribution tracking.

Rationale: static mesh import is enough to prove the asset boundary. Animation and full material support should wait until the minimal path is tested through real files.

### Priority 6: Localization

Localization should start after the UI text surface is stable enough to avoid churn:

1. Add a small gettext PO catalog loader or build-time catalog compiler.
2. Add a `tr`/context-aware lookup service with fallback language and missing-key logging.
3. Move sidebar labels, window titles, help text, settings labels, and demo strings behind stable ids.
4. Add translator comments for ambiguous UI labels.
5. Add a language setting only after runtime catalog switching is tested.

Rationale: PO files are the right source format, but moving strings too early creates noisy churn while demo wording is still changing.

### Priority 7: Package Boundary

The reusable package split should wait until the main services have proven their boundaries:

1. Remove the renderer's direct dependency on `DemoUiScreen`.
2. Separate engine renderer ownership from demo scene/controller ownership.
3. Define public modules for UI, renderer helpers, font atlas, asset loading, localization, and audio.
4. Keep demo window text, sample assets, settings keys, and learning-demo workflows outside the reusable package.
5. Review package metadata and examples after UI cursors, animation, asset/localization, and audio service boundaries are all exercised.

## Public Package Preparation

Before publishing on code.dlang.org, decide the package boundary:

- reusable renderer modules
- reusable UI modules
- font atlas support
- reusable asset loading for PNG images, glTF/GLB models, and later package containers
- reusable localization catalog loading and lookup
- reusable audio device, event, mixer, clip, and music modules
- SDL2/Vulkan bootstrap helpers
- demo-only executable and sample assets

The public module should not expose demo-specific names, HUD naming, sample window text, or placeholder-only settings keys as engine APIs.
