/** Lightweight pointer input events for retained UI widgets.
 *
 * The event model stays intentionally small so widgets can own their input
 * without forcing the renderer to translate every interaction manually.
 *
 * Authors: Carsten Schlote, schlote@vahanus.net
 * Copyright: Carsten Schlote, Released under CC-BY-NC-SA 4.0 license, 2018-2026
 * License: CC-BY-NC-SA 4.0
 */
module vulkan.ui.ui_event;

/** Pointer events that can be routed through the widget tree. */
enum UiPointerEventKind
{
    move,
    buttonDown,
    buttonUp,
    wheel,
}

/** Describes one pointer event in widget-local coordinates. */
struct UiPointerEvent
{
    /** Event kind. */
    UiPointerEventKind kind;
    /** Pointer X coordinate in the current widget space. */
    float x;
    /** Pointer Y coordinate in the current widget space. */
    float y;
    /** Pointer button identifier for button events. */
    uint button;
    /** Horizontal wheel delta for wheel events. */
    float wheelX;
    /** Vertical wheel delta for wheel events. */
    float wheelY;
}
