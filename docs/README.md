# Documentation

This folder collects the project-facing documentation for the codebase and its architecture.

## Entry Points

- [Vulkan Quickstart](vulkan-quickstart.md) gives a senior-level overview of the rendering stack, resource flow, and frame lifecycle.
- [Shader Guide](shaders.md) explains the GLSL sources and how they map to the renderer.
- [Rendering Architecture](rendering-architecture.md) describes the layered image composition and the placeholder geometry strategy.
- [UI Architecture](ui-architecture.md) captures the current widget, input, signal, and layout ideas for the retained UI layer.

## Scope

The repository is intentionally compact, so the docs focus on the parts that matter when you want to extend the code rather than on an exhaustive tutorial. The current overlay is custom, but the frame lifecycle, descriptor flow, and per-frame resource separation are the same concepts you would apply to any future UI layer.
