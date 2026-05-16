/** Cursor intent values reported by retained UI hit testing.
 *
 * Widgets report semantic cursor intent instead of platform cursor handles.
 * The application or window backend maps these values to SDL or another
 * platform-specific cursor implementation.
 *
 * Authors: Carsten Schlote, schlote@vahanus.net
 * Copyright: Carsten Schlote, Released under CC-BY-NC-SA 4.0 license, 2018-2026
 * License: CC-BY-NC-SA 4.0
 */
module vulkan.ui.ui_cursor;

import vulkan.ui.ui_event : UiResizeHandle;

/** Semantic cursor shapes understood by the retained UI layer. */
enum UiCursorKind
{
    /** Default arrow or scene cursor. */
    default_,
    /** Text insertion cursor. */
    text,
    /** Clickable action cursor. */
    pointer,
    /** Move or drag cursor. */
    move,
    /** Horizontal resize cursor. */
    resizeHorizontal,
    /** Vertical resize cursor. */
    resizeVertical,
    /** Northwest/southeast diagonal resize cursor. */
    resizeNwse,
    /** Northeast/southwest diagonal resize cursor. */
    resizeNesw,
    /** Busy or waiting cursor. */
    busy,
    /** Blocked or not-allowed cursor. */
    blocked,
}

/** Maps a resize handle to the cursor shape that describes its gesture.
 *
 * Params:
 *   handle = Resize handle returned by window chrome hit testing.
 *
 * Returns:
 *   Cursor shape for the handle, or `default_` when no resize is active.
 */
UiCursorKind cursorForResizeHandle(UiResizeHandle handle)
{
    final switch (handle)
    {
        case UiResizeHandle.none:
            return UiCursorKind.default_;
        case UiResizeHandle.topLeft:
        case UiResizeHandle.bottomRight:
            return UiCursorKind.resizeNwse;
        case UiResizeHandle.topRight:
        case UiResizeHandle.bottomLeft:
            return UiCursorKind.resizeNesw;
        case UiResizeHandle.top:
        case UiResizeHandle.bottom:
            return UiCursorKind.resizeVertical;
        case UiResizeHandle.left:
        case UiResizeHandle.right:
            return UiCursorKind.resizeHorizontal;
    }
}
