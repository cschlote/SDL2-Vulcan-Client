# Documentation

This folder collects the project-facing documentation for the engine prototype, the Vulkan demo, and the retained UI layer.

## Entry Points

- [Vulkan Quickstart](vulkan-quickstart.md) explains the rendering stack, resource flow, and frame lifecycle.
- [Rendering Architecture](rendering-architecture.md) describes the layered scene/UI composition and current renderer ownership.
- [UI Architecture](ui-architecture.md) captures the retained UI engine model, `UiScreen` ownership, widget layout, and event routing.
- [UI Widgets](ui-widgets.md) documents existing and planned widgets, including the current demo sidebar and planned reusable sidebar class.
- [Demo Windows](demo-windows.md) documents the current and planned demo windows that exercise UI classes through normal use cases.
- [UI Animation Plan](ui-animation-plan.md) captures the planned retained UI animation and window transition model.
- [Audio Architecture](audio-architecture.md) captures the planned audio event, mixer, stream, and music model.
- [Asset And Localization Pipeline](asset-and-localization-pipeline.md) records the chosen PNG, glTF/GLB, and gettext/PO asset and localization direction.
- [Demo UI Plan](demo-ui-plan.md) tracks the current demo UI migration and the plan for moving toward a reusable engine module.
- [Shader Guide](shaders.md) explains the GLSL sources and how they map to the renderer.

## Current Direction

The repository is both a learning demo and the staging area for a reusable D game-engine module. The demo keeps the implementation visible and testable while the reusable parts settle:

- `source/vulkan/engine/` contains the current Vulkan rendering spine.
- `source/vulkan/ui/` contains the reusable retained UI widget engine.
- `source/vulkan/audio/` contains the first reusable audio device, mixer, event, clip, voice, and system modules; music streaming remains planned.
- future reusable asset and localization modules should decode PNG/glTF/PO-style project data before handing neutral runtime data to the renderer, UI, and demo code.
- `source/demo/` contains application-specific bootstrap, settings, and demo UI construction.

The documentation should stay aligned with that split. Demo-specific behavior belongs in demo docs and plans; reusable UI and renderer concepts should be described as engine concepts.
