# CHANGELOGS

## Unreleased

- Added a Vulkan quickstart, a rendering-architecture guide, shader documentation, and DDox/ADRDox skeletons for future technical notes.
- Fixed HUD window layering so each window's panel, text, and hidden-line elements stay in the same render block.

## Release 26.19.8459

- Improved the on-screen interface with real font atlases, a configurable font path, and crisper text rendering.
- Added Shift-accelerated camera rotation and a higher-contrast checkerboard scene texture.

## Release 26.19.8409

- Added a native-resolution 2D overlay with translucent window panels and crisp bitmap text.
- Added lit textured and wireframe render modes with clearer on-screen controls and mode labels.
- Expanded DDoc coverage and refreshed the project README to match the current build and release workflow.

## Release 26.19.7021

- Stabilized the colored cube view with cursor-key driven rotation on two axes.
- Fixed the perspective depth ordering so nearer faces render in front of farther faces.
- Initial SDL/Vulkan demo scaffold with explicit resource cleanup, shader loading, and animated 3D rendering.