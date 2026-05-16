# UI Animation Plan

This document captures the planned animation model for the retained UI layer. No animation runtime exists yet. The goal is to reserve clean ownership boundaries now so later animated widgets, media widgets, and window transitions can be added without rewriting input routing or layout.

## Goals

- let individual widgets animate their own visual state
- support animated `UiImage`, future media widgets, progress indicators, and value transitions
- support top-level window open and close transitions such as scale, alpha, and slight position easing
- keep layout deterministic while visual animation is running
- keep input hit testing based on the retained logical widget tree
- avoid renderer-specific animation policy in demo code

## Non-Goals For The First Version

- no full scene graph rewrite
- no timeline editor
- no physics-based UI layout
- no animation dependency on external asset tools
- no requirement that all widgets become animated immediately

## Ownership Model

Animation state should live with the object that owns the visual effect.

- `UiWidget` should be able to request a repaint or advance an optional local animation.
- `UiWindow` should own top-level transition state for opening, closing, minimizing, or modal presentation.
- `UiScreen` should own frame-time dispatch, active animation collection, and transition cleanup for windows leaving the stack.
- The renderer should receive already-resolved draw geometry, color, alpha, and transform data.
- Demo code should select example transitions and wire controls, but should not own the reusable animation scheduler.

This keeps game and demo screens declarative: a screen asks a window to open, close, or animate a state; the UI engine decides how that effect progresses.

## Time And Scheduling

The UI layer needs a small time source independent from input events. `UiScreen` can receive frame delta time from the renderer before building overlay geometry.

Expected first API shape:

- `UiScreen.tickUi(float deltaSeconds)`
- `UiWidget.tick(float deltaSeconds)` for widgets with active local animation
- `UiWindow.tickTransition(float deltaSeconds)` for top-level transition state
- a boolean result or dirty flag that tells the renderer whether another frame is needed even when input is idle

The scheduler should clamp large delta values after stalls or breakpoints so transitions do not jump through several visual states at once.

## Widget-Local Animation

Widget-local animation covers visual changes that do not alter the ownership tree.

Examples:

- button hover or press highlight fade
- slider thumb easing toward a value
- caret blink in `UiTextField`
- progress bar fill movement
- animated icon frame selection
- validation color pulse for invalid text input

The logical rectangle should normally remain stable during widget-local animation. If an animation needs to affect measured size, that should be an explicit layout animation feature later, because it changes parent container negotiation.

## Animated Images And Media Widgets

Animated `UiImage`, `UiVideo`, or similar widgets should be modeled as content widgets with their own playback state.

Expected responsibilities:

- asset identity and frame source
- play, pause, stop, loop, and playback speed state
- current frame index or timestamp
- optional aspect-ratio preserving layout hints
- renderer-facing texture or atlas region selection

The first implementation can start with frame-indexed animated images before real video decoding exists. A later asset pipeline can decide whether frames come from sprite sheets, image sequences, or decoded media streams.

## Window Transitions

Top-level window transitions should be owned by `UiWindow` and coordinated by `UiScreen`.

Common transition states:

- hidden
- opening
- visible
- closing

Common transition properties:

- alpha
- scale
- translation offset
- optional shadow or border emphasis

Apple-style pop-in behavior can be approximated with a short scale-and-alpha ease from the window center. Close behavior should mirror the open transition and remove or hide the window only after the transition completes.

Input policy must be explicit:

- opening windows can usually receive input once visible enough, or after the transition completes
- closing windows should normally stop accepting new input immediately
- modal transitions should block background input according to modal routing, not according to draw alpha

## Layout And Hit Testing

Animation should not make hit testing ambiguous.

Default rule:

- layout and hit testing use the retained logical rectangle
- rendering may apply transient visual alpha, scale, or offset

Exceptions should be rare and documented. For example, an animated expanding panel may need its current animated height to participate in layout. That should be handled by a layout-aware transition type, not by ad hoc rendering offsets.

## Renderer Boundary

The current UI renderer consumes `UiOverlayGeometry` and `UiWindowDrawRange`. To support animation, renderer-facing UI geometry may later need:

- per-window or per-widget alpha
- optional 2D transform data
- texture frame references for image widgets
- clipping rectangles for animated panels or media widgets

The renderer should still not own widget state. It should draw the current frame described by the UI layer.

## Demo Coverage

The demo should add an Animation Demo window when the scheduler exists. Until then, the planning target is:

- keep widget rendering methods small enough to accept animated visual parameters later
- avoid hard-coding all visual state as immutable constants
- keep window close behavior separable from window destruction
- ensure spawned demo windows can be hidden first and removed after a transition later

The Chrome Demo is the natural first place to test open and close transitions. The Widget Demo and future Media Demo are the natural places to test widget-local animation and animated images.

## Open Questions

- Should transitions be configured by simple structs, delegates, or theme data?
- Should animation easing functions live in `vulkan.ui` or a more general engine module?
- How should animations be paused when the application is minimized?
- Should animated cursors use the same timing model as UI widgets, or stay backend/theme-specific?
- How should video or media decoding integrate with the render thread and asset lifetime?

