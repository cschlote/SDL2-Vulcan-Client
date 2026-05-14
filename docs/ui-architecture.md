# UI Architecture

This document captures the current UI direction for the project and the ideas we want to preserve before the implementation grows further.

The goal is to keep the interface understandable, self-contained, and easy to extend. The current retained widget layer is a good starting point, but the next step is to make input flow and widget communication explicit enough that the UI can express more behavior on its own.

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
- window, container, label, and button widgets in [source/vulkan/ui/](../source/vulkan/ui/)
- a render context that carries the current origin and target buffers in [source/vulkan/ui/ui_context.d](../source/vulkan/ui/ui_context.d)
- the HUD assembly path in [source/vulkan/ui_layer.d](../source/vulkan/ui_layer.d)

That means the project already thinks in terms of widgets and local coordinates. What is still missing is a first-class event model that lets widgets react directly to input and publish meaningful output.

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

The layout system should be introduced now, not later.

The current demo already behaves like a manually positioned grid: sizes, offsets, and positions are calculated in code and then used to place widgets directly. That is acceptable for a small prototype, but it does not scale well once resizable windows, docking, or richer content are added.

The preferred direction is a small retained layout core with two main primitives:

- horizontal and vertical boxes for most content areas
- a simple grid for places where explicit X/Y positioning is still the clearest option

That gives the project a practical middle ground. The window chrome can stay explicit and hand-placed, while the inner content area can be arranged automatically by layout rules instead of fixed coordinates.

This approach has a few advantages:

- resize behavior becomes a natural consequence of the layout tree
- content can reflow without rewriting every widget position by hand
- later docking and grouping features have a stable foundation
- the code stays readable because most cases are handled by a small number of containers

The layout system does not need to solve every UI problem on day one. It should first cover the common retained-widget cases and leave special-purpose placement to the grid path.

## Backgrounds, Frames, and Spacing

The next presentation step should separate three concerns that are currently mixed together in a few widgets:

- background fill for the widget body or chrome surface
- frame or border decoration around the surface
- layout spacing inside or around the widget content

This keeps translucent surfaces predictable. A widget should not need to fake transparency by painting over its children; instead, the widget can simply choose a background color with alpha, or skip drawing the background entirely when it should be fully transparent.

The same idea applies to frame styling. A frame should be a renderable surface decoration, while margins and padding should stay in the layout layer. That gives the UI a familiar box model without forcing every widget to manually reserve space for borders or visual gutters.

In practice, the layout code should reserve chrome space by offsetting and padding child widgets, while the render code should only paint the surface it owns. A header background should stop short of explicit chrome controls and resize grips; those controls should sit in their own layout band instead of being covered by one large opaque strip.

The first practical margin use case is the window body: keep the shell background visible all the way to the frame, then inset the content root by a few pixels so inner widgets do not sit directly on the border line.

The practical target is a small box-style widget layer that can:

- paint an optional background with alpha
- paint an optional border or frame
- expose padding and margin for layout
- leave children responsible for their own surface style

This is the right level for the current codebase because the retained tree already knows local coordinates, and the chrome widgets already own their interaction behavior. The next step is to move visual surface policy into reusable box helpers instead of hard-coding it in window chrome.

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
- [source/vulkan/ui_layer.d](../source/vulkan/ui_layer.d)
- [docs/rendering-architecture.md](rendering-architecture.md)
