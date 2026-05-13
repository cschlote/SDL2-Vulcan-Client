/** $purposeofFile
 *
 * Authors: Carsten Schlote, schlote@vahanus.net
 * Copyright: Carsten Schlote, Released under CC-BY-NC-SA 4.0 license, 2018
 * License: CC-BY-NC-SA 4.0
 */
module window;

import bindbc.sdl : SDL_CreateWindow, SDL_DestroyWindow, SDL_GetError, SDL_GetWindowSize, SDL_SetWindowTitle, SDL_Vulkan_CreateSurface, SDL_Window, SDL_WindowFlags;
import bindbc.vulkan;
import std.exception : enforce;
import std.string : fromStringz, toStringz;

/** Creates a resizable Vulkan-capable SDL window.
 *
 * @param title = Initial window title.
 * @param width = Initial window width in pixels.
 * @param height = Initial window height in pixels.
 * @returns Nothing.
 */
struct SdlWindow
{
    /** Owning SDL window handle. */
    SDL_Window* handle;

    this(string title, int width, int height)
    {
        handle = SDL_CreateWindow(title.toStringz, width, height, SDL_WindowFlags.vulkan | SDL_WindowFlags.resizable);
        enforce(handle !is null, "SDL_CreateWindow failed: " ~ SDL_GetError().fromStringz.idup);
    }

    /** Destroys the managed SDL window if it is still alive.
     *
     * @returns Nothing.
     */
    void destroy()
    {
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
}
