# SDL2 Vulkan Demo in D

A minimal but clean Vulkan-based 3D demo written in D. The application opens a resizable SDL window, creates a Vulkan device and swapchain, and renders a small animated 3D scene so it is immediately visible that the rendering path works.

The project is intentionally small and direct:

- DUB is used as the build system.
- SDL is used for the window, event loop, and Vulkan surface integration.
- Vulkan handles all rendering.
- The math layer is hand-written and kept minimal.
- Shaders are stored as GLSL sources and loaded as SPIR-V at runtime.

## What it shows

- A resizable window with a Vulkan swapchain.
- A simple animated indexed mesh.
- Per-frame uniform updates for model, view, and projection matrices.
- Basic depth buffering and explicit GPU resource cleanup.

## Repository Layout

- [source/main.d](source/main.d) is the executable entry point.
- [source/app.d](source/app.d) handles bootstrap and shutdown.
- [source/window.d](source/window.d) wraps SDL window ownership and Vulkan surface creation.
- [source/math/matrix.d](source/math/matrix.d) contains the small matrix/vector helper layer.
- [source/vulkan/](source/vulkan) contains the Vulkan instance, device, swapchain, pipeline, and renderer code.
- [shaders/](shaders) contains the GLSL sources used by the pipeline.
- [scripts/](scripts) contains small D helpers for the Git-describe version string and the release timetag.

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

## Shader Compilation

The renderer loads SPIR-V shader binaries from `shaders/main.vert.spv` and `shaders/main.frag.spv`. These files are not generated automatically by DUB, so compile the GLSL sources before running the application:

```bash
glslangValidator -V shaders/main.vert -o shaders/main.vert.spv
glslangValidator -V shaders/main.frag -o shaders/main.frag.spv
```

If you prefer a different GLSL compiler, keep the output paths aligned with the renderer configuration.

The executable expects those paths to exist relative to the repository root. Run the binary from the project directory, not from inside `bin/`, unless you adjust the paths in the renderer.

## Run

After building the binary and compiling the shaders, run the executable from the repository root:

```bash
./bin/sdl2-vulcan-client
```

On startup the window should appear, the scene should animate, and the title bar will show a simple FPS readout. If the shader files are missing, the program exits immediately with a file-not-found error.

## Versioning

The application prints the current Git describe string at startup and includes it in the window title. That value comes from `git describe --tag --always --long`, so a build at `v26.19.0000-2-gbfd646b` will report that exact version string.

For release tagging, use the helper scripts in [scripts/](scripts): [scripts/version.d](scripts/version.d) prints the Git-describe version in the shell, and [scripts/release_timetag.d](scripts/release_timetag.d) derives the release timetag from `va_toolbox.timetags.getTimeTagString()`.

## Notes

- The code is structured to keep resource ownership explicit and cleanup deterministic.
- Validation and debug helpers are kept lightweight so the control flow stays easy to follow.
- The implementation is focused on being a clear starting point for a modern DLang + SDL + Vulkan application, not on feature breadth.
