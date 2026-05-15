# Rendering Architecture

This project renders a compact scene plus a native-resolution retained UI. The current executable is a learning demo, but the architecture is being shaped as a reusable game-engine foundation in D.

## Visual Stack

The intended frame has three conceptual layers:

1. A far background layer for skybox, star field, or other world backdrop.
2. A 3D scene layer for game objects.
3. A foreground UI layer for retained windows and widgets.

```mermaid
flowchart TB
    A[Background layer] --> B[3D scene layer]
    B --> C[Foreground retained UI]
    C --> D[Presented swapchain image]
```

The current code has a simple clear background, selectable placeholder meshes, and a custom UI overlay. The background layer is still mostly conceptual, but the renderer should keep enough separation for it to become a real pass later.

## 3D Scene Layer

The scene currently renders selectable Platonic solids from [source/vulkan/models/polyhedra.d](../source/vulkan/models/polyhedra.d). These meshes are placeholders for future authored models or game objects.

They are useful because they exercise the important engine paths:

- indexed geometry
- normals
- texture coordinates
- filled, wireframe, and hidden-line render modes
- depth buffering
- per-frame transform updates

[source/vulkan/engine/renderer.d](../source/vulkan/engine/renderer.d) transforms the mesh into the current view, uploads vertex/index data, updates uniforms, and records the draw commands.

## UI Layer

The foreground UI is a retained widget system rendered in native window pixels. It is not a screenshot texture or an immediate-mode debug overlay. Widgets generate panel and text geometry, and the renderer uploads that geometry into per-frame overlay buffers.

The ownership split is:

- `source/vulkan/ui/` contains reusable UI engine classes such as `UiWidget`, `UiWindow`, `UiScreen`, layout containers, labels, buttons, and render helpers.
- [source/demo/demo_ui.d](../source/demo/demo_ui.d) contains the current demo-specific screen construction.
- [source/vulkan/engine/renderer.d](../source/vulkan/engine/renderer.d) consumes the generated overlay geometry and draw ranges.

The renderer should know only generic UI render output names. `UiOverlayGeometry` and `UiWindowDrawRange` are the current renderer-facing names. Overlay geometry now comes from the retained `DemoUiScreen` window stack rather than from the old stateless HUD builder path.

## Frame Order

A frame should follow a stable order:

1. Process input and update runtime state.
2. Update camera, scene, and UI state.
3. Build or update scene geometry.
4. Build UI overlay geometry.
5. Upload scene and UI data into current frame resources.
6. Record command buffers.
7. Submit and present.

That order keeps the data flow one-directional. Runtime state produces geometry; geometry becomes GPU-visible buffers; command buffers describe the frame.

## Engine Boundary

The long-term goal is to extract the reusable engine pieces into an Engine-only D module. The demo exists to keep those pieces exercised while the shape settles.

Reusable engine candidates:

- `source/vulkan/ui/`: retained UI widgets, layout containers, controls, `UiScreen`, and `UiWindow`
- `source/vulkan/font/`: font atlas and text geometry support
- `source/vulkan/engine/instance.d`, `device.d`, `swapchain.d`, and `pipeline.d`: Vulkan setup helpers after API boundaries are tightened
- renderer-facing UI draw data once it moves out of the demo module
- mesh and asset-facing abstractions after placeholder geometry is replaced

Demo-only candidates:

- `source/demo/`: bootstrap policy, demo settings, demo UI construction, and application-level persistence decisions
- `source/vulkan/models/polyhedra.d`: current Platonic-solid placeholder scene selection
- current demo window labels, sample profiles, render-mode shortcuts, and learning-demo workflows
- renderer code that directly knows about demo shape names, demo settings, or demo-specific callbacks

## Decision Points

The next architecture decisions are:

- decide how far renderer ownership should be split before publishing a first package
- decide which settings belong to the engine and which belong only to the demo application
- decide whether `UiOverlayGeometry` and `UiWindowDrawRange` should move into `source/vulkan/ui/`
- decide whether the current `VulkanRenderer` becomes an engine renderer plus a smaller demo scene controller

## Related Files

- [source/vulkan/engine/renderer.d](../source/vulkan/engine/renderer.d)
- [source/vulkan/engine/pipeline.d](../source/vulkan/engine/pipeline.d)
- [source/vulkan/models/polyhedra.d](../source/vulkan/models/polyhedra.d)
- [source/vulkan/ui/ui_screen.d](../source/vulkan/ui/ui_screen.d)
- [source/demo/demo_ui.d](../source/demo/demo_ui.d)
- [docs/vulkan-quickstart.md](vulkan-quickstart.md)
- [docs/ui-architecture.md](ui-architecture.md)
