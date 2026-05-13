# SDL2 Vulkan Quickstart

This repository is a compact Vulkan codebase in D that is meant to be read, extended, and used as a senior-level quickstart for both Vulkan and Dear ImGui style frame integration. The current renderer uses a custom overlay, but the ownership model, per-frame resource split, and swapchain lifecycle are the same pieces you need when you swap in ImGui.

## Fast Orientation

- DUB drives the build.
- SDL owns the window, event loop, and Vulkan surface integration.
- Vulkan owns rendering, presentation, and synchronization.
- The shader path is explicit: GLSL in [shaders/](shaders), SPIR-V in `build/shaders/`.
- The docs folder now holds the short Vulkan overview, shader notes, and DDox or ADRDox skeletons.

## What To Read First

- [docs/vulkan-quickstart.md](docs/vulkan-quickstart.md) for the frame lifecycle and Vulkan object model.
- [docs/shaders.md](docs/shaders.md) for the GLSL stage contract.
- [docs/README.md](docs/README.md) for the documentation index.
- [source/vulkan/renderer.d](source/vulkan/renderer.d) for the real frame orchestration and resource ownership.

## Build and Run

```bash
dub build
./build/bin/sdl2-vulcan-client
```

The build runs the version helper and shader compiler before linking the executable. The binary expects `build/shaders/main.vert.spv` and `build/shaders/main.frag.spv` to exist relative to the repository root.

## Repository Map

- [source/main.d](source/main.d) is the executable entry point.
- [source/app.d](source/app.d) handles bootstrap and shutdown.
- [source/window.d](source/window.d) wraps SDL window ownership and Vulkan surface creation.
- [source/math/matrix.d](source/math/matrix.d) contains the compact matrix and vector helpers.
- [source/vulkan/](source/vulkan) contains the instance, device, swapchain, pipeline, renderer, overlay, font, and mesh code.
- [shaders/](shaders) contains the GLSL shader sources.
- [docs/](docs) contains the short-form technical documentation and skeletons for future DDox or ADRDox notes.

## Controls

- `F` selects flat-color rendering.
- `T` selects lit and textured rendering.
- `W` selects wireframe rendering.
- `H` selects hidden-line rendering.
- Arrow keys rotate the camera.
- `+` and `-` switch the active Platonic solid, including keypad variants.
- `Esc` closes the application.

## Documentation Notes

- The overlay is rendered in native window pixels, not as a scaled texture, so it stays crisp.
- The frame lifecycle is intentionally explicit so that a future Dear ImGui integration can reuse the same swapchain and per-frame resource structure.
- If you need deeper source documentation, start with the DDox skeleton in [docs/templates/ddox.md](docs/templates/ddox.md) and the ADRDox skeleton in [docs/templates/adrdox.md](docs/templates/adrdox.md).

## Release and Versioning

- [scripts/git_describe_version.d](scripts/git_describe_version.d) writes `build/git-describe.txt`.
- [scripts/compile_shaders.d](scripts/compile_shaders.d) compiles the GLSL sources into SPIR-V.
- [scripts/release_timetag.d](scripts/release_timetag.d) prints the release tag seed.

For release commits, keep `CHANGELOG.md` focused, generate the timetag with the helper script, and tag the commit with a leading `v`.
