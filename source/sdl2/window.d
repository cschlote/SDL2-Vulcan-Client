/** Wraps SDL window ownership and Vulkan surface creation.
 *
 * Manages the native window handle, exposes size and title helpers, and creates
 * the Vulkan surface needed by the renderer.
 *
 * Authors: Carsten Schlote, schlote@vahanus.net
 * Copyright: Carsten Schlote, Released under CC-BY-NC-SA 4.0 license, 2018-2026
 * License: CC-BY-NC-SA 4.0
 */
module sdl2.window;

import bindbc.sdl : SDL_CreateCursor, SDL_CreateSystemCursor, SDL_Cursor, SDL_DestroyCursor, SDL_CreateWindow, SDL_DestroyWindow, SDL_GetDefaultCursor, SDL_GetError, SDL_GetWindowSize, SDL_SetCursor, SDL_SetWindowMinimumSize, SDL_SetWindowTitle, SDL_SystemCursor, SDL_Vulkan_CreateSurface, SDL_Window, SDL_WindowFlags;
import bindbc.vulkan;
import std.exception : enforce;
import std.string : fromStringz, toStringz;

private enum size_t systemCursorCount = cast(size_t)SDL_SystemCursor.count;

/** Monochrome SDL cursor bitmap used for custom system-cursor overrides. */
struct SdlCursorBitmap
{
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

    /** Returns whether the bitmap has enough data for SDL cursor creation.
     *
     * @returns `true` when dimensions, planes, and hotspot are valid.
     */
    bool isValid() const
    {
        const requiredBytes = cursorMaskBytes(width, height);
        return requiredBytes > 0 &&
            data.length >= requiredBytes &&
            mask.length >= requiredBytes &&
            hotX >= 0 && hotX < width &&
            hotY >= 0 && hotY < height;
    }
}

/** Returns the number of bytes required for one SDL cursor bitmap plane.
 *
 * @param width = Cursor bitmap width in pixels.
 * @param height = Cursor bitmap height in pixels.
 * @returns Required byte count for one data or mask plane.
 */
size_t cursorMaskBytes(int width, int height)
{
    if (width <= 0 || height <= 0)
        return 0;

    return ((cast(size_t)width + 7) / 8) * cast(size_t)height;
}

/** Creates a resizable Vulkan-capable SDL window.
 *
 * The wrapper keeps the native handle alive for the renderer, applies a minimum
 * size, and provides the SDL surface that starts the Vulkan frame pipeline.
 *
 * @param title = Initial window title.
 * @param width = Initial window width in pixels.
 * @param height = Initial window height in pixels.
 * @returns Nothing.
 */
struct SdlWindow
{
    /** Owning SDL window handle used for surface creation and event routing. */
    SDL_Window* handle;
    private SDL_Cursor*[systemCursorCount] systemCursors;
    private SDL_Cursor*[systemCursorCount] customCursors;
    private SDL_SystemCursor activeCursor = SDL_SystemCursor.count;

    this(string title, int width, int height)
    {
        handle = SDL_CreateWindow(title.toStringz, width, height, SDL_WindowFlags.vulkan | SDL_WindowFlags.resizable);
        enforce(handle !is null, "SDL_CreateWindow failed: " ~ SDL_GetError().fromStringz.idup);
        enforce(SDL_SetWindowMinimumSize(handle, 1024, 576), "SDL_SetWindowMinimumSize failed: " ~ SDL_GetError().fromStringz.idup);
    }

    /** Destroys the managed SDL window if it is still alive.
     *
     * @returns Nothing.
     */
    void destroy()
    {
        destroySystemCursors();

        if (handle !is null)
        {
            SDL_DestroyWindow(handle);
            handle = null;
        }
    }

    /** Queries the current drawable window size.
     *
     * @param width = Receives the current window width.
     * @param height = Receives the current window height.
     * @returns `true` when the size query succeeded, otherwise `false`.
     */
    bool getSize(out uint width, out uint height)
    {
        int w = 0;
        int h = 0;
        if (!SDL_GetWindowSize(handle, &w, &h))
            return false;

        width = cast(uint)w;
        height = cast(uint)h;
        return true;
    }

    /** Updates the SDL window title.
     *
     * @param title = New title text.
     * @returns Nothing.
     */
    void setTitle(string title)
    {
        SDL_SetWindowTitle(handle, title.toStringz);
    }

    /** Applies a cached SDL system cursor.
     *
     * @param cursorKind = SDL system cursor kind to apply.
     * @returns Nothing.
     */
    void setSystemCursor(SDL_SystemCursor cursorKind)
    {
        if (cursorKind == activeCursor)
            return;

        auto cursor = cursorFor(cursorKind);
        if (cursor is null)
            cursor = SDL_GetDefaultCursor();
        if (cursor !is null && SDL_SetCursor(cursor))
            activeCursor = cursorKind;
    }

    /** Registers a custom bitmap cursor for one SDL system cursor slot.
     *
     * @param cursorKind = System cursor slot to override.
     * @param bitmap = Monochrome cursor bitmap and hotspot.
     * @returns `true` when SDL accepted the cursor, otherwise `false`.
     */
    bool registerCustomSystemCursor(SDL_SystemCursor cursorKind, ref const SdlCursorBitmap bitmap)
    {
        const index = cast(size_t)cursorKind;
        if (index >= customCursors.length || !bitmap.isValid())
            return false;

        auto cursor = SDL_CreateCursor(bitmap.data.ptr, bitmap.mask.ptr, bitmap.width, bitmap.height, bitmap.hotX, bitmap.hotY);
        if (cursor is null)
            return false;

        destroyCursor(customCursors[index]);
        customCursors[index] = cursor;

        if (cursorKind == activeCursor)
            SDL_SetCursor(cursor);

        return true;
    }

    /** Removes one custom cursor override and falls back to the system cursor.
     *
     * @param cursorKind = System cursor slot to clear.
     * @returns Nothing.
     */
    void clearCustomSystemCursor(SDL_SystemCursor cursorKind)
    {
        const index = cast(size_t)cursorKind;
        if (index >= customCursors.length)
            return;

        destroyCursor(customCursors[index]);

        if (cursorKind == activeCursor)
            activeCursor = SDL_SystemCursor.count;
    }

    /** Creates a Vulkan surface for the managed SDL window.
     *
     * @param instance = The Vulkan instance used for surface creation.
     * @param surface = Receives the created Vulkan surface handle.
     * @returns `true` when SDL reported success, otherwise `false`.
     */
    bool createVulkanSurface(VkInstance instance, out VkSurfaceKHR surface)
    {
        ulong rawSurface = 0;
        const created = SDL_Vulkan_CreateSurface(handle, instance, null, &rawSurface);
        surface = cast(VkSurfaceKHR)cast(void*)rawSurface;
        return created;
    }

private:
    /** Returns a cached SDL cursor for the requested system cursor kind.
     *
     * @param cursorKind = System cursor kind.
     * @returns SDL cursor handle or `null` when SDL cannot create one.
     */
    SDL_Cursor* cursorFor(SDL_SystemCursor cursorKind)
    {
        if (cursorKind == SDL_SystemCursor.default_)
        {
            const defaultIndex = cast(size_t)SDL_SystemCursor.default_;
            if (defaultIndex < customCursors.length && customCursors[defaultIndex] !is null)
                return customCursors[defaultIndex];
            return SDL_GetDefaultCursor();
        }

        const index = cast(size_t)cursorKind;
        if (index >= systemCursors.length)
            return SDL_GetDefaultCursor();

        if (customCursors[index] !is null)
            return customCursors[index];

        if (systemCursors[index] is null)
            systemCursors[index] = SDL_CreateSystemCursor(cursorKind);

        return systemCursors[index];
    }

    /** Destroys cached SDL system cursors created by this wrapper.
     *
     * @returns Nothing.
     */
    void destroySystemCursors()
    {
        foreach (ref cursor; systemCursors)
            destroyCursor(cursor);

        foreach (ref cursor; customCursors)
            destroyCursor(cursor);

        activeCursor = SDL_SystemCursor.count;
    }

    /** Destroys an owned cursor handle and clears the reference.
     *
     * @param cursor = Owned cursor reference to destroy.
     * @returns Nothing.
     */
    void destroyCursor(ref SDL_Cursor* cursor)
    {
        if (cursor !is null)
        {
            SDL_DestroyCursor(cursor);
            cursor = null;
        }
    }
}

@("SdlCursorBitmap validates mask dimensions and hotspot")
unittest
{
    const(ubyte)[] data = [0x80, 0x00];
    const(ubyte)[] mask = [0x80, 0x00];
    auto cursor = SdlCursorBitmap(8, 2, 0, 0, data, mask);
    assert(cursor.isValid());

    cursor.hotY = 2;
    assert(!cursor.isValid());
}
