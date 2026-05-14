/** Creates and owns the Vulkan instance.
 *
 * Requests the SDL-required instance extensions, configures the application
 * and engine names, and tears the instance down through the wrapper lifetime.
 *
 * Authors: Carsten Schlote, schlote@vahanus.net
 * Copyright: Carsten Schlote, Released under CC-BY-NC-SA 4.0 license, 2018
 * License: CC-BY-NC-SA 4.0
 */
module vulkan.instance;

import bindbc.sdl : SDL_Vulkan_GetInstanceExtensions, SDL_Window;
import bindbc.vulkan;

private static immutable char[17] applicationName = "SDL2 Vulkan Demo";
private static immutable char[17] engineName = "SDL2 Vulkan Demo";

/** Wraps the Vulkan instance handle created from the SDL-required extensions.
 *
 * The instance is the first Vulkan object in the renderer's lifetime and is
 * kept separate so the surface, device, and swapchain can all be created and
 * destroyed in a controlled order.
 *
 *
 * @param windowHandle = SDL window used to query required Vulkan extensions.
 * @returns Nothing.
 */
struct VulkanInstance
{
    /** Vulkan instance handle owned by the wrapper. */
    VkInstance handle = VK_NULL_HANDLE;

    /** Creates a Vulkan instance using the SDL-required surface extensions.
     *
     * @param windowHandle = SDL window used to query required Vulkan extensions.
     */
    this(SDL_Window* windowHandle)
    {
        uint extensionCount = 0;
        const(char*)* requiredExtensions = SDL_Vulkan_GetInstanceExtensions(&extensionCount);
        if (requiredExtensions is null || extensionCount == 0)
            throw new Exception("SDL_Vulkan_GetInstanceExtensions failed.");

        const(char)*[] extensions;
        extensions.length = extensionCount;
        foreach (index; 0 .. extensionCount)
            extensions[index] = requiredExtensions[index];

        VkApplicationInfo applicationInfo;
        applicationInfo.sType = VkStructureType.VK_STRUCTURE_TYPE_APPLICATION_INFO;
        applicationInfo.pApplicationName = &applicationName[0];
        applicationInfo.applicationVersion = (1u << 22);
        applicationInfo.pEngineName = &engineName[0];
        applicationInfo.engineVersion = (1u << 22);
        applicationInfo.apiVersion = VK_API_VERSION;

        VkInstanceCreateInfo createInfo;
        createInfo.sType = VkStructureType.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO;
        createInfo.pApplicationInfo = &applicationInfo;
        createInfo.enabledExtensionCount = cast(uint)extensions.length;
        createInfo.ppEnabledExtensionNames = extensions.ptr;

        if (vkCreateInstance(&createInfo, null, &handle) != VkResult.VK_SUCCESS)
            throw new Exception("vkCreateInstance failed.");
    }

    /** Destroys the Vulkan instance if it is still alive.
     *
     * @returns Nothing.
     */
    void destroy()
    {
        if (handle != VK_NULL_HANDLE)
        {
            vkDestroyInstance(handle, null);
            handle = VK_NULL_HANDLE;
        }
    }
}
