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
    /** Precision or inspect cursor. */
    crosshair,
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

/** Returns the number of bytes required for an SDL-style cursor bitmap mask.
 *
 * Params:
 *   width = Cursor bitmap width in pixels.
 *   height = Cursor bitmap height in pixels.
 *
 * Returns:
 *   Required byte count for one 1-bit-per-pixel data or mask plane.
 */
size_t cursorBitmapMaskBytes(int width, int height)
{
    if (width <= 0 || height <= 0)
        return 0;

    return ((cast(size_t)width + 7) / 8) * cast(size_t)height;
}

/** Theme-level monochrome cursor bitmap definition.
 *
 * The bitmap uses SDL's classic cursor representation: `data` selects black
 * pixels and `mask` selects visible pixels. When a theme does not provide a
 * bitmap for a cursor kind, the platform system cursor remains the fallback.
 */
struct UiCursorBitmap
{
    /** Cursor kind this bitmap replaces. */
    UiCursorKind kind;
    /** Cursor bitmap width in pixels. */
    int width;
    /** Cursor bitmap height in pixels. */
    int height;
    /** Hotspot X coordinate in pixels. */
    int hotX;
    /** Hotspot Y coordinate in pixels. */
    int hotY;
    /** 1-bit cursor data plane. */
    const(ubyte)[] data;
    /** 1-bit cursor visibility mask plane. */
    const(ubyte)[] mask;

    /** Returns whether the bitmap has a usable shape and hotspot.
     *
     * Returns:
     *   `true` when dimensions, planes, and hotspot are valid.
     */
    bool isValid() const
    {
        const requiredBytes = cursorBitmapMaskBytes(width, height);
        return requiredBytes > 0 &&
            data.length >= requiredBytes &&
            mask.length >= requiredBytes &&
            hotX >= 0 && hotX < width &&
            hotY >= 0 && hotY < height;
    }
}

@("UiCursorBitmap validates mask dimensions and hotspot")
unittest
{
    const(ubyte)[] data = [0x80, 0x00];
    const(ubyte)[] mask = [0x80, 0x00];
    auto cursor = UiCursorBitmap(UiCursorKind.pointer, 8, 2, 0, 0, data, mask);
    assert(cursor.isValid());

    cursor.hotX = 8;
    assert(!cursor.isValid());
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
