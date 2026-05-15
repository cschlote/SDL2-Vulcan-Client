# CHANGELOGS

## Unreleased

- Updated the engine and UI planning documentation.
- Removed the legacy stateless HUD construction path from the retained demo UI.
- Refactored `DemoUiScreen` to use generic `UiScreen` window registration, iteration, hit testing, layout, and interaction helpers.
- Stopped automatic demo settings persistence on Apply and application shutdown; only a future explicit Save action should write the config file.
- Improved font test coverage and documentation for release checks.

## Release 26.20.6619

- Improved the retained UI layout and clarified how screens own widgets.

## Release 26.20.5344

- Centered the close button in the window header.

## Release 26.20.5274

- Improved the on-screen window interactions and debug logging.
- Started a box-based layout system for the on-screen windows.
- Clarified how UI surfaces, borders, and spacing should be handled.

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
