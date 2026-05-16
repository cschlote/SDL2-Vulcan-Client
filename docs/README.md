# Documentation

This folder collects the project-facing documentation for the engine prototype, the Vulkan demo, and the retained UI layer.

## Entry Points

- [Vulkan Quickstart](vulkan-quickstart.md) explains the rendering stack, resource flow, and frame lifecycle.
- [Rendering Architecture](rendering-architecture.md) describes the layered scene/UI composition and current renderer ownership.
- [UI Architecture](ui-architecture.md) captures the retained UI engine model, `UiScreen` ownership, widget layout, and event routing.
- [Audio Architecture](audio-architecture.md) captures the planned audio event, mixer, stream, and music model.
- [Demo UI Plan](demo-ui-plan.md) tracks the current demo UI migration and the plan for moving toward a reusable engine module.
- [Shader Guide](shaders.md) explains the GLSL sources and how they map to the renderer.

## Current Direction

The repository is both a learning demo and the staging area for a reusable D game-engine module. The demo keeps the implementation visible and testable while the reusable parts settle:

- `source/vulkan/engine/` contains the current Vulkan rendering spine.
- `source/vulkan/ui/` contains the reusable retained UI widget engine.
- future audio modules should contain reusable audio device, mixer, event, and music playback services.
- `source/demo/` contains application-specific bootstrap, settings, and demo UI construction.

The documentation should stay aligned with that split. Demo-specific behavior belongs in demo docs and plans; reusable UI and renderer concepts should be described as engine concepts.
