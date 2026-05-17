# UI Architecture

This document describes the retained UI engine direction. The UI is being built as a reusable part of the future D game-engine module, while the current demo application remains a proving ground for windows, widgets, layout, and input.

## Design Goals

The UI layer should behave like a small application framework, not a passive drawing helper.

The core goals are:

- widgets own their geometry, layout hints, rendering, and local input behavior
- windows provide reusable chrome, close handling, dragging, and resizing
- `UiScreen` owns screen-wide window order, viewport state, layout dispatch, and input routing
- layout is font-sensitive and deterministic
- widgets and windows can later add local animation without moving application policy into the renderer
- application-specific UI is built outside the reusable `vulkan.ui` package
- the renderer consumes generated geometry instead of owning UI behavior

The inspiration is closer to retained desktop UI systems such as Qt and Amiga Magic User Interface than to a pure immediate-mode HUD.

## Module Split

Reusable UI engine code lives in [source/vulkan/ui/](../source/vulkan/ui):

- [ui_widget.d](../source/vulkan/ui/ui_widget.d): retained widget base class
- [ui_screen.d](../source/vulkan/ui/ui_screen.d): screen-level owner for windows and input dispatch
- [ui_window.d](../source/vulkan/ui/ui_window.d): window chrome, close button, drag and resize behavior
- [ui_layout.d](../source/vulkan/ui/ui_layout.d): box-style layout containers and spacers
- [ui_label.d](../source/vulkan/ui/ui_label.d): text widgets
- [ui_button.d](../source/vulkan/ui/ui_button.d): button widget
- [ui_controls.d](../source/vulkan/ui/ui_controls.d): toggle, slider, dropdown, and text field controls
- [ui_geometry.d](../source/vulkan/ui/ui_geometry.d): renderer-facing UI overlay geometry and draw ranges
- [ui_image.d](../source/vulkan/ui/ui_image.d): small image/icon placeholder widget
- [ui_context.d](../source/vulkan/ui/ui_context.d): renderer-facing UI render context
- [ui_widget_helpers.d](../source/vulkan/ui/ui_widget_helpers.d): geometry helper functions

Demo-specific UI lives in [source/demo/demo_ui.d](../source/demo/demo_ui.d). That file currently contains `DemoUiScreen`, which builds the demo windows using the reusable UI engine.

The widget catalog in [UI Widgets](ui-widgets.md) documents current widgets, planned widgets, expected demo coverage, and open implementation questions.

## UiScreen

`UiScreen` represents the content area of the SDL window. It is the logical owner above `UiWindow`.

Generic responsibilities belong in `UiScreen`:

- store the current viewport size
- store screen-wide font atlas references
- own the ordered list of `UiWindow` objects
- iterate windows from back to front or front to back
- move windows to the front or back of the ordered list
- dispatch pointer events to top-most visible windows
- own transient popup window placement, stack priority, and outside-click/Escape dismissal
- own active modal window routing, background blocking, modal focus containment, and modal Enter/Escape action dispatch
- answer whether a pointer is inside any visible window
- drive layout for registered windows
- clamp windows to the viewport
- place windows in free screen space when possible
- start normal window open and close transitions through shared show, hide, and toggle helpers
- animate programmatic window move and resize requests through shared bounds helpers
- provide shared helpers for window dragging, resizing, toggling, registration, and removal

Responsibilities that do not belong in `UiScreen`:

- demo window titles and text
- demo settings drafts
- render mode buttons
- sample windows
- concrete game or demo behavior
- app-specific persistence policy

Those belong in a subclass such as `DemoUiScreen`, or later in a game-specific screen class.

`UiScreen` is still experimental, but `DemoUiScreen` now uses it for window registration, iteration, hit testing, layout, dragging, resizing, viewport clamping, normal window show/hide transitions, and API-level bounds transitions.

## UiWindow

`UiWindow` is the retained window widget. It owns reusable window chrome:

- title/header rendering
- content root placement
- close button
- optional header widgets
- drag hit testing
- resize corner and edge hit testing
- resize/drag tracking callbacks

Window content should be ordinary widgets. Application code should build a window body with layout containers and controls, then hand it to `UiWindow`.

Window chrome owns the resize ring, stack behavior, and header controls. Edge grips resize one dimension, corner grips resize two dimensions, and chrome buttons or grips receive middle and right mouse buttons before the generic middle-click window stacking fallback. Stackability is separate from draggability: disabling header drag should not disable middle-click front/back ordering on free chrome. The content root is inset away from active chrome, border, and resize ring so application widgets do not overlap window affordances.

`UiWindow` separates interactive chrome policy from passive chrome visibility. Sizeability, closability, draggability, and stackability define the built-in window affordances; programmatic movement, resizing, hiding, or closing remain application/API actions outside those flags. Header, title, and border visibility define how much passive chrome is shown and reserved for content layout. A chrome-less dock/sidebar window can therefore use the same top-level class: with no header and no border the content root fills the complete window; with a border enabled the content root starts inside that border.

Modal dialog conventions are attached to `UiWindow` through optional default and cancel buttons. `UiScreen` keeps the modal routing policy, while the window owns which button represents Enter or Escape. The button callback still decides what the action means, such as applying a dialog, dismissing the modal window, or showing validation feedback.

## Current Widget Set

The reusable UI package currently provides these retained widgets:

- `UiWindow`: framed, draggable, resizeable top-level window with an internal content root
- `UiLabel`: single-line text label
- `UiTextBlock`: text block placeholder for multi-line text rendering
- `UiButton`: framed button with optional icon and label content row
- `UiImage`: compact framed image/icon placeholder
- `UiSpacer`: invisible layout spacer
- `UiContentBox`: padded content root used by windows and other containers
- `UiFrameBox`: visible framed content box for grouping content
- `UiVBox`: vertical stack with spacing, padding, and flex-style growth/shrink hints
- `UiHBox`: horizontal row with spacing, padding, and flex-style growth/shrink hints
- `UiGrid`: weighted grid with explicit cell placement
- `UiScrollArea`: partial viewport for oversized content with retained scroll offsets and wheel handling
- `UiToggle`: boolean checkbox-style setting control
- `UiSlider`: horizontal floating-point value control with pointer dragging
- `UiTabBar`: horizontal page selector for grouped settings and future inspectors
- `UiDropdown`: compact option selector that opens a transient popup list through `UiScreen`
- `UiListBox`: selectable text-row list used by popup-backed dropdowns
- `UiTextField`: single-line text value field with focus, caret, UTF-8 text input, and basic cursor/edit keys

The D-key debug overlay outlines these boxes at runtime. The current color map is orange for `UiWindow`, cyan for `UiContentBox` and `UiFrameBox`, green for `UiVBox`, blue for `UiHBox`, purple for `UiGrid`, yellow for `UiSpacer`, and red for the generic widget fallback used by basic controls.

Planned widgets and widget variants include reusable `UiSidebar`, full scrollbar-backed `UiScrollArea`, `UiIconButton`, `UiProgressBar`, richer `UiTabBar` and `UiListBox` variants, `UiSeparator`, `UiPopupRoot`, `UiTooltip`, and media-oriented widgets such as animated `UiImage` and future `UiVideo`. The current demo sidebar is a composition of a chrome-less `UiWindow`, `UiVBox`, and compact or expanded text-placeholder `UiButton` rows. Those button rows are temporary: a later sidebar action widget should keep icon and label layout separate instead of encoding both into one centered caption.

`UiContentBox` and `UiFrameBox` should not become scrollable content solutions. They remain simple content/frame boxes. Oversized content belongs in a separate `UiScrollArea` that owns a viewport, scroll offsets, clipping, and horizontal or vertical scrollbars. The first `UiScrollArea` implementation owns retained offsets and wheel handling; renderer clipping and scrollbar widgets are still open.

## Context-Sensitive Cursors

The UI owns cursor intent for the regions it controls. A widget or window chrome hit test reports the cursor shape that best describes the available action, while the application falls back to the scene cursor when the pointer is outside UI.

Expected cursor states include:

- default pointer
- text insertion for focused or hoverable text fields
- horizontal, vertical, and diagonal resize cursors for window grips
- move cursor for draggable chrome
- hand or action cursor for buttons and clickable controls
- busy cursor for future long-running UI actions
- blocked cursor for the background behind an active modal window

`UiScreen` resolves final cursor intent because it already owns window order and hit testing. Individual widgets expose local cursor preferences, and `UiScreen` chooses the front-most visible result. The SDL/window layer applies the platform cursor, keeping cursor resource ownership out of individual widgets.

The first custom-cursor hook is intentionally small. `UiCursorBitmap` describes a monochrome theme cursor for a `UiCursorKind`, and the SDL window wrapper can register that bitmap as an override for the matching system cursor slot. If no custom bitmap is registered, the existing SDL system cursor remains the fallback. A later asset pipeline can load these bitmap definitions from theme data without changing widget cursor intent.

The current demo registers a small custom inspect cursor for `UiCursorKind.crosshair`; the layout probe boxes in the Widget Demo use that cursor so custom cursor registration can be checked at runtime.

## UiWidget Box Model

`UiWidget` is the smallest retained UI object: a rectangular box with local coordinates, layout hints, children, optional focusability, and optional input handling.

The widget model should continue toward a clear box model:

- outer rectangle
- minimum, preferred, and maximum size
- flex growth hints as layout policy, not as intrinsic content size
- optional surface/background behavior in specialized widgets
- padding and spacing in layout containers
- children positioned in local coordinates
- optional focus ownership for controls that consume keyboard or text input

Children should receive a well-defined content area. Chrome, border, and gutter decisions should be owned by the widget or layout container that introduces them.

Layout follows the same broad idea as mature retained UI systems: a widget reports a natural content size, then the parent layout uses minimum, preferred, maximum, and grow hints to decide the arranged size. A control such as `UiButton` may therefore measure its caption as a compact natural width while still filling a sidebar or form row when its maximum width and horizontal grow hint allow stretching. Widgets should not silently turn their current arranged size into their future intrinsic size, because that makes later shrink layouts impossible.

`UiScreen` owns keyboard focus at the window-stack level. Primary pointer-down selects the deepest focusable widget under the pointer or clears focus when no focusable widget is hit. `Tab` and `Shift-Tab` move through visible focusable widgets in front-window traversal order, including dropdown controls. Focused widgets receive generic key events and UTF-8 text input before the demo renderer evaluates global shortcuts, so editing a text field does not accidentally change render modes. Focus ownership is visible: the focused widget draws a generic focus ring, and the window that owns that focused widget tints its title text.

## Font-Sensitive Layout

The UI should be font-sensitive by default. Text measurement must influence:

- button width and height
- label and text-block size
- window minimum size
- dialog layout
- row and column allocation

This is essential for a UI system inspired by MUI-style automatic layout. Hard-coded rectangles are acceptable for bootstrapping, but final UI windows should derive their useful size from font and content measurements.

## Input Ownership

Input should be routed to the widget that owns the hit region.

The expected event flow is:

1. `UiScreen` receives an input event in screen coordinates.
2. It walks visible windows in front-to-back order.
3. The first window that handles the event consumes it.
4. The window routes the event through chrome and then into its body widgets.
5. The target widget handles the event or emits a callback/signal.

This keeps behavior local. A button decides when it was clicked. A future slider decides how dragging maps to a value. A window decides whether the event starts dragging the window or reaches the body.

## Signals And Callbacks

The current code uses direct delegates for button clicks, close events, drag events, and resize events. That is enough for the current stage.

The longer-term direction is signal-like communication:

- controls emit typed events or typed callbacks
- application screens connect those events to behavior
- widgets do not need to know the owning game or demo object

Whether signals are synchronous delegates, queued events, or a small typed event bus remains open.

## Animation Direction

The retained UI should reserve a path for animation without changing ownership boundaries. Widgets may later animate their own visual state, such as hover fades, caret blinking, animated images, media widgets, progress movement, or validation feedback. Windows may later animate their own presentation, such as short pop-in and close-out transitions.

The default rule should keep layout and hit testing based on logical retained rectangles while rendering applies transient alpha, scale, frame selection, or small offsets. `UiScreen` owns frame-time dispatch through `tickUi`, while `UiWidget` owns recursive widget-local tick hooks. `UiWindow` owns logical open/close transition state, progress, and API-level bounds interpolation. `UiWindowDrawRange` carries the current window alpha, scale, and offset across the renderer boundary. `UiScreen.buildOverlayGeometry` applies those window presentation values to the generated vertex positions and alpha before upload, so the renderer still draws resolved geometry and does not own animation policy.

See [UI Animation Plan](ui-animation-plan.md) for the planned scheduler, widget-local animation, media-widget, and window-transition model.

## Renderer Boundary

The renderer should not know widget internals. It should receive generated UI geometry and draw ranges.

Current boundary:

- `UiOverlayGeometry` and `UiWindowDrawRange` live in `vulkan.ui.ui_geometry` as generic renderer-facing data types.
- `UiScreen.buildOverlayGeometry` owns generic retained window traversal and emits renderer-facing overlay geometry.
- The renderer still imports `DemoUiScreen` because the current application screen owns demo windows, labels, settings drafts, and callbacks.

Target direction:

- keep renderer-facing UI geometry named generically
- keep demo-specific screen construction in `source/demo/`
- keep reusable widget and screen code in `source/vulkan/ui/`
- split renderer ownership so reusable engine rendering no longer imports a demo screen class

## Persistence Policy

The reusable UI engine should not save settings by itself. Persistence is an application concern.

For the demo application:

- loading settings at startup is fine
- Apply updates the running state only
- Save writes settings to disk
- closing the app must not silently persist changed UI settings unless the user explicitly saved

This policy keeps runtime experimentation separate from permanent configuration.

## Open Questions

- Should UI signals stay as delegates or become typed event objects?
- Should `UiScreen.buildOverlayGeometry` stay as the final render traversal API, or should it become part of a separate UI renderer object?
- Should future color or animated cursors be represented as theme assets, renderer textures, SDL surfaces, or a backend-specific extension?
- Which modal dialog conventions should be built on top of the current modal routing primitive?
- Should docking and grouping live in `UiScreen` or in a separate layout manager?
- Should the left-edge UI sidebar reserve viewport space, overlay the scene, or support both modes?
- Should `UiScrollArea` support both axes in the first version, or should vertical scrolling land first?
- Which UI pieces are stable enough for the first public engine module?

## Related Files

- [source/vulkan/ui/ui_screen.d](../source/vulkan/ui/ui_screen.d)
- [source/vulkan/ui/ui_widget.d](../source/vulkan/ui/ui_widget.d)
- [source/vulkan/ui/ui_window.d](../source/vulkan/ui/ui_window.d)
- [source/vulkan/ui/ui_layout.d](../source/vulkan/ui/ui_layout.d)
- [source/vulkan/ui/ui_context.d](../source/vulkan/ui/ui_context.d)
- [source/demo/demo_ui.d](../source/demo/demo_ui.d)
- [source/vulkan/engine/renderer.d](../source/vulkan/engine/renderer.d)
- [docs/demo-ui-plan.md](demo-ui-plan.md)
- [docs/ui-widgets.md](ui-widgets.md)
- [docs/demo-windows.md](demo-windows.md)
- [docs/ui-animation-plan.md](ui-animation-plan.md)
