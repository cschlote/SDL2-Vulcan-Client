module vulkan.device;

import bindbc.vulkan;
import std.exception : enforce;
import std.string : fromStringz;

enum swapchainExtensionName = "VK_KHR_swapchain";

struct QueueFamilyIndices
{
    uint graphicsFamily = uint.max;
    uint presentFamily = uint.max;

    bool isComplete() const
    {
        return graphicsFamily != uint.max && presentFamily != uint.max;
    }
}

struct VulkanDevice
{
    VkPhysicalDevice physicalDevice = VK_NULL_HANDLE;
    VkDevice handle = VK_NULL_HANDLE;
    VkQueue graphicsQueue = VK_NULL_HANDLE;
    VkQueue presentQueue = VK_NULL_HANDLE;
    QueueFamilyIndices queueFamilies;
    VkFormat depthFormat;

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

    void destroy()
    {
        if (handle != VK_NULL_HANDLE)
        {
            vkDestroyDevice(handle, null);
            handle = VK_NULL_HANDLE;
        }
    }
}

private VkDeviceQueueCreateInfo createQueueInfo(uint familyIndex, const float* priority)
{
    VkDeviceQueueCreateInfo info;
    info.sType = VkStructureType.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO;
    info.queueFamilyIndex = familyIndex;
    info.queueCount = 1;
    info.pQueuePriorities = priority;
    return info;
}

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
