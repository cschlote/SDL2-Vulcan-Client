# CHANGELOGS

## Unreleased

- Wired demo audio settings into the runtime `AudioSystem` volume buses on startup, Apply, and Save.
- Added backend-neutral audio bus/event scaffolding with settings volume mapping.
- Added API-level UI window move and resize bounds transitions plus updated Help Desk shortcut text.
- Wired normal `UiScreen` show, hide, and toggle paths plus demo singleton windows through UI window transitions.
- Applied UI window transition alpha, scale, and offset to generated overlay vertices before upload.
- Added renderer-facing window presentation parameters for UI transition alpha, scale, and offset.
- Added logical `UiWindow` open and close transition states with progress ticking.
- Added the first UI animation scheduler hooks with `UiScreen.tickUi`, recursive `UiWidget.tick`, delta clamping, and renderer frame dispatch.
- Added blocked cursor feedback for background regions behind active modal windows.
- Added modal default and cancel button handling for Enter and Escape on active `UiWindow` dialogs.
- Added `UiScreen` modal window routing with background input blocking, modal stack priority, and modal focus containment.
- Added screen-level Tab and Shift-Tab focus traversal plus Enter/arrow keyboard handling for focused buttons, toggles, and sliders.
- Added focused keyboard handling for `UiTabBar` and `UiListBox`, including SDL up/down key mapping.
- Reduced the expanded demo sidebar width to match the current text-placeholder actions more closely.
- Added `UiTabBar` and split Settings into Display, UI, and Audio pages with persisted audio volume sliders.
- Added a reusable `UiListBox` text-row selection control and switched dropdown popups to use it instead of demo-local button rows.
- Fixed dropdown popup row selection so each option button selects its own option instead of the last option in the list.
- Reworked `UiDropdown` to request popup lists and wired the demo settings and widget-demo dropdowns to transient popup windows.
- Added `UiScreen` popup primitives for transient popup windows with anchor placement, viewport clamping, front-most stack handling, outside-click dismissal, and Escape dismissal.

## Release 26.20.8493

- Removed the obsolete Demo Control window; the sidebar now toggles singleton windows and spawns repeatable demo windows.
- Expanded the Widget Demo into an initial control gallery with content/frame boxes and current retained controls.
- Added an initial `UiScrollArea` with retained scroll offsets, content bounds, clamped wheel scrolling, and UI wheel-event routing.
- Split the old content/frame box role into `UiContentBox` for padded content roots and `UiFrameBox` for visible framed groups.
- Renamed the Controls / Log window to Help Desk and documented the later searchable help and AI-agent direction.
- Fixed growable `UiSpacer` measurement so an expanded sidebar spacer does not prevent later vertical shrink.
- Documented the current sidebar entry limit and the later scrollable launcher group with fade-out indicators.
- Added bottom-aligned Help, Settings, and Exit actions to the demo sidebar using a vertically growable spacer.
- Documented that the sidebar currently uses temporary `UiButton` rows and should later move to a dedicated icon/action row widget.
- Allowed `UiButton` to stretch horizontally when layout hints request growth, and documented size hints versus layout policy.
- Added an expanded-label mode to the left-edge demo sidebar.
- Added a chrome-less left-edge demo sidebar for opening existing demo windows.
- Added configurable `UiWindow` chrome visibility for header, title, and border.
- Clarified the planned split between simple content/frame boxes and a future scroll area widget.
- Added widget documentation and planning notes for a chrome-less left-edge UI sidebar.
- Added documentation for current and planned demo windows and the future retained UI animation model.
- Added a demo custom inspect cursor for Widget Demo probe boxes.
- Added optional bitmap cursor definitions and SDL custom cursor registration hooks.
- Added retained UI cursor intent and SDL system cursor updates for controls and window chrome.
- Moved generic retained UI overlay traversal into `UiScreen`.
- Moved renderer-facing retained UI geometry range types into the reusable `vulkan.ui` package.
- Corrected documentation and package metadata around the CC-BY-NC-SA 4.0 license, current UI controls, cursor planning, and planned audio architecture.
- Fixed middle-click window chrome stacking so retained UI windows can be brought to the front or sent to the back outside their content area.
- Improved `UiWindow` chrome with edge resize grips, smaller corner markers, larger title text, and content-root insets that avoid the resize ring.
- Refined `UiWindow` title and resize-ring layout and added a Chrome Demo window for toggling sizeable, closable, and dragable flags at runtime.
- Reduced the resize-ring opacity so the window chrome reads more subtly.
- Split middle-click window stacking from the dragable chrome flag and exposed the stackable flag in the Chrome Demo.
- Added generic retained UI keyboard focus routing, SDL text input forwarding, and editable `UiTextField` cursor/key handling.
- Updated the UI architecture and demo plan for focus ownership, text editing, and the next popup/menu work.

## Release 26.20.7022

- Updated the engine and UI planning documentation.
- Removed the legacy stateless HUD construction path from the retained demo UI.
- Refactored `DemoUiScreen` to use generic `UiScreen` window registration, iteration, hit testing, layout, and interaction helpers.
- Stopped automatic demo settings persistence on Apply and application shutdown; only a future explicit Save action should write the config file.
- Added generic retained toggle, slider, dropdown, and text field controls with unit coverage.
- Rebuilt the demo settings window around generic controls with separate Apply and explicit Save actions.
- Renamed the demo UI windows and actions around clearer app roles: demo control, status, controls/log, settings, and widget demo.
- Fixed retained UI rendering after several windows by keeping overlay geometry in a stable depth range and disabling depth tests for the overlay pipeline.
- Added a global `D` hotkey that overlays semi-transparent red bounds for every visible retained UI widget.
- Colored the UI debug bounds by widget/layout type so nested layout boxes are easier to distinguish.
- Fixed `UiWindow` content layout so direct body widgets fill the available content root instead of bypassing the root layout box.
- Fixed retained layout shrinking after a window was resized larger, and made the widget demo rows grow vertically.
- Fixed layout measurement so arranged widget sizes do not become new intrinsic sizes, and improved slider dragging.
- Anchored the settings Apply and Save buttons in a fixed bottom action row below the growable settings body.
- Added UiScreen window stacking and non-overlap placement helpers; middle-clicking a window header toggles that window between front and back.
- Added the UI debug bounds color legend to the Help Desk window.
- Removed stale layout-demo color literals, expanded DDoc for the retained controls and `UiScreen`, and refreshed the UI plan to match the current widget set.
- Updated architecture notes for the current reusable engine boundary after the UI cleanup.
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
