# SDL2 Vulkan Demo in D

A minimal but clean Vulkan-based 3D demo written in D. The application opens a resizable SDL window, creates a Vulkan device and swapchain, renders a small animated 3D scene, and overlays a native-resolution 2D interface above it.

The project is intentionally small and direct:

- DUB is used as the build system.
- SDL is used for the window, event loop, and Vulkan surface integration.
- Vulkan handles all rendering.
- The math layer is hand-written and kept minimal.
- Shaders are written as GLSL sources, pre-compiled to SPIR-V during the build, and loaded from `build/shaders/` at runtime.

## What it shows

- A resizable window with a Vulkan swapchain.
- A simple animated indexed mesh.
- Per-frame uniform updates for model, view, and projection matrices.
- A native-resolution overlay with translucent panels and bitmap text.
- Basic depth buffering and explicit GPU resource cleanup.

## Repository Layout

- [source/main.d](source/main.d) is the executable entry point.
- [source/app.d](source/app.d) handles bootstrap and shutdown.
- [source/window.d](source/window.d) wraps SDL window ownership and Vulkan surface creation.
- [source/math/matrix.d](source/math/matrix.d) contains the small matrix/vector helper layer.
- [source/vulkan/](source/vulkan) contains the Vulkan instance, device, swapchain, pipeline, renderer, overlay, and mesh-generation code.
- [shaders/](shaders) contains the GLSL sources used by the pipeline.
- [scripts/](scripts) contains small D helpers for the Git-describe version string and the release timetag.
- [build/](build) contains generated build data such as `build/git-describe.txt`, compiled shaders in `build/shaders/`, and the application binary in `build/bin/`.

## Requirements

- A D compiler supported by DUB, such as `dmd`.
- Vulkan runtime and loader support on the target system.
- SDL development libraries available to the dynamic binding used by the project.
- `glslangValidator` or another GLSL-to-SPIR-V compiler for generating the shader binaries.

## Build

Build the application with DUB:

```bash
dub build
```

The current workspace compiles the application successfully with `dub build`.
The build generates `build/git-describe.txt` and compiles the shaders into `build/shaders/` first, then writes the executable to `build/bin/`.

## Shader Compilation

The renderer loads SPIR-V shader binaries from `build/shaders/main.vert.spv` and `build/shaders/main.frag.spv`. These files are generated automatically by the pre-build helper, but you can also run the helper directly if needed:

```bash
rdmd scripts/compile_shaders.d
```

If you prefer a different GLSL compiler, keep the output paths aligned with the renderer configuration and still write to `build/shaders/`.

The executable expects those paths to exist relative to the repository root. Run the binary from the project directory, not from inside `build/bin/`, unless you adjust the paths in the renderer.

## Run

After building the binary and compiling the shaders, run the executable from the repository root:

```bash
./build/bin/sdl2-vulcan-client
```

On startup the window should appear, the scene should animate, and the title bar will show FPS, camera yaw and pitch, the active shape, and the current render mode. If the shader files are missing, the program exits immediately with a file-not-found error.

## Versioning

The application prints the current Git describe string at startup and includes it in the window title. The value is read from `build/git-describe.txt`, which is generated from `git describe --tag --always --long` before the build. A build at `v26.19.0000-2-gbfd646b` will therefore report that exact version string.

For release tagging, use the helper scripts in [scripts/](scripts): [scripts/git_describe_version.d](scripts/git_describe_version.d) writes `build/git-describe.txt`, [scripts/compile_shaders.d](scripts/compile_shaders.d) compiles the GLSL shaders into `build/shaders/`, and [scripts/release_timetag.d](scripts/release_timetag.d) derives the release timetag from `va_toolbox.timetags.getTimeTagString()`.

## Controls

- `F` selects flat-color rendering.
- `T` selects the lit and textured render mode.
- `W` selects wireframe rendering.
- `H` selects hidden-line rendering.
- Arrow keys rotate the camera.
- `+` and `-` switch the active Platonic solid, including keypad variants.
- `Esc` closes the application.

## Overlay

The overlay is drawn in screen space at the native window resolution, not as a scaled texture. That keeps the text crisp and makes the panels behave like a simple in-game desktop GUI.

## Commit Workflow

Keep commits small and single-purpose. Stage only the files that belong to the change, write a technical English subject, and add a short body when the commit needs context.

For release commits, move the new note into `CHANGELOG.md` under `## Release <timetag>`, leave `## Unreleased` at the top, generate the timetag with [scripts/release_timetag.d](scripts/release_timetag.d), and tag the commit with a leading `v`.

## SDL Findings

The project surfaced a few SDL-in-D gotchas that are worth keeping in mind:

- `bindbc-sdl` 2.3.5 exposes SDL3-style names in some places, so check the installed binding instead of relying on older SDL2 examples.
- Keyboard shortcuts should account for both the main keyboard and the keypad; plus/minus live under `equals` / `minus` and `kpPlus` / `kpMinus` here.
- Use the `repeat` flag on `SDL_KeyboardEvent` for one-shot actions like object switching, otherwise a held key will trigger multiple times.
- SDL window coordinates start in the upper-left corner, so HUD or overlay code should only flip the Y axis once when converting to NDC.
- Keep SDL/Vulkan ownership explicit and deterministic: create, map, unmap, destroy, and free buffers in balanced pairs.
- When writing overlay or HUD text in D, keep the glyph set explicit and add the missing characters early, otherwise simple labels can render incompletely.

## Notes

- The code is structured to keep resource ownership explicit and cleanup deterministic.
- Validation and debug helpers are kept lightweight so the control flow stays easy to follow.
- The implementation is focused on being a clear starting point for a modern DLang + SDL + Vulkan application, not on feature breadth.
