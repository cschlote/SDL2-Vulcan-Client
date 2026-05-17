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

## UI Sidebar

The UI Sidebar is the persistent left-edge launcher for demo windows. It replaces the old Demo Control window and is currently implemented as a chrome-less `UiWindow` whose content root fills the usable window area. Compact mode shows a vertical stack of roughly 32 x 32 icon actions. Expanded mode widens the bar and shows text labels beside the fixed icon slots.

The sidebar actions use `UiSidebarAction`. This keeps a fixed icon slot on the left with 26 x 26 image content, places expanded text in a separate label region, keeps compact captions empty so old mnemonic placeholder letters are not shown beside real icons, animates sidebar expand/collapse through the window bounds-transition path, can show a slim active marker for open singleton windows, and shows collapsed-label tooltips after a hover delay through the generic screen tooltip hook and a small frameless input-transparent tooltip window above/right of the pointer.

Current behavior:

- anchors to the left edge of the SDL window
- toggles singleton windows such as Help Desk, Status, and Settings
- spawns repeatable windows such as Widget Demo, UiWindow Demo, Input Demo, Selection Demo, and Audio Demo when that action policy is useful
- toggles between compact and expanded label modes
- animates expand and collapse through the window bounds-transition path
- uses a vertically growable spacer to separate demo-window actions from bottom-aligned system actions
- exposes bottom system actions for Help, Status, Settings, Close All, and Exit
- hides singleton windows and removes repeatable demo-window instances through the Close All action
- shows active markers for visible singleton target windows
- shows delayed tooltips for collapsed icon-only actions
- keeps an opened tooltip visible while the pointer stays inside the same tooltip source region
- keeps the number of visible sidebar actions intentionally small for the current minimum SDL window size
- reserves the upper launcher group for at most eight direct actions at the current minimum SDL window height
- stays chrome-less: no header, no title, no close button, normally no resize ring

Useful regression checks:

- content root really fills the chrome-less window
- icon slots stay stable at compact width
- compact and expanded action buttons fill the available sidebar width
- the growable spacer keeps Help, Status, Settings, Close All, and Exit aligned to the bottom edge after viewport resizing
- Close All hides the singleton Help Desk, Status, and Settings windows and destroys repeatable demo windows without relying on window titles
- persistent window lookup should use generated window ids, not titles; optional application tags are secondary integration data
- expanding the sidebar updates the reserved left edge for demo windows
- viewport resizing keeps the bar attached to the left edge
- shrinking to the minimum SDL window height must shrink the growable spacer instead of clipping bottom actions
- modals and popups layer above the sidebar when needed

Planned extensions:

- decide whether dragging ordinary windows into the reserved sidebar strip should be blocked immediately or only corrected by relayout after sidebar expand/shrink
- scroll the upper launcher action group with the mouse wheel once the number of demo entries exceeds the available height
- show fade-out indicators at the top or bottom of the scrollable action group when more entries exist offscreen
- texture-backed icons with generated fallback cells; the current low-resolution PPM files are placeholders until a coherent high-resolution PNG icon set and package image loader exist
- generalize `UiSidebarAction` and ordinary button behavior into one configurable icon-capable action widget instead of adding another narrow button class

## Help Desk Window

The Help Desk window is currently a compact reference panel. It exercises `UiWindow`, `UiVBox`, `UiLabel`, `UiSpacer`, text measurement, and live label updates. It also documents the debug bounds overlay color map at runtime. Later it should become the built-in help system with searchable documentation and an optional AI-agent interface for real questions about the demo and engine.

Current behavior:

- lists keyboard and mouse controls
- displays the number of spawned demo windows
- documents debug bounds colors for `UiWindow`, `UiContentBox`, `UiFrameBox`, `UiVBox`, `UiHBox`, `UiGrid`, `UiSpacer`, and generic controls
- hides itself when closed instead of being destroyed

Useful regression checks:

- labels remain readable after font or atlas changes
- longer help text does not overlap the window chrome
- the window can be dragged, resized, stacked, hidden, and shown again
- live counters update without rebuilding the whole window

Planned extensions:

- add search over built-in help topics and documentation snippets
- add an AI-agent style question interface after the help data model and safety boundaries are clear
- add a scrolling log region after a text-area or text-block viewport exists
- use `UiScrollArea` for long help and log content once renderer clipping exists
- add filter controls for input, UI, renderer, and audio messages
- add a copy/export command after clipboard support exists

## Status Window

The Status window is a live read-only inspector. It exercises `UiWindow`, `UiVBox`, `UiHBox`, `UiLabel`, preferred-size measurement, per-frame text updates, viewport-edge pinning, backdrop layering, and a chrome-less nearly transparent backfill presentation.

Current behavior:

- displays build/version text
- displays current FPS
- displays current scene shape
- displays current render mode
- displays 3D object yaw and pitch angles
- displays viewport size
- starts visible so the demo has immediate runtime feedback after launch
- pins to the top-right SDL viewport edge with configurable top/right margins
- renders without header, border, or resize chrome and uses a very weak backfill so the status widgets stay readable without becoming a normal opaque panel
- is marked as a backdrop window so regular demo and dialog windows are drawn and routed above it
- auto-sizes to the current key/value rows instead of reserving a fixed dialog-sized rectangle
- re-measures after live text changes so longer build, scene, or render-mode strings grow the overlay before pinning is applied
- uses muted captions and brighter value colors so the compact overlay remains scannable

Useful regression checks:

- per-frame label updates do not allocate window objects repeatedly
- viewport changes keep the window attached to the top-right edge and clamped
- changing render mode or scene shape updates the status text immediately
- keyboard or mouse rotation updates the yaw/pitch text without moving the window
- numeric text remains aligned enough to scan during rendering tests
- longer build/version strings grow the window only as far as needed

Planned extensions:

- add optional frame-time and draw-count lines
- wire compact mode into real window/theme behavior
- add renderer and UI diagnostics once a small metrics model exists

## Settings Window

The Settings window is the current dialog-style form. It exercises `UiWindow`, `UiVBox`, `UiHBox`, `UiContentBox`, `UiLabel`, `UiTabBar`, `UiDropdown`, `UiListBox`, `UiTextField`, `UiToggle`, `UiSlider`, `UiButton`, keyboard focus, text input, callbacks, popup-backed selection, grouped pages, and a fixed action row.

Current behavior:

- edits display window mode
- edits window width and height with focused text fields
- toggles VSync
- switches between Display, UI, and Audio pages with a visual tab strip
- uses a `UiTabBar` that already supports overflow scrolling for later additional pages
- adjusts UI scale with a slider
- selects a theme placeholder
- toggles compact-window placeholder behavior
- adjusts persisted master, music, and effects volume settings
- applies settings to the running application
- saves settings only through an explicit Save action

Useful regression checks:

- `UiTextField` keeps focus and caret behavior while global renderer shortcuts stay blocked
- slider dragging keeps pointer capture until button-up
- tab switching changes only the active settings page
- overflowing tab strips can scroll with the mouse wheel or previous/next button regions and keep the selected tab visible
- dropdown popups open, stay above normal windows, and close through the screen popup policy
- focused dropdowns open through Enter
- the action row stays attached below the growable settings body
- Apply and Save remain separate persistence concepts

Planned extensions:

- add Controls and Gameplay pages once those settings become editable
- place oversized page content into `UiScrollArea` instead of forcing the window to grow
- extract repeated popup wiring into a widget-level popup facade
- add UI sound volume once the settings model exposes the existing UI audio bus separately
- add validation feedback for invalid numeric fields

## Widget Demo Window

The Widget Demo window is the first control-gallery window. It exercises `UiWindow`, `UiVBox`, `UiHBox`, `UiSpacer`, `UiSeparator`, `UiContentBox`, `UiFrameBox`, `UiButton`, `UiImage`, `UiToggle`, `UiSlider`, `UiProgressBar`, `UiDropdown`, visible `UiListBox` selection, `UiListBox` through dropdown popups, visible `UiTabBar` selection, `UiTextField`, custom demo widgets derived from `UiWidget`, preferred-size measurement, nested layout, resize behavior, debug bounds, and custom cursor registration.

Current behavior:

- spawns as independent windows with serial titles
- contains a layout and box section with nested probe boxes and a padded content-box example
- contains a retained-controls section with buttons, toggle, slider, dropdown, list, tab, and text field examples
- contains placeholder image/icon examples with asset ids and an icon-plus-label button
- groups related control rows with non-interactive separators
- updates a progress bar from the Amount slider
- updates a summary label from the list selection
- updates a summary label from the tab selection
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

- replace the rough low-resolution placeholder image assets with a coherent higher-resolution icon/image set
- move richer image browsing and animated-image examples into the planned Media Demo
- add future controls to the gallery
- wrap the gallery in `UiScrollArea` after renderer clipping exists
- add popup examples as those widgets land
- add interaction examples where one control changes another widget's value or visibility
- add disabled, focused, hover, pressed, and validation states for each control family

## UiWindow Demo Window

The UiWindow Demo window isolates top-level window behavior. It exercises `UiWindow` behavior flags, passive chrome visibility flags, optional window backfill, viewport-edge pinning, `UiDropdown`, `UiToggle`, `UiButton`, `UiLabel`, callbacks, close controls, resize rings, header dragging, border/content insets, and middle-click stacking.

Current behavior:

- toggles resize ring availability
- toggles the close button
- toggles header dragging
- toggles middle-click front/back stacking
- toggles header, title, and border visibility
- toggles body/header backfill rendering
- toggles viewport-edge pinning on each edge
- offers presets for default windows, transparent overlays, docked status-like windows, tool palettes, and dialogs
- resets all demo settings to defaults from a button
- updates a summary label from toggle callbacks
- spawns as independent windows and removes itself when closed

Useful regression checks:

- disabling header drag does not disable middle-click stacking
- disabling close hides or blocks only close behavior, not window visibility management elsewhere
- disabling the resize grips removes resize cursor regions and resize gestures
- disabling the header moves content to the top chrome inset, while disabling the border lets content fill the full window area
- disabling backfill leaves child widgets visible and interactive
- pinning follows SDL viewport resize without making API move/resize unavailable
- presets are ordinary control changes and leave the user free to continue editing individual toggles
- chrome controls receive pointer buttons before generic window stacking fallback
- content remains inset away from resize grips when sizeability changes

Planned extensions:

- add a modal-window example now that modal routing exists
- add default and cancel button examples for dialog chrome
- add controls to replay or compare animated open and close transitions

## Input Demo Window

The Input Demo exercises input ownership and keyboard navigation with ordinary retained controls. It makes Tab order, text input, activation keys, dropdown focus, and value callbacks visible in one small form.

Current behavior:

- focus traversal across text fields, toggles, sliders, buttons, and dropdowns
- keyboard activation for buttons and toggles
- live summary updates from text, toggle, slider, dropdown, and button callbacks
- repeatable window instances from the sidebar

Planned extensions:

- pointer capture visualization for dragging controls
- disabled and blocked cursor states
- visible modal focus containment examples now that modal routing exists

Primary classes to exercise:

- `UiScreen`
- `UiWindow`
- `UiWidget`
- `UiTextField`
- `UiButton`
- `UiToggle`
- `UiSlider`
- `UiDropdown`

## Selection Demo Window

The Selection Demo exercises popup and selection primitives in one repeatable window. It makes dropdown-backed popups, popup placement, outside-click dismissal, list selection, keyboard movement, and selection callbacks visible without mixing those checks into the Settings dialog.

Current behavior:

- opens a dropdown through the shared transient popup path
- offers an Edge popup button that requests popup placement near the window edge
- shows a visible `UiListBox` with highlighted active row
- updates a summary label from dropdown and list selections
- supports keyboard selection movement through focused dropdown popups and the visible list
- can be spawned repeatedly from the sidebar

Primary classes to exercise:

- `UiScreen` transient popup window policy
- `UiDropdown`
- `UiListBox`
- `UiLabel`
- `UiButton`

Planned extensions:

- add context-menu style popup examples after a reusable menu widget exists
- add tooltip coverage after `UiTooltip` exists
- replace the screen-level popup callback with a widget-level `UiPopupRoot` facade once multiple popup widget families share behavior

## Planned Presets / Shortcuts Window

The Presets / Shortcuts window should expose reusable commands once the demo has a small action metadata model. It should not duplicate the sidebar launcher. Its role is to group command presets, saved layouts, render profiles, and shortcut discovery in one normal tool window.

Target use cases:

- restore common demo window layouts
- switch render profiles or scene presets
- show editable or discoverable keyboard shortcuts
- expose command groups that can later feed menus, toolbars, and shortcut binding

Primary classes to exercise:

- `UiWindow`
- `UiTabBar` or future grouped command selector
- `UiListBox`
- `UiButton`
- future command/action metadata

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

## Audio Demo Window

The Audio Demo exercises the current audio service from ordinary retained UI controls. It connects buttons to semantic audio events and lets the renderer map those events to the runtime audio buses instead of calling backend playback functions from the demo window.

Current behavior:

- button click sound event
- one-shot preview buttons for UI, master, music, and effects bus routing
- repeatable window instances from the sidebar
- no direct dependency on SDL audio backend code

Planned extensions:

- one-shot effect preview with real assets
- master, music, effects, and UI bus volume sliders
- music play, stop, loop, fade, and crossfade
- settings preview that does not implicitly save configuration

Primary classes to exercise:

- current audio service
- `AudioEvent`
- `UiButton`
- `UiSlider`
- `UiToggle`
- `UiDropdown`
