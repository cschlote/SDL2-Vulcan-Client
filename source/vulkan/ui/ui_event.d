/** Lightweight input events for retained UI widgets.
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

/** Edge or corner used when resizing a window from one of its grips. */
enum UiResizeHandle
{
    none,
    top,
    topLeft,
    topRight,
    right,
    bottom,
    bottomLeft,
    bottomRight,
    left,
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
    /** Pointer X coordinate in screen space, preserved during widget-local routing. */
    float screenX;
    /** Pointer Y coordinate in screen space, preserved during widget-local routing. */
    float screenY;
    /** Pointer button identifier for button events. */
    uint button;
    /** Horizontal wheel delta for wheel events. */
    float wheelX;
    /** Vertical wheel delta for wheel events. */
    float wheelY;
}

/** Keyboard event kinds routed to the focused widget. */
enum UiKeyEventKind
{
    keyDown,
    keyUp,
}

/** Small key vocabulary understood by generic widgets. */
enum UiKeyCode
{
    unknown,
    backspace,
    delete_,
    left,
    right,
    up,
    down,
    home,
    end,
    enter,
    escape,
    tab,
}

/** Generic key modifier bits used by retained UI widgets. */
enum UiKeyModifier : uint
{
    none = 0,
    shift = 1 << 0,
}

/** Describes one keyboard event routed through the UI focus owner. */
struct UiKeyEvent
{
    /** Event kind. */
    UiKeyEventKind kind;
    /** Generic key identifier. */
    UiKeyCode key;
    /** True when the platform reports this as a repeated keydown. */
    bool repeat;
    /** Platform modifier bitmask for future shortcut handling. */
    uint modifiers;
}

/** UTF-8 text input emitted by the platform text input layer. */
struct UiTextInputEvent
{
    /** Insertable text payload in UTF-8. */
    string text;
}
