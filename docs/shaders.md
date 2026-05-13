# Shader Guide

The project uses two GLSL shaders that are compiled to SPIR-V during the build and loaded from `build/shaders/` at runtime.

## Vertex Shader

File: [shaders/main.vert](../shaders/main.vert)

This shader is intentionally small. It forwards the vertex attributes from the mesh into the fragment stage and writes clip-space position directly from the incoming position.

Inputs:

- location 0: position
- location 1: color
- location 2: normal
- location 3: UV coordinates

Outputs:

- location 0: interpolated color
- location 1: interpolated normal
- location 2: interpolated UV coordinates

## Fragment Shader

File: [shaders/main.frag](../shaders/main.frag)

This shader selects one of three rendering modes through the `SceneUniforms` block:

- mode 0 renders flat vertex color
- mode 1 applies diffuse and specular lighting on top of the sampled texture
- mode 2 multiplies the vertex color by the sampled texture without lighting

The fragment shader therefore covers both the main object pass and the overlay-style textured path used by the renderer.

## Build Path

The build pipeline compiles the GLSL sources to:

- `build/shaders/main.vert.spv`
- `build/shaders/main.frag.spv`

The renderer expects those files relative to the repository root.
