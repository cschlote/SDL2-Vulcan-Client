module window;

import bindbc.sdl : SDL_CreateWindow, SDL_DestroyWindow, SDL_GetError, SDL_GetWindowSize, SDL_SetWindowTitle, SDL_Vulkan_CreateSurface, SDL_Window, SDL_WindowFlags;
import bindbc.vulkan;
import std.exception : enforce;
import std.string : fromStringz, toStringz;

struct SdlWindow
{
    SDL_Window* handle;

    this(string title, int width, int height)
    {
        handle = SDL_CreateWindow(title.toStringz, width, height, SDL_WindowFlags.vulkan | SDL_WindowFlags.resizable);
        enforce(handle !is null, "SDL_CreateWindow failed: " ~ SDL_GetError().fromStringz.idup);
    }

    void destroy()
    {
        if (handle !is null)
        {
            SDL_DestroyWindow(handle);
            handle = null;
        }
    }

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

    void setTitle(string title)
    {
        SDL_SetWindowTitle(handle, title.toStringz);
    }

    bool createVulkanSurface(VkInstance instance, out VkSurfaceKHR surface)
    {
        ulong rawSurface = 0;
        const created = SDL_Vulkan_CreateSurface(handle, instance, null, &rawSurface);
        surface = cast(VkSurfaceKHR)cast(void*)rawSurface;
        return created;
    }
}
