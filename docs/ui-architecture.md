# UI Architecture

This document captures the current UI direction for the project and the implementation details we want to preserve as the retained widget tree grows.

The goal is to keep the interface understandable, self-contained, and easy to extend. The current retained widget layer already has explicit window chrome, box helpers, and layout containers, so the next step is to keep those pieces consistent as more behavior is added.

## Design Goals

The UI layer should behave like a small application framework instead of a passive drawing helper.

The main goals are:

- widgets handle their own input when they are responsible for a region
- widgets can emit events instead of forcing a central controller to copy values around
- layout remains explicit and deterministic
- the UI can evolve without depending on the 3D renderer internals
- the system stays small enough to reason about in source code

This is closer to classic retained UI systems than to a pure immediate-mode approach.

## Current Shape

The existing UI code already has the right building blocks:

- a retained widget tree in [source/vulkan/ui/ui_widget.d](../source/vulkan/ui/ui_widget.d)
- window, container, label, button, and layout widgets in [source/vulkan/ui/](../source/vulkan/ui/)
- a render context that carries the current origin and target buffers in [source/vulkan/ui/ui_context.d](../source/vulkan/ui/ui_context.d)
- the HUD assembly path in [source/vulkan/ui_layer.d](../source/vulkan/ui_layer.d)

That means the project already thinks in terms of widgets and local coordinates. The remaining work is to keep event handling, geometry generation, and layout policy aligned as the UI grows.

## UiScreen And Ownership

The retained UI tree benefits from a single top-level owner that acts as the global entry point for a frame.

That top-level object should be understood as a UiScreen-style coordinator:

- it owns the root UI tree or the root windows
- it stores screen-wide resources such as font atlases, theme data, and viewport-dependent state
- it drives the explicit layout and render passes
- it can also own global input routing, focus state, and animation timing

This keeps the global responsibilities in one place instead of spreading them across individual widgets. Widgets should be able to focus on their own local geometry and interaction while the screen object provides the shared context they need.

## UiWidget As Box Model

UiWidget should be treated as the smallest reusable retained UI object: a rectangular box with layout hints and optional surface styling.

In this model the widget owns:

- its outer rectangle
- minimum, preferred, and maximum sizing hints
- optional margin and padding policy
- optional background and frame/border drawing
- child ownership for nested retained UI elements

The important rule is that children only receive the inner content area. The outer frame belongs to the widget itself, while the inner rect is the space available for child layout.

That means a widget can reserve chrome, borders, or gutters without forcing every child to understand those details. A button, panel, or container can therefore compute its own inner layout and still remain visually consistent with the rest of the UI.

The practical consequences are straightforward:

- layout computes outer size first and then derives the inner working area
- render draws the widget's own surface before or around its children as needed
- children never overlap the border unless the widget deliberately exposes that space
- the layout tree stays readable because spacing policy lives at the widget boundary instead of being hand-coded into every child

## Input Ownership

Input should be routed to the widget that owns the hit region.

The UI layer should not act as a permanent controller that translates one widget's value into another widget's state by hand. Instead, the layer should:

1. perform hit testing
2. locate the top-most relevant widget
3. deliver the input event to that widget
4. let the widget either consume the event or emit a signal

This keeps the interaction local. A button can decide whether a click matters. A slider can decide whether dragging changes its value. A window can decide whether the pointer should start moving the window instead of reaching a child control.

## Signals

Signals are a good fit for the kind of UI the project wants.

They allow widgets to communicate without hard-wiring one widget to another. Examples:

- a slider emits a value changed signal
- a mode button emits a selected mode signal
- a toggle widget emits an on/off signal
- a text field emits a committed value signal

This is useful because it keeps the widget responsible for its own interaction while still allowing other parts of the UI to react.

The current code already uses direct callbacks for the built-in close button and the window chrome gestures, so signals remain an architectural option rather than a missing prerequisite.

The intended effect is similar to Qt and other signal-based systems: the UI can express behavior without every action being manually forwarded through a central controller.

## Buttons and Events

Buttons should not just be visual elements.

They should:

- do their own hit testing
- track hover, pressed, and released states if needed
- emit a click or activation event when the user completes the interaction
- remain reusable for menu-like stacks, tool bars, and settings panels

In the current project this is especially relevant for the render-mode window, where the button row is already a natural candidate for local event handling.

## Layout Strategy

The layout system is already part of the codebase and should continue to be extended deliberately.

The current demo still mixes explicit chrome placement with layout containers, but sizes, offsets, and positions are now handled by reusable box, row, column, and grid widgets instead of being hard-coded everywhere. That is acceptable for a small prototype, and it gives enough structure for resizable windows, docking, or richer content.

The preferred direction is a small retained layout core with two main primitives:

- horizontal and vertical boxes for most content areas
- a simple grid for places where explicit X/Y positioning is still the clearest option

That gives the project a practical middle ground. The window chrome can stay explicit and hand-placed, while the inner content area can be arranged automatically by layout rules instead of fixed coordinates.

This approach has a few advantages:

- resize behavior becomes a natural consequence of the layout tree
- content can reflow without rewriting every widget position by hand
- later docking and grouping features have a stable foundation
- the code stays readable because most cases are handled by a small number of containers

The layout system does not need to solve every UI problem on day one. It already covers the common retained-widget cases and can leave special-purpose placement to the grid path.

## Backgrounds, Frames, and Spacing

The current presentation layer already separates these concerns in some places, and the next step is to apply that split more consistently across the UI:

- background fill for the widget body or chrome surface
- frame or border decoration around the surface
- layout spacing inside or around the widget content

This keeps translucent surfaces predictable. A widget should not need to fake transparency by painting over its children; instead, the widget can simply choose a background color with alpha, or skip drawing the background entirely when it should be fully transparent.

The same idea applies to frame styling. A frame should be a renderable surface decoration, while margins and padding should stay in the layout layer. That gives the UI a familiar box model without forcing every widget to manually reserve space for borders or visual gutters.

In practice, the layout code should reserve chrome space by offsetting and padding child widgets, while the render code should only paint the surface it owns. The header can keep a reserved control band on the right, and the content can then be separated from the header by a thin optical groove instead of a second full-width fill band.

The first practical margin use case is the window body: keep the shell background visible all the way to the frame, then inset the content root by a few pixels so inner widgets do not sit directly on the border line.

The practical target is a small box-style widget layer that can:

- paint an optional background with alpha
- paint an optional border or frame
- expose padding and margin for layout
- leave children responsible for their own surface style

This is the right level for the current codebase because the retained tree already knows local coordinates, and the chrome widgets already own their interaction behavior. The remaining work is to keep visual surface policy in reusable box helpers instead of hard-coding it in window chrome.

## Icons and Small Graphics

The UI should support small decorative graphics in addition to text.

This matters for game-like interfaces where icons, state markers, and compact visual cues are often more useful than text alone. The system should leave room for:

- static icons
- simple sprite-like images
- animated icons or small looping graphics
- state-dependent decorations for buttons or indicators

The interface does not need a large asset system right away, but the widget model should not block these future additions.

## Future Layout Requirements

Several likely requirements are already visible and should be kept in mind while the UI evolves.

Resizable windows:

- windows should eventually support size changes
- content should react to window dimensions instead of relying only on fixed offsets
- minimum sizes and content clipping will matter once resizing is enabled
- the current demo can still grow the window without re-laying out the widgets, but that should only be a temporary stepping stone

Docking and grouping:

- windows may need to snap or dock to each other
- grouped windows would make complex layouts easier to manage
- docking will require clear geometry and neighbor relationships

Hybrid layout:

- chrome and decoration should remain explicit
- inner content should use the layout system
- manual placement should remain available for special cases, icons, and tight control surfaces

These features are easier to add if the widget tree, the hit testing, and the event dispatch are already explicit.

## Reference Inspirations

The project can borrow ideas from several GUI traditions without copying them directly.

Useful references include:

- Magic User Interface on the Amiga for its gadget-oriented structure
- Qt for signals and object-style event propagation
- game UI systems for icon-heavy, compact, and animated controls

The purpose of the references is not visual imitation. The useful part is the architecture: small widgets, local ownership, and clear event flow.

## Open Questions

The following questions should be answered as the implementation grows:

- should signals be synchronous or queued
- should widgets emit typed events or a generic event structure
- should the layout core be box-first with a small grid escape hatch
- how much of the chrome should stay manual versus layout-driven
- should box widgets own background, frame, padding, and margin policy
- should animation live inside the widget or in a separate presentation layer
- how should dragging, docking, and resizing interact when multiple widgets overlap

These are not blockers, but they should stay visible so the code does not drift into an ad hoc event system.

## Related Files

- [source/vulkan/ui/ui_widget.d](../source/vulkan/ui/ui_widget.d)
- [source/vulkan/ui/ui_context.d](../source/vulkan/ui/ui_context.d)
- [source/vulkan/ui/ui_widget_helpers.d](../source/vulkan/ui/ui_widget_helpers.d)
- [source/vulkan/ui/ui_layout.d](../source/vulkan/ui/ui_layout.d)
- [source/vulkan/ui/ui_window.d](../source/vulkan/ui/ui_window.d)
- [source/vulkan/ui_layer.d](../source/vulkan/ui_layer.d)
- [docs/rendering-architecture.md](rendering-architecture.md)
