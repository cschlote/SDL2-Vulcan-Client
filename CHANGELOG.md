# CHANGELOGS

## Unreleased

- Improved the on-screen window interactions and added clearer debug logging for development.
- Started a box-based layout system for the on-screen windows.
- Clarified the UI surface direction so window backgrounds, borders, and spacing stay separate.

## Release 26.20.4916

- The release helper script now runs correctly through DUB, so the release workflow is easier to repeat.
- The app now starts on the dodecahedron, and the UI code is split into smaller modules so it is easier to follow and extend.

## Release 26.20.4126

- Improved the custom overlay documentation and clarified the retained UI layout.
- Set a sensible minimum size for the SDL window and kept HUD elements rendering together.

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