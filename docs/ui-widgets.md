# UI Widgets

This document tracks existing and planned retained UI widgets. Each entry records the intended use case, required behavior, demo coverage, and implementation status. The goal is to keep widget work testable through demo windows and to make later refactoring safer.

Reusable implementations belong in [source/vulkan/ui/](../source/vulkan/ui/). Demo composition and sample workflows belong in [source/demo/demo_ui.d](../source/demo/demo_ui.d).

## Status Terms

- Implemented: a reusable widget or core behavior exists.
- Partial: useful behavior exists, but important planned behavior is missing.
- Planned: documented target only.

## Widget Principles

- Widgets own local geometry, layout hints, rendering, and local input behavior.
- Widgets report intent, such as cursor shape or callbacks, instead of owning platform resources.
- Layout should derive from text, content, and explicit hints rather than fixed screen rectangles.
- Demo windows should show widgets in normal workflows, including hover, focus, disabled, resized, and repeated-instance states.
- Future animation support should be considered when adding visual state, but animation policy should stay outside renderer code.

## Core Containers

### UiWidget

Status: Implemented.

`UiWidget` is the retained base class for rectangular UI objects. It stores local position, size, preferred layout hints, children, focusability, pointer routing, cursor intent, and rendering hooks. Focusable widgets draw a generic focus ring when they own keyboard focus, unless a later specialized control deliberately overrides that visual language.

Common use cases:

- base class for controls and layout containers
- nested child ownership
- local-coordinate input handling
- custom demo probes and future specialized widgets

Required behavior:

- stable local-to-parent geometry
- deterministic child traversal
- optional focus ownership with visible focus ring
- optional cursor preference through `cursorSelf`
- local rendering through `renderSelf`
- measuring and layout through `measureSelf` and layout hints
- separation between natural content size and arranged size

Demo coverage:

- Widget Demo uses custom `LayoutDemoProbeBox` widgets derived from `UiWidget`.
- Debug bounds overlay should reveal generic widget fallback outlines.

Planned work:

- add local animation tick hooks
- add explicit disabled state
- add accessibility or semantic metadata if the project grows in that direction

### UiScreen

Status: Implemented, still experimental.

`UiScreen` is the screen-level owner for windows, viewport state, layout dispatch, input routing, focus ownership, cursor resolution, and window stack order. It is not drawn as a widget, but it is part of the UI object model.

Common use cases:

- own the visible window list
- dispatch pointer and keyboard events
- resolve top-most hit targets
- block background routing while a modal window is active
- route modal Enter/Escape keys to a window's configured default or cancel button
- build renderer-facing overlay geometry
- clamp and place windows in the SDL viewport

Required behavior:

- preserve deterministic front-to-back and back-to-front window order
- keep focus routing separate from renderer shortcuts
- answer cursor intent for the visible top-most UI object
- keep demo-specific behavior out of reusable screen logic

Demo coverage:

- all current demo windows are owned by `DemoUiScreen`, which derives from `UiScreen`.
- Status and Help Desk windows expose live screen state indirectly.

Planned work:

- widget-level popup root ownership
- animation tick dispatch and transition cleanup
- optional dock/sidebar placement helpers

### UiWindow

Status: Implemented, with additional planned window roles.

`UiWindow` is the top-level retained UI container. It owns frame rendering, content root placement, close button behavior, dragging, resizing, stacking, and window-level hit testing.

For modal use cases, `UiWindow` can mark one body `UiButton` as the default action and one as the cancel action. `UiScreen` activates those buttons for Enter and Escape while the window is the active modal window. The callbacks remain ordinary button callbacks, so a cancel action may close the modal, and a default action may apply, validate, or keep the dialog open.

Common use cases:

- normal draggable tool windows
- dialogs with body content and action rows
- chrome demos and settings panels
- future chrome-less dock/sidebar windows
- future modal windows

Required behavior:

- content root stays clear of active chrome, close controls, and resize grips
- direct content widgets receive the useful body area
- chrome flags can independently control sizeability, closability, draggability, and stackability
- chrome visibility can independently control header, title, and border
- cursor regions match resize, move, action, and blocked states
- close/hide/destroy behavior remains distinguishable

Implemented chrome attributes:

- header visibility
- title visibility
- border visibility and thickness
- content padding per side

Planned chrome attributes:

- window role such as normal, tool, dialog, popup, dock, or sidebar
- optional transition preset for open and close animation

Demo coverage:

- all current UI windows are `UiWindow` instances.
- Chrome Demo toggles current behavior and visibility flags.
- planned Sidebar Demo should exercise chrome-less window mode.
- planned Animation Demo should exercise open and close transitions.

### UiSidebar

Status: Partial as demo composition; reusable class planned.

`UiSidebar` is the planned reusable left-edge UI bar inspired by application launchers such as EVE Online side panels or the Ubuntu GNOME dock. The current demo implements the first version as a chrome-less `UiWindow` whose content root fills the window. The content stacks compact text-placeholder actions vertically, can expand to show text labels, and can show, raise, or spawn demo windows.

The current sidebar actions intentionally reuse `UiButton` as a temporary compound widget. A `UiButton` centers its label by placing it inside an internal `UiHBox` with flexible spacer widgets on both sides. That is acceptable for the first text-placeholder sidebar, but it is not the target structure for a launcher row.

Common use cases:

- persistent left-edge launcher for demo windows
- compact icon-only navigation
- expandable icon-plus-text navigation
- quick show/hide for tool windows
- future pinned game/editor tools

Required behavior:

- anchor to the left edge of the SDL viewport
- default compact width around one 32 px icon plus padding
- expanded width large enough for icon plus label text
- vertical layout of actions with stable 32 x 32 icon slots
- action widgets fill the available sidebar width in compact and expanded modes
- support a growable spacer between primary launcher actions and bottom system actions
- bottom system actions should include Help, Settings, and Exit in the demo sidebar
- keep the visible action count limited until the upper action group can scroll
- click action shows, hides, raises, or spawns a target window depending on the action policy
- optional active-state marker for currently visible windows
- optional tooltip when collapsed and labels are hidden
- content root fills the full chrome-less window area
- no title header, no close button, and no draggable header in docked mode
- resizing should normally be disabled in compact docked mode
- stacking should keep the sidebar above scene content and generally below modal dialogs

Implementation direction:

- keep the first version as a specialized demo composition before deciding whether it deserves a reusable class
- use `UiVBox` for vertical stacking
- replace temporary `UiButton` rows with `UiIconButton`, `UiSidebarAction`, or an equivalent launcher row once texture-backed icons exist
- give the replacement row a fixed icon slot and a separate label region instead of centering the combined text label with symmetric spacers
- add mouse-wheel scrolling and fade-out indicators for the upper launcher group before adding many more sidebar entries
- allow the expanded state to be a normal retained boolean, later animated by the UI animation scheduler

Demo coverage:

- The demo sidebar replaces the old Demo Control launcher.
- The sidebar toggles Help Desk, Status, and Settings, and spawns Widget Demo and Chrome Demo, with compact and expanded labels.
- The sidebar uses a vertical `UiSpacer` with `flexGrowY` to pin Help, Settings, and Exit actions to the bottom.
- The Widget Demo should include sidebar button rows once icon widgets exist.

Open questions:

- Should the reusable class be `UiSidebar`, `UiDockBar`, or just a documented `UiWindow` role?
- Should hidden target windows be remembered as singleton windows or spawned as new instances?
- Should expansion be hover-driven, click-driven, pinned, or all three?
- Should the sidebar reserve viewport space for the scene, or overlay it?

## Layout Widgets

### UiVBox

Status: Implemented.

`UiVBox` stacks child widgets vertically with spacing, padding, and flex-style growth and shrink behavior.

Common use cases:

- form bodies
- launcher action stacks
- settings groups
- vertical demo probe layout
- future sidebar action list

Required behavior:

- preserve child spacing
- distribute extra or missing height through layout hints
- shrink after previous larger layouts without corrupting preferred sizes
- provide useful debug bounds

Demo coverage:

- Help Desk, Status, Settings, Widget Demo, and Chrome Demo.

### UiHBox

Status: Implemented.

`UiHBox` arranges children horizontally with spacing, padding, and flex-style growth and shrink behavior.

Common use cases:

- form rows
- action button rows
- icon plus text rows
- nested layout probes
- future expanded sidebar entries

Required behavior:

- preserve horizontal spacing
- support fixed and growable children
- keep row height consistent with child preferred sizes

Demo coverage:

- Settings size row and action row.
- Widget Demo nested rows.

## Layout Policy

`UiWidget` layout hints describe both size constraints and growth policy. `minimumWidth`/`minimumHeight` are the smallest useful size, `preferredWidth`/`preferredHeight` are the natural size requested by content, and `maximumWidth`/`maximumHeight` cap stretching. `flexGrowX` and `flexGrowY` tell parent containers whether available surplus space may be assigned to the widget on each axis.

This is intentionally similar to Qt-style size hints plus size policies: the measured content size answers "how large would this widget like to be?", while the grow and maximum hints answer "may this widget consume more room?". `UiButton` uses this distinction so ordinary buttons can stay caption-sized, but sidebar buttons can fill the full bar width by setting `maximumWidth` to `float.max` and `flexGrowX` to `1.0f`.

### UiGrid

Status: Implemented.

`UiGrid` places children in weighted grid cells with explicit placement.

Common use cases:

- palette layouts
- inspector tables
- control galleries
- future icon grids or selection panels

Required behavior:

- deterministic cell placement
- clear debug bounds
- useful weighted row and column allocation

Demo coverage:

- debug color legend documents it; the Widget Demo should add a visible grid example.

### UiSpacer

Status: Implemented.

`UiSpacer` reserves empty layout space.

Common use cases:

- section separation
- flexible gaps
- forcing action rows or panels apart

Required behavior:

- draw no normal content
- expose debug bounds when the bounds overlay is enabled
- participate in layout without becoming an interactive hit target
- keep intrinsic spacer size separate from the arranged size assigned by a growable layout

Demo coverage:

- Help Desk, Widget Demo, and Chrome Demo.

### UiContentBox

Status: Implemented.

`UiContentBox` is a padded content-root container. It assigns its children to a useful inner rectangle and does not draw a visible background or border by default. `UiWindow` uses this for its internal body content root so window chrome stays separate from application widgets.

This widget should stay simple. It should not grow into a scrolling container. Its purpose is to pad and assign a useful inner rectangle to content.

Common use cases:

- window content roots
- chrome-less window content roots
- visual grouping without creating a top-level window

Required behavior:

- assign child to the padded content area
- keep debug bounds distinct from generic widgets
- remain non-scrollable and non-interactive by default
- keep clipping and scroll state out of this class

Demo coverage:

- current window content roots use `UiContentBox` internally.
- Widget Demo shows an explicit padded `UiContentBox` example inside the control gallery.

### UiFrameBox

Status: Implemented.

`UiFrameBox` is the visible sibling of `UiContentBox`. It uses the same padding and child-layout behavior, but draws a background and border before child content. It is intended for framed groups and future repeated item cards where a visible frame is semantically useful.

Common use cases:

- framed panels
- visible groups inside windows
- future card-like repeated items where a card is a genuine item, not a page section

Required behavior:

- assign child to the padded content area
- render background and border before child content
- keep debug bounds distinct from generic widgets
- remain non-scrollable and non-interactive by default
- keep clipping and scroll state out of this class

Demo coverage:

- Widget Demo uses `UiFrameBox` sections for layout probes and retained controls.

### UiScrollArea

Status: Partial.

`UiScrollArea` is the planned widget for content that can be larger than the visible region. It should own a viewport, scroll offsets, optional horizontal and vertical scrollbars, clipping, and pointer-event coordinate translation into the scrolled content.

The first implementation owns retained `scrollX` and `scrollY` offsets, measures content extent, clamps scrolling to content bounds, translates child input by the current scroll offset, and consumes mouse-wheel events. Renderer clipping, visible scrollbars, and fade indicators are still planned.

Common use cases:

- settings pages that can become taller than the window
- long help or log content
- widget galleries with more controls than fit on screen
- scrollable lists before or alongside dedicated list widgets
- smaller windows that can still expose oversized content

Required behavior:

- own `scrollX` and `scrollY`
- expose a visible viewport rectangle
- clip child rendering to that viewport
- translate pointer events by the current scroll offset
- support mouse wheel scrolling
- show horizontal and vertical scrollbars when content exceeds viewport size
- let scrollbars be dragged directly
- clamp scroll offsets to the content bounds
- preserve keyboard focus for children inside the scrolled content
- provide debug bounds for viewport, content extent, and scrollbar regions

Implementation direction:

- model the public widget as `UiScrollArea`
- use an internal `UiViewport` concept if the implementation benefits from naming the clipped visible rectangle separately
- allow one child content root first, then decide whether multiple children are useful
- keep visual framing optional so it can be combined with `UiContentBox` or used directly inside `UiWindow`

Demo coverage:

- planned Widget Demo gallery should use it once the gallery grows beyond one window.
- Help Desk should use it for long help content after renderer clipping and text-block content exist.
- Settings should use it when tab pages or grouped settings exceed the current window height.

Open questions:

- Should scrollbars be ordinary widgets or private parts of `UiScrollArea`?
- Should content measurement happen before or during scroll-area layout?
- Should the first version support both axes immediately, or vertical first with horizontal later?

## Text Widgets

### UiLabel

Status: Implemented.

`UiLabel` renders a single line of text.

Common use cases:

- status values
- field descriptions
- summary lines
- sidebar labels in expanded mode

Required behavior:

- measure from font atlas metrics
- support configured text style and color
- remain non-focusable and non-editable
- update text without rebuilding the owning window

Demo coverage:

- Help Desk, Status, Settings, and Chrome Demo.

### UiTextBlock

Status: Partial.

`UiTextBlock` is the planned multi-line text widget. It currently exists as a placeholder-level text widget and should evolve into wrapped or explicit multi-line rendering.

Common use cases:

- help panels
- documentation snippets
- log output
- validation summaries

Required behavior:

- text wrapping or explicit line breaks
- line-height measurement
- optional clipping when inside scrollable regions
- future selectable or copyable text is optional

Demo coverage:

- Help Desk should use it once multi-line rendering is complete.

Planned work:

- line wrapping
- scroll integration
- optional monospace style for logs

## Action Widgets

### UiButton

Status: Implemented.

`UiButton` is a framed clickable action widget with optional image and label content.

The current implementation is a compound widget: the button owns an internal horizontal row with flexible spacer widgets, an optional image, and a label. This keeps ordinary caption buttons centered and gives us a simple icon-plus-text path, but it is not ideal for sidebar launcher rows where the icon slot should stay fixed on the left and the expanded label should occupy a separate text region.

Common use cases:

- launcher actions
- dialog Apply and Save actions
- icon buttons
- future sidebar item base

Required behavior:

- emit click callback on primary activation
- activate with Enter when focused
- show pointer/action cursor
- measure from label and optional icon content
- stretch only when layout hints and grow policy explicitly allow it
- support future hover, pressed, disabled, and focused states

Demo coverage:

- Settings and Widget Demo.
- Widget Demo includes button examples in the retained-controls section.
- Sidebar currently reuses `UiButton` as a temporary text-placeholder row.
- Sidebar should later use `UiIconButton`, `UiSidebarAction`, or a specialized derivative.

### UiToggle

Status: Implemented.

`UiToggle` is a boolean setting control.

Common use cases:

- settings flags
- chrome behavior toggles
- visibility filters
- future pinned sidebar expansion toggle

Required behavior:

- expose checked state
- emit changed callback
- activate with Enter when focused
- show action cursor

Demo coverage:

- Settings and Chrome Demo.

### UiSlider

Status: Implemented.

`UiSlider` is a horizontal floating-point value control with pointer dragging.

Common use cases:

- UI scale
- audio volume
- animation speed
- render/debug parameters

Required behavior:

- map pointer position to value
- capture pointer while dragging
- clamp value to min/max
- emit changed callback during updates
- adjust with arrow keys, Home, and End when focused

Demo coverage:

- Settings.
- planned Audio Demo and Animation Demo.

### UiDropdown

Status: Partial.

`UiDropdown` is a compact option selector that requests a transient popup list on click or focused Enter. It participates in keyboard focus traversal and shows the generic focus ring while focused. The current demo wires activation requests to a chrome-less popup `UiWindow`; the later reusable step is extracting that option-list surface into a proper selection/list widget.

Common use cases:

- window mode
- theme
- render profile
- settings categories
- selection examples

Required behavior:

- show selected text
- emit changed callback
- open popup list through `UiScreen` popup primitives
- dismiss popup on outside click
- support keyboard popup opening. Implemented for focused Enter.
- support keyboard selection later

Demo coverage:

- Settings.
- Widget Demo.
- planned Selection Demo.

### UiTextField

Status: Implemented for single-line editing.

`UiTextField` is a focusable single-line text input.

Common use cases:

- numeric settings
- names or profile values
- search/filter inputs
- command fields

Required behavior:

- acquire focus on primary click
- receive UTF-8 text input
- handle Backspace, Delete, Home, End, Left, and Right
- render caret
- emit changed callback
- show text insertion cursor

Demo coverage:

- Settings width and height fields.
- planned Input Demo.

## Visual And Media Widgets

### UiImage

Status: Partial.

`UiImage` is currently a compact framed image/icon placeholder. It should become texture-backed and later support animated image content.

Common use cases:

- button icons
- sidebar icons
- image previews
- state indicators
- future sprite or media previews

Required behavior:

- stable preferred size
- optional aspect-ratio constraints
- texture or atlas reference once the asset path exists
- optional frame selection for animated images

Demo coverage:

- button tests currently cover image-plus-label composition.
- planned Media Demo and Sidebar.

### UiVideo

Status: Planned.

`UiVideo` is a future media widget for video-like playback or decoded streams.

Common use cases:

- animated previews
- tutorial panels
- cutscene or media playback experiments

Required behavior:

- explicit play, pause, stop, and loop state
- aspect-ratio preserving layout
- renderer-facing texture frame handoff
- integration with future media/audio timing if needed

Demo coverage:

- planned Media Demo.

## Planned Selection And Navigation Widgets

### UiTabBar

Status: Partial.

`UiTabBar` selects one visible page from several related content pages. It currently renders as a row of visual tabs attached to the top of the page area, supports pointer and direct key selection, and is used by the Settings window.

Common use cases:

- Settings pages
- demo category switching
- inspector panels

Required behavior:

- active tab state. Implemented.
- changed callback. Implemented.
- keyboard navigation. Implemented for Left, Right, Home, and End when focused.
- compact label measurement. Implemented.
- overflow navigation with mouse wheel, arrow buttons, and edge fade indicators. Planned for tab sets that exceed the available width.

Demo coverage:

- Settings window for Display, UI, and Audio pages.
- Widget Demo.

### UiProgressBar

Status: Planned.

`UiProgressBar` displays determinate or indeterminate progress.

Common use cases:

- loading or asset progress
- audio fade preview
- animation demo progress
- background task status

Required behavior:

- clamped value display
- optional text label
- future indeterminate animation

Demo coverage:

- planned Animation Demo and Widget Demo.

### UiListBox

Status: Partial.

`UiListBox` shows selectable text rows. It is currently used as the reusable option surface inside dropdown popups.

Common use cases:

- popup dropdown list
- settings profile list
- asset or scene list
- log filters

Required behavior:

- selected row state. Implemented.
- changed callback. Implemented.
- activation callback for clicks on the already selected row. Implemented.
- active row rendering. Implemented for the selected row.
- keyboard selection. Implemented for Up, Down, Left, Right, Home, End, and Enter when focused.
- hover row rendering later
- scroll integration when content exceeds viewport
- focus traversal integration later

Demo coverage:

- Settings dropdown popups.
- Widget Demo dropdown popup.
- planned Selection Demo.

### UiSeparator

Status: Planned.

`UiSeparator` is a thin visual divider for grouped content.

Common use cases:

- settings sections
- toolbar or sidebar groups
- status and log grouping

Required behavior:

- horizontal and vertical variants
- predictable spacing in `UiVBox` and `UiHBox`
- no input behavior

Demo coverage:

- Sidebar after grouped launcher sections exist.
- Settings after tabs/grouped panels exist.

### UiPopupRoot

Status: Partial.

`UiPopupRoot` is the planned widget-facing owner for transient UI surfaces such as menus, dropdown lists, and tooltips. The first implementation step lives in `UiScreen`: a transient popup `UiWindow` can be shown near an anchor rectangle, clamped to the viewport, kept above ordinary windows, and dismissed on outside click or Escape.

Common use cases:

- dropdown option lists
- context menus
- tooltips
- small chooser panels

Required behavior:

- place relative to anchor widget. Implemented at screen-window level.
- clamp to viewport edges. Implemented at screen-window level.
- dismiss on outside click or Escape. Implemented at screen-window level.
- stack above normal windows but below active popups and modal blocking policy where appropriate. Implemented at screen-window level.
- expose a widget-level popup root API for dropdowns, context menus, and tooltips.

Demo coverage:

- planned Selection Demo.
- current unit coverage in `UiScreen` for placement, clamping, stacking, outside-click dismissal, and Escape dismissal.

### UiTooltip

Status: Planned.

`UiTooltip` shows short explanatory text for icon-only or compact controls.

Common use cases:

- collapsed sidebar actions
- icon buttons
- disabled control reasons

Required behavior:

- delayed hover display
- viewport-clamped placement
- non-focusable transient rendering
- dismissal on pointer leave or input

Demo coverage:

- planned Sidebar and Widget Demo.

### UiIconButton

Status: Planned.

`UiIconButton` is a compact action button centered around an icon, with optional text in expanded contexts.

Common use cases:

- sidebar launcher entries
- toolbar actions
- compact window controls

Required behavior:

- stable icon slot, usually 32 x 32 px for the first sidebar implementation
- optional label text in a separate region beside the icon slot
- left-edge sidebar mode where the icon remains aligned and the row can fill the available width
- active, hover, pressed, disabled, and focused states
- tooltip support when the label is hidden
- action cursor

Demo coverage:

- planned Sidebar.
- Widget Demo once icon assets exist.
