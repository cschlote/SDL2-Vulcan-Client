# Documentation

This folder collects the project-facing documentation for the codebase and its architecture.

## Entry Points

- [Vulkan Quickstart](vulkan-quickstart.md) gives a senior-level overview of the rendering stack, resource flow, and frame lifecycle.
- [Shader Guide](shaders.md) explains the GLSL sources and how they map to the renderer.

## Scope

The repository is intentionally compact, so the docs focus on the parts that matter when you want to extend the code rather than on an exhaustive tutorial. The current overlay is custom, but the frame lifecycle, descriptor flow, and per-frame resource separation are the same concepts you would apply when integrating Dear ImGui.
