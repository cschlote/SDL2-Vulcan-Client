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

Docking and grouping:

- windows may need to snap or dock to each other
- grouped windows would make complex layouts easier to manage
- docking will require clear geometry and neighbor relationships

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
- should layout be fully manual, constraint-based, or partially automatic
- should animation live inside the widget or in a separate presentation layer
- how should dragging, docking, and resizing interact when multiple widgets overlap

These are not blockers, but they should stay visible so the code does not drift into an ad hoc event system.

## Related Files

- [source/vulkan/ui/ui_widget.d](../source/vulkan/ui/ui_widget.d)
- [source/vulkan/ui/ui_context.d](../source/vulkan/ui/ui_context.d)
- [source/vulkan/ui/ui_widget_helpers.d](../source/vulkan/ui/ui_widget_helpers.d)
- [source/vulkan/ui_layer.d](../source/vulkan/ui_layer.d)
- [docs/rendering-architecture.md](rendering-architecture.md)
