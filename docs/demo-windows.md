# Demo Windows

This document describes the demo application's UI windows. Each window should exercise reusable UI classes through realistic use cases, not only through isolated widget tests. When a widget class changes, the matching demo window should make the visual and interaction regression visible during normal development runs.

The implementation lives in [source/demo/demo_ui.d](../source/demo/demo_ui.d). Reusable behavior belongs in [source/vulkan/ui/](../source/vulkan/ui/); demo windows should only compose widgets, wire callbacks, and expose example workflows.

## Maintenance Rules

- Every visible demo window needs a section in this document.
- Every new reusable UI class should appear in at least one demo window through a normal use case.
- Demo windows may be changed when a better interaction example exists.
- Layout should stay font-sensitive and avoid fixed rectangles except for bootstrap defaults and intentionally fixed sample artwork.
- The `D` debug overlay should remain useful for every window by showing widget nesting, padding, content roots, and resize behavior.
- Demo-specific labels, sample values, and callbacks should stay out of reusable `vulkan.ui` modules.

## Demo Control Window

The Demo Control window is the small always-visible launcher for the rest of the UI. It currently exercises `UiWindow`, `UiVBox`, `UiButton`, `UiSpacer`, click callbacks, close handling, and window visibility toggling.

Current behavior:

- toggles the Help Desk window
- toggles the Status window
- opens the Settings window
- spawns independent Widget Demo windows
- spawns independent Chrome Demo windows
- requests application shutdown when the launcher itself is closed

Useful regression checks:

- button labels still determine useful minimum widths
- button hover and pointer cursors remain consistent
- repeated show/hide actions do not duplicate singleton windows
- close behavior is distinct from hide behavior for application-owned windows

Planned extensions:

- add launch buttons for the future Input Demo, Selection Demo, Media Demo, Animation Demo, and Audio Demo windows
- group launcher actions once tabs or grouped panels exist
- expose reset-layout and preset-layout actions after a presets window exists
- keep launcher actions mirrored in the left-edge UI sidebar while both launch surfaces exist

## UI Sidebar

The UI Sidebar is a persistent left-edge launcher for demo windows. It is currently implemented as a chrome-less `UiWindow` whose content root fills the usable window area. Compact mode shows a vertical stack of roughly 32 x 32 text-placeholder actions. Expanded mode widens the bar and shows text labels beside the short action markers.

The sidebar actions currently reuse `UiButton`, whose internal content row centers the label with flexible spacers on both sides. This keeps the bootstrap implementation small, but it is only a placeholder for the final launcher-row design. A later `UiIconButton` or `UiSidebarAction` should keep a fixed icon slot on the left and place expanded text in a separate label region.

Current behavior:

- anchors to the left edge of the SDL window
- shows or raises singleton windows such as Help Desk, Status, and Settings
- spawns repeatable windows such as Widget Demo and Chrome Demo when that action policy is useful
- toggles between compact and expanded label modes
- uses a vertically growable spacer to separate demo-window actions from bottom-aligned system actions
- exposes bottom system actions for Help, Settings, and Exit
- keeps the number of visible sidebar actions intentionally small for the current minimum SDL window size
- stays chrome-less: no header, no title, no close button, normally no resize ring

Useful regression checks:

- content root really fills the chrome-less window
- icon slots stay stable at compact width
- compact and expanded action buttons fill the available sidebar width
- the growable spacer keeps Help, Settings, and Exit aligned to the bottom edge after viewport resizing
- expanding the sidebar updates the reserved left edge for demo windows
- viewport resizing keeps the bar attached to the left edge
- shrinking to the minimum SDL window height must shrink the growable spacer instead of clipping bottom actions
- modals and popups layer above the sidebar when needed

Planned extensions:

- scroll the upper launcher action group with the mouse wheel once the number of demo entries exceeds the available height
- show fade-out indicators at the top or bottom of the scrollable action group when more entries exist offscreen
- active or visible-state markers for target windows
- tooltips for collapsed icon-only actions
- texture-backed icons or placeholder icon widgets
- `UiIconButton` or equivalent icon-plus-label action rows with fixed icon slot and separate label region
- optional animation support for expand/collapse

## Help Desk Window

The Help Desk window is currently a compact reference panel. It exercises `UiWindow`, `UiVBox`, `UiLabel`, `UiSpacer`, text measurement, and live label updates. It also documents the debug bounds overlay color map at runtime. Later it should become the built-in help system with searchable documentation and an optional AI-agent interface for real questions about the demo and engine.

Current behavior:

- lists keyboard and mouse controls
- displays the number of spawned demo windows
- documents debug bounds colors for `UiWindow`, `UiSurfaceBox`, `UiVBox`, `UiHBox`, `UiGrid`, `UiSpacer`, and generic controls
- hides itself when closed instead of being destroyed

Useful regression checks:

- labels remain readable after font or atlas changes
- longer help text does not overlap the window chrome
- the window can be dragged, resized, stacked, hidden, and shown again
- live counters update without rebuilding the whole window

Planned extensions:

- add search over built-in help topics and documentation snippets
- add an AI-agent style question interface after the help data model and safety boundaries are clear
- add a scrolling log region after list or text-area widgets exist
- use `UiScrollArea` once long text and log content exceed the visible window body
- add filter controls for input, UI, renderer, and audio messages
- add a copy/export command after clipboard support exists

## Status Window

The Status window is a live read-only inspector. It exercises `UiWindow`, `UiVBox`, `UiLabel`, per-frame text updates, and viewport-aware anchoring.

Current behavior:

- displays build/version text
- displays current FPS
- displays current scene shape
- displays current render mode
- displays viewport size
- anchors near the top-right viewport corner

Useful regression checks:

- per-frame label updates do not allocate window objects repeatedly
- viewport changes keep the window visible and clamped
- changing render mode or scene shape updates the status text immediately
- numeric text remains aligned enough to scan during rendering tests

Planned extensions:

- add optional frame-time and draw-count lines
- add compact mode after settings tabs exist
- add renderer and UI diagnostics once a small metrics model exists

## Settings Window

The Settings window is the current dialog-style form. It exercises `UiWindow`, `UiVBox`, `UiHBox`, `UiLabel`, `UiDropdown`, `UiTextField`, `UiToggle`, `UiSlider`, `UiButton`, keyboard focus, text input, callbacks, and a fixed action row.

Current behavior:

- edits display window mode
- edits window width and height with focused text fields
- toggles VSync
- adjusts UI scale with a slider
- selects a theme placeholder
- toggles compact-window placeholder behavior
- applies settings to the running application
- saves settings only through an explicit Save action

Useful regression checks:

- `UiTextField` keeps focus and caret behavior while global renderer shortcuts stay blocked
- slider dragging keeps pointer capture until button-up
- dropdown cycling remains deterministic until popup menus exist
- the action row stays attached below the growable settings body
- Apply and Save remain separate persistence concepts

Planned extensions:

- split content into Display, Controls, Gameplay, Audio, and UI pages when tabs exist
- place oversized page content into `UiScrollArea` instead of forcing the window to grow
- use popup-backed dropdown lists instead of click-to-cycle dropdowns
- add audio bus volume sliders for master, music, effects, and UI sound
- add validation feedback for invalid numeric fields

## Widget Demo Window

The Widget Demo window is currently a layout probe and should become the main control gallery. It exercises `UiWindow`, `UiVBox`, `UiHBox`, `UiSpacer`, custom demo widgets derived from `UiWidget`, preferred-size measurement, nested layout, resize behavior, debug bounds, and custom cursor registration.

Current behavior:

- spawns as independent windows with serial titles
- contains nested rows and columns of fixed-size probe boxes
- uses varied fill and border colors to make layout movement visible
- applies a custom crosshair cursor over probe boxes
- can be resized and stacked like normal windows
- removes itself from the screen owner when closed

Useful regression checks:

- growing and then shrinking the window does not corrupt intrinsic preferred sizes
- nested `UiHBox` and `UiVBox` containers preserve spacing
- debug bounds show expected row, column, spacer, and widget outlines
- custom cursor fallback and override behavior is visible at runtime
- multiple instances do not share mutable window state accidentally

Planned extensions:

- turn the probe area into a gallery with buttons, toggles, sliders, text fields, dropdowns, image widgets, and future controls
- wrap the gallery in `UiScrollArea` when the number of examples exceeds the visible window body
- add list, progress, tab, and popup examples as those widgets land
- add interaction examples where one control changes another widget's value or visibility
- add disabled, focused, hover, pressed, and validation states for each control family

## Chrome Demo Window

The Chrome Demo window isolates top-level window behavior. It exercises `UiWindow` behavior flags, passive chrome visibility flags, `UiToggle`, `UiLabel`, callbacks, close controls, resize rings, header dragging, border/content insets, and middle-click stacking.

Current behavior:

- toggles resize ring availability
- toggles the close button
- toggles header dragging
- toggles middle-click front/back stacking
- toggles header, title, and border visibility
- updates a summary label from toggle callbacks
- spawns as independent windows and removes itself when closed

Useful regression checks:

- disabling header drag does not disable middle-click stacking
- disabling close hides or blocks only close behavior, not window visibility management elsewhere
- disabling the resize grips removes resize cursor regions and resize gestures
- disabling the header moves content to the top chrome inset, while disabling the border lets content fill the full window area
- chrome controls receive pointer buttons before generic window stacking fallback
- content remains inset away from resize grips when sizeability changes

Planned extensions:

- add a modal-window example once modal routing exists
- add default and cancel button examples for dialog chrome
- add animated open and close transitions when the animation scheduler exists

## Planned Input Demo Window

The Input Demo should exercise input ownership and keyboard navigation. It should become the first window that makes Tab order, Shift-Tab order, activation keys, focus containment, and blocked global shortcuts visible.

Target use cases:

- focus traversal across text fields, toggles, sliders, buttons, and dropdowns
- keyboard activation for buttons and toggles
- pointer capture visualization for dragging controls
- disabled and blocked cursor states
- optional modal focus containment after modal windows exist

Primary classes to exercise:

- `UiScreen`
- `UiWindow`
- `UiWidget`
- `UiTextField`
- `UiButton`
- `UiToggle`
- `UiSlider`
- `UiDropdown`

## Planned Selection Demo Window

The Selection Demo should exercise popup and selection primitives once they exist. It should make dropdowns, popup placement, outside-click dismissal, list selection, and selection callbacks visible in one place.

Target use cases:

- dropdown opening and closing
- popup placement near viewport edges
- selection list with highlighted active row
- outside-click dismissal
- keyboard selection movement
- selection changing a label, preview, or dependent control

Primary classes to exercise:

- future popup root
- future menu/list widgets
- `UiDropdown`
- `UiLabel`
- `UiButton`

## Planned Media Demo Window

The Media Demo should exercise visual asset widgets. It should cover static images first, then animated images and video-like content when those APIs exist.

Target use cases:

- static texture-backed `UiImage`
- icon buttons using real image assets
- animated `UiImage` frame playback
- paused, playing, and loading states
- resize behavior for aspect-ratio constrained media

Primary classes to exercise:

- `UiImage`
- future animated image widget
- future video or media widget
- `UiButton`
- `UiSlider`

## Planned Animation Demo Window

The Animation Demo should exercise the UI animation scheduler and transition model. It should make widget-local animation and window open/close animation visible without coupling those effects to application code.

Target use cases:

- hover or value-change animation on a widget
- progress animation
- animated panel expansion and collapse
- Apple-style window pop-in and close-out transitions
- animation interruption when a window is closed, reopened, or resized quickly

Primary classes to exercise:

- `UiScreen`
- `UiWindow`
- `UiWidget`
- future animation scheduler
- future transition descriptors

## Planned Audio Demo Window

The Audio Demo should exercise the audio service once implemented. It should connect ordinary UI controls to audio events instead of directly calling backend playback functions.

Target use cases:

- button click sound event
- one-shot effect preview
- master, music, effects, and UI bus volume sliders
- music play, stop, loop, fade, and crossfade
- settings preview that does not implicitly save configuration

Primary classes to exercise:

- future audio service
- future `AudioEvent`
- `UiButton`
- `UiSlider`
- `UiToggle`
- `UiDropdown`
