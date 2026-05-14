/** Selects a Vulkan physical device and creates the logical device.
 *
 * Finds the graphics and presentation queue families, validates swapchain
 * support, and builds the device and queue state used by the renderer. The
 * device layer sits directly between the Vulkan instance and the swapchain in
 * docs/vulkan-quickstart.md.
 *
 * See_Also:
 *   docs/vulkan-quickstart.md
 *
 * Authors: Carsten Schlote, schlote@vahanus.net
 * Copyright: Carsten Schlote, Released under CC-BY-NC-SA 4.0 license, 2018
 * License: CC-BY-NC-SA 4.0
 */
module vulkan.device;

import bindbc.vulkan;
import std.exception : enforce;
import std.string : fromStringz;

/** Required Vulkan extension name for swapchain support. */
enum swapchainExtensionName = "VK_KHR_swapchain";

/** Stores the queue families needed by the renderer.
 *
 * The renderer only needs a graphics queue and a presentation queue, so this
 * helper keeps those two capabilities together.
 */
struct QueueFamilyIndices
{
    /** Graphics queue family index used for command submission and rendering. */
    uint graphicsFamily = uint.max;
    /** Present queue family index used for swapchain presentation. */
    uint presentFamily = uint.max;

    /** Reports whether both graphics and present queues were found.
     *
     * @returns `true` when both queue family indices are valid, otherwise `false`.
     */
    bool isComplete() const
    {
        return graphicsFamily != uint.max && presentFamily != uint.max;
    }
}

/** Selects a Vulkan physical device and creates the logical device used by the renderer.
 *
 * The wrapper keeps the queue-family selection and depth-format choice together
 * so the renderer can treat them as a single capability bundle.
 *
 * @param instance = Vulkan instance handle.
 * @param surface = SDL-created Vulkan surface.
 * @returns Nothing.
 */
struct VulkanDevice
{
    /** Selected physical device that passed the capability checks. */
    VkPhysicalDevice physicalDevice = VK_NULL_HANDLE;
    /** Logical device created from the selected physical device. */
    VkDevice handle = VK_NULL_HANDLE;
    /** Graphics queue retrieved from the logical device. */
    VkQueue graphicsQueue = VK_NULL_HANDLE;
    /** Present queue retrieved from the logical device. */
    VkQueue presentQueue = VK_NULL_HANDLE;
    /** Queue family indices used to create the logical device. */
    QueueFamilyIndices queueFamilies;
    /** Depth format chosen for the renderer's depth attachment. */
    VkFormat depthFormat;

    /** Creates the logical device and resolves the renderer queues.
     *
     * @param instance = Vulkan instance handle.
     * @param surface = SDL-created Vulkan surface.
     */
    this(VkInstance instance, VkSurfaceKHR surface)
    {
        physicalDevice = pickPhysicalDevice(instance, surface, queueFamilies);
        depthFormat = findDepthFormat(physicalDevice);

        const(char)*[] deviceExtensions = [swapchainExtensionName.ptr];

        VkPhysicalDeviceFeatures deviceFeatures;
        VkDeviceQueueCreateInfo[2] queueCreateInfos;
        float priority = 1.0f;
        uint queueCreateInfoCount = 0;

        queueCreateInfos[queueCreateInfoCount++] = createQueueInfo(queueFamilies.graphicsFamily, &priority);
        if (queueFamilies.presentFamily != queueFamilies.graphicsFamily)
            queueCreateInfos[queueCreateInfoCount++] = createQueueInfo(queueFamilies.presentFamily, &priority);

        VkDeviceCreateInfo createInfo;
        createInfo.sType = VkStructureType.VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO;
        createInfo.queueCreateInfoCount = queueCreateInfoCount;
        createInfo.pQueueCreateInfos = queueCreateInfos.ptr;
        createInfo.enabledExtensionCount = cast(uint)deviceExtensions.length;
        createInfo.ppEnabledExtensionNames = deviceExtensions.ptr;
        createInfo.pEnabledFeatures = &deviceFeatures;

        enforce(vkCreateDevice(physicalDevice, &createInfo, null, &handle) == VkResult.VK_SUCCESS, "vkCreateDevice failed.");
        vkGetDeviceQueue(handle, queueFamilies.graphicsFamily, 0, &graphicsQueue);
        vkGetDeviceQueue(handle, queueFamilies.presentFamily, 0, &presentQueue);
    }

    /** Destroys the logical Vulkan device if it is still alive.
     *
     * @returns Nothing.
     */
    void destroy()
    {
        if (handle != VK_NULL_HANDLE)
        {
            vkDestroyDevice(handle, null);
            handle = VK_NULL_HANDLE;
        }
    }
}

/** Builds a queue-create-info structure for the requested queue family.
 *
 * @param familyIndex = Queue family index.
 * @param priority = Pointer to the queue priority value.
 * @returns A populated queue-create-info structure.
 */
private VkDeviceQueueCreateInfo createQueueInfo(uint familyIndex, const float* priority)
{
    VkDeviceQueueCreateInfo info;
    info.sType = VkStructureType.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO;
    info.queueFamilyIndex = familyIndex;
    info.queueCount = 1;
    info.pQueuePriorities = priority;
    return info;
}

/** Picks a suitable Vulkan physical device for the SDL surface.
 *
 * @param instance = Vulkan instance handle.
 * @param surface = Presentation surface.
 * @param indices = Receives the discovered queue family indices.
 * @returns The selected physical device handle.
 */
private VkPhysicalDevice pickPhysicalDevice(VkInstance instance, VkSurfaceKHR surface, out QueueFamilyIndices indices)
{
    uint deviceCount = 0;
    enforce(vkEnumeratePhysicalDevices(instance, &deviceCount, null) == VkResult.VK_SUCCESS && deviceCount > 0, "No Vulkan physical devices were found.");

    VkPhysicalDevice[] devices;
    devices.length = deviceCount;
    enforce(vkEnumeratePhysicalDevices(instance, &deviceCount, devices.ptr) == VkResult.VK_SUCCESS, "vkEnumeratePhysicalDevices failed.");

    foreach (device; devices)
    {
        QueueFamilyIndices candidate = findQueueFamilies(device, surface);
        if (!candidate.isComplete())
            continue;

        if (!supportsRequiredExtensions(device))
            continue;

        indices = candidate;
        return device;
    }

    enforce(false, "No suitable Vulkan device found.");
    return VK_NULL_HANDLE;
}

/** Finds the graphics and present queue families for a physical device.
 *
 * @param device = Vulkan physical device handle.
 * @param surface = Presentation surface.
 * @returns The discovered queue family indices.
 */
private QueueFamilyIndices findQueueFamilies(VkPhysicalDevice device, VkSurfaceKHR surface)
{
    QueueFamilyIndices indices;

    uint queueFamilyCount = 0;
    vkGetPhysicalDeviceQueueFamilyProperties(device, &queueFamilyCount, null);

    VkQueueFamilyProperties[] families;
    families.length = queueFamilyCount;
    vkGetPhysicalDeviceQueueFamilyProperties(device, &queueFamilyCount, families.ptr);

    foreach (index, family; families)
    {
        if ((family.queueFlags & VkQueueFlagBits.VK_QUEUE_GRAPHICS_BIT) != 0)
            indices.graphicsFamily = cast(uint)index;

        VkBool32 presentSupport = VK_FALSE;
        enforce(vkGetPhysicalDeviceSurfaceSupportKHR(device, cast(uint)index, surface, &presentSupport) == VkResult.VK_SUCCESS, "vkGetPhysicalDeviceSurfaceSupportKHR failed.");
        if (presentSupport != VK_FALSE)
            indices.presentFamily = cast(uint)index;

        if (indices.isComplete())
            break;
    }

    return indices;
}

/** Checks whether the physical device supports the required Vulkan device extensions.
 *
 * @param device = Vulkan physical device handle.
 * @returns `true` when all required extensions are available, otherwise `false`.
 */
private bool supportsRequiredExtensions(VkPhysicalDevice device)
{
    uint extensionCount = 0;
    enforce(vkEnumerateDeviceExtensionProperties(device, null, &extensionCount, null) == VkResult.VK_SUCCESS, "vkEnumerateDeviceExtensionProperties failed.");

    VkExtensionProperties[] extensions;
    extensions.length = extensionCount;
    enforce(vkEnumerateDeviceExtensionProperties(device, null, &extensionCount, extensions.ptr) == VkResult.VK_SUCCESS, "vkEnumerateDeviceExtensionProperties failed.");

    foreach (extension; extensions)
    {
        if (extension.extensionName.fromStringz == swapchainExtensionName)
            return true;
    }

    return false;
}

/** Chooses a supported depth format for the device.
 *
 * @param device = Vulkan physical device handle.
 * @returns A depth-capable Vulkan format.
 */
private VkFormat findDepthFormat(VkPhysicalDevice device)
{
    foreach (format; [VkFormat.VK_FORMAT_D32_SFLOAT, VkFormat.VK_FORMAT_D24_UNORM_S8_UINT, VkFormat.VK_FORMAT_D16_UNORM])
    {
        VkFormatProperties properties;
        vkGetPhysicalDeviceFormatProperties(device, format, &properties);
        if ((properties.optimalTilingFeatures & VkFormatFeatureFlagBits.VK_FORMAT_FEATURE_DEPTH_STENCIL_ATTACHMENT_BIT) != 0)
            return format;
    }

    enforce(false, "No supported depth format found.");
    return VkFormat.VK_FORMAT_UNDEFINED;
}
