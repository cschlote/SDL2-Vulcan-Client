/** Vulkan instance creation and destruction helpers for the SDL window surface. */
module vulkan.instance;

import bindbc.sdl : SDL_Vulkan_GetInstanceExtensions, SDL_Window;
import bindbc.vulkan;

static immutable char[17] applicationName = "SDL2 Vulkan Demo";
static immutable char[17] engineName = "SDL2 Vulkan Demo";

/** Creates a Vulkan instance using the SDL-required surface extensions.
 *
 * @param windowHandle = SDL window used to query required Vulkan extensions.
 * @returns Nothing.
 */
struct VulkanInstance
{
    VkInstance handle = VK_NULL_HANDLE;

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
