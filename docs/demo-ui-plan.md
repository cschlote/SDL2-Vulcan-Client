# Demo UI Plan

This document describes the next UI steps for the demo application before the implementation grows further.

## Goals

- Keep the retained UI small, explicit, and readable.
- Expand the current test screen into a more useful demo application.
- Add a real settings dialog with persistent INI-based storage.
- Keep planning separate from implementation so each technical step can be reviewed independently.

## Planned Widget Set

The current retained UI already has windows, labels, buttons, spacers, surface boxes, and row or column layout containers. The next layer should add the usual interactive widgets that make the settings dialog and demo windows practical:

- checkbox / toggle
- slider
- text field
- combo box / dropdown
- tab bar
- progress bar
- list box or selection list
- separator or divider
- optional icon or image placeholder widget

The first implementation step should favor simple, composable widgets over a large framework.

## Demo Window Structure

The demo should keep the current five-window test screen as a starting point, then evolve into a small application with dedicated windows:

- Status window: app version, frame rate, active scene, current render mode, save state, and close button that exits the app
- Widget demo window: interactive examples for buttons, toggles, sliders, dropdowns, and text fields
- Controls window: keyboard and mouse help, plus short hints for UI interaction
- Settings window: real settings dialog for display, controls, gameplay, audio, and UI options
- Presets or shortcuts window: quick access to common configurations and window actions

The four corner windows should serve different roles so the UI reads as a proper demo application instead of a fixed debug layout.

## Settings Dialog

The first serious settings dialog should cover the common options a demo or small game usually needs:

- video and display settings such as window mode, fullscreen, resolution, VSync, and scaling
- control settings such as mouse sensitivity, camera speed, and optional axis inversion
- gameplay or demo settings such as default render mode, startup scene, and UI hints
- audio settings such as master volume and effect volume
- UI settings such as font scale, theme accents, and window behavior

The dialog should support a visible Apply or Save action rather than writing config changes immediately on every widget interaction.

## Persistence

Settings should be stored at ~/.config/sdl2-vulcan-demo/config in INI format.

Expected behavior:

- load defaults when the file does not exist
- preserve a stable key layout so the file is easy to read and edit manually
- save only through explicit Apply or Save actions
- keep parsing and serialization small and dependency-free if possible

## Implementation Order

1. Introduce the settings data model and config I/O.
2. Add the missing UI widgets needed by the settings dialog.
3. Build the settings window and hook it into the demo UI.
4. Rework the corner windows so each one has a clear purpose.
5. Validate the flow with small commits after each coherent step.
