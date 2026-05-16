# SDL2 Vulkan Engine Prototype

This repository is a compact D codebase for building a small game-engine spine with SDL2, Vulkan, and a custom retained UI. It is still useful as a Vulkan learning demo, but the project direction is broader: implement the important engine building blocks first, then split the reusable engine pieces into a separate D module that can be published and used by a game.

## Fast Orientation

- DUB drives the build.
- SDL owns the native window, event loop, and Vulkan surface integration.
- Vulkan owns rendering, presentation, synchronization, textures, buffers, and shaders.
- The UI is a custom retained widget system inspired by Qt-style ownership and Amiga Magic User Interface style font-sensitive layout.
- Demo-specific UI lives in `source/demo/`; reusable UI widgets live in `source/vulkan/ui/`.
- GLSL shader sources live in [shaders/](shaders); generated SPIR-V lives in `build/shaders/`.

## What To Read First

- [docs/vulkan-quickstart.md](docs/vulkan-quickstart.md) for the frame lifecycle and Vulkan object model.
- [docs/rendering-architecture.md](docs/rendering-architecture.md) for the renderer's layered frame composition.
- [docs/ui-architecture.md](docs/ui-architecture.md) for the retained UI engine direction.
- [docs/audio-architecture.md](docs/audio-architecture.md) for the planned audio event, mixer, and music architecture.
- [docs/demo-ui-plan.md](docs/demo-ui-plan.md) for the current migration and planning notes.
- [docs/shaders.md](docs/shaders.md) for the GLSL stage contract.
- [docs/README.md](docs/README.md) for the documentation index.

## Build and Run

```bash
dub build
./build/bin/sdl2-vulcan-client
```

The build runs the version helper and shader compiler before linking the executable. The binary expects `build/git-describe.txt`, `build/shaders/main.vert.spv`, and `build/shaders/main.frag.spv` to exist relative to the repository root.

## Repository Map

- [source/main.d](source/main.d) is the executable entry point.
- [source/demo/app.d](source/demo/app.d) handles bootstrap, settings load/save, and shutdown.
- [source/demo/demo_ui.d](source/demo/demo_ui.d) builds the current demo UI.
- [source/demo/demo_settings.d](source/demo/demo_settings.d) stores demo settings in a small INI format.
- [source/sdl2/window.d](source/sdl2/window.d) wraps SDL window ownership and Vulkan surface creation.
- [source/vulkan/engine/renderer.d](source/vulkan/engine/renderer.d) owns frame orchestration and Vulkan resources.
- [source/vulkan/ui/](source/vulkan/ui) contains the retained UI widget engine.
- [source/vulkan/models/polyhedra.d](source/vulkan/models/polyhedra.d) builds the placeholder scene meshes.
- [source/math/matrix.d](source/math/matrix.d) contains compact math helpers.
- [docs/](docs) contains architecture and planning notes.

## Controls

- `F` selects flat-color rendering.
- `T` selects lit and textured rendering.
- `W` selects wireframe rendering.
- `H` selects hidden-line rendering.
- `D` toggles color-coded UI widget bounds for layout debugging.
- Arrow keys rotate the camera.
- Hold `Shift` while rotating for faster camera movement.
- Mouse drag outside UI windows rotates the scene.
- Middle-click free UI window chrome to toggle that window between front and back.
- Mouse wheel outside UI windows changes the camera field of view.
- `+` and `-` switch the active Platonic solid, including keypad variants.
- `Esc` closes the application unless a focused UI control consumes it first.

## Settings Policy

Settings are loaded from `~/.config/sdl2-vulcan-demo/config`. Runtime changes stay local. Apply updates the running app state only; persistence to disk is reserved for an explicit Save operation.

## Release and Versioning

- [scripts/git_describe_version.d](scripts/git_describe_version.d) writes `build/git-describe.txt`.
- [scripts/compile_shaders.d](scripts/compile_shaders.d) compiles the GLSL sources into SPIR-V.
- [scripts/release_timetag.d](scripts/release_timetag.d) prints the release tag seed.

For release commits, keep `CHANGELOG.md` focused, generate the timetag with the helper script, and tag the commit with a leading `v`.

## License

The repository uses the CC-BY-NC-SA 4.0 license for source code, documentation, and related project material unless a file says otherwise. The project is intended as a learning demo and engine-building reference; commercial reuse requires separate permission.
