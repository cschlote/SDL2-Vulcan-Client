# UI Architecture

This document describes the retained UI engine direction. The UI is being built as a reusable part of the future D game-engine module, while the current demo application remains a proving ground for windows, widgets, layout, and input.

## Design Goals

The UI layer should behave like a small application framework, not a passive drawing helper.

The core goals are:

- widgets own their geometry, layout hints, rendering, and local input behavior
- windows provide reusable chrome, close handling, dragging, and resizing
- `UiScreen` owns screen-wide window order, viewport state, layout dispatch, and input routing
- layout is font-sensitive and deterministic
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
- [ui_image.d](../source/vulkan/ui/ui_image.d): small image/icon placeholder widget
- [ui_context.d](../source/vulkan/ui/ui_context.d): renderer-facing UI render context
- [ui_widget_helpers.d](../source/vulkan/ui/ui_widget_helpers.d): geometry helper functions

Demo-specific UI lives in [source/demo/demo_ui.d](../source/demo/demo_ui.d). That file currently contains `DemoUiScreen`, which builds the demo windows using the reusable UI engine.

## UiScreen

`UiScreen` represents the content area of the SDL window. It is the logical owner above `UiWindow`.

Generic responsibilities belong in `UiScreen`:

- store the current viewport size
- store screen-wide font atlas references
- own the ordered list of `UiWindow` objects
- iterate windows from back to front or front to back
- move windows to the front or back of the ordered list
- dispatch pointer events to top-most visible windows
- answer whether a pointer is inside any visible window
- drive layout for registered windows
- clamp windows to the viewport
- place windows in free screen space when possible
- provide shared helpers for window dragging, resizing, toggling, registration, and removal

Responsibilities that do not belong in `UiScreen`:

- demo window titles and text
- demo settings drafts
- render mode buttons
- sample windows
- concrete game or demo behavior
- app-specific persistence policy

Those belong in a subclass such as `DemoUiScreen`, or later in a game-specific screen class.

`UiScreen` is still experimental, but `DemoUiScreen` now uses it for window registration, iteration, hit testing, layout, dragging, resizing, and viewport clamping. The next cleanup question is whether renderer-facing overlay geometry should also become a generic `vulkan.ui` type.

## UiWindow

`UiWindow` is the retained window widget. It owns reusable window chrome:

- title/header rendering
- content root placement
- close button
- optional header widgets
- drag hit testing
- resize corner hit testing
- resize/drag tracking callbacks

Window content should be ordinary widgets. Application code should build a window body with layout containers and controls, then hand it to `UiWindow`.

## Current Widget Set

The reusable UI package currently provides these retained widgets:

- `UiWindow`: framed, draggable, resizeable top-level window with an internal content root
- `UiLabel`: single-line text label
- `UiTextBlock`: text block placeholder for multi-line text rendering
- `UiButton`: framed button with optional icon and label content row
- `UiImage`: compact framed image/icon placeholder
- `UiSpacer`: invisible layout spacer
- `UiSurfaceBox`: optional background/border surface that assigns its child the full padded content area
- `UiVBox`: vertical stack with spacing, padding, and flex-style growth/shrink hints
- `UiHBox`: horizontal row with spacing, padding, and flex-style growth/shrink hints
- `UiGrid`: weighted grid with explicit cell placement
- `UiToggle`: boolean checkbox-style setting control
- `UiSlider`: horizontal floating-point value control with pointer dragging
- `UiDropdown`: compact option selector that cycles values until popup menus exist
- `UiTextField`: single-line text value field with focus state; keyboard editing is still planned

The D-key debug overlay outlines these boxes at runtime. The current color map is orange for `UiWindow`, cyan for `UiSurfaceBox`, green for `UiVBox`, blue for `UiHBox`, purple for `UiGrid`, yellow for `UiSpacer`, and red for the generic widget fallback used by basic controls.

## UiWidget Box Model

`UiWidget` is the smallest retained UI object: a rectangular box with local coordinates, layout hints, children, and optional input handling.

The widget model should continue toward a clear box model:

- outer rectangle
- minimum, preferred, and maximum size
- flex growth hints
- optional surface/background behavior in specialized widgets
- padding and spacing in layout containers
- children positioned in local coordinates

Children should receive a well-defined content area. Chrome, border, and gutter decisions should be owned by the widget or layout container that introduces them.

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

## Renderer Boundary

The renderer should not know widget internals. It should receive generated UI geometry and draw ranges.

Current boundary:

- `UiOverlayGeometry` and `UiWindowDrawRange` are the current generic renderer-facing data types.
- The renderer imports `DemoUiScreen` because the demo currently owns overlay construction.

Target direction:

- keep renderer-facing UI geometry named generically
- keep demo-specific screen construction in `source/demo/`
- keep reusable widget and screen code in `source/vulkan/ui/`
- move renderer-facing UI geometry types into `vulkan.ui` once `UiScreen` owns enough generic render traversal

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
- Should there be a generic `UiOverlayGeometry` type in `vulkan.ui`?
- Should `UiScreen` expose a render method that builds geometry, or should rendering stay in app-specific screen classes for now?
- How should focus, keyboard navigation, and modal windows be represented?
- Should docking and grouping live in `UiScreen` or in a separate layout manager?
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
