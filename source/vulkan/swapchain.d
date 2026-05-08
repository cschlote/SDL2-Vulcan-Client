/** Swapchain creation, image-view setup, and surface capability helpers. */
module vulkan.swapchain;

import bindbc.vulkan;
import std.exception : enforce;

/** Owns the Vulkan swapchain and its image views. */
struct Swapchain
{
    VkSwapchainKHR handle = VK_NULL_HANDLE;
    VkFormat imageFormat = VkFormat.VK_FORMAT_UNDEFINED;
    VkExtent2D extent;
    VkImage[] images;
    VkImageView[] imageViews;

    /** Creates the swapchain and image views for the current window extent.
     *
     * @param physicalDevice = Vulkan physical device used to query surface support.
     * @param device = Logical Vulkan device.
     * @param surface = Presentation surface.
     * @param graphicsFamily = Graphics queue family index.
     * @param presentFamily = Present queue family index.
     * @param width = Requested swapchain width.
     * @param height = Requested swapchain height.
     * @returns Nothing.
     */
    this(VkPhysicalDevice physicalDevice, VkDevice device, VkSurfaceKHR surface, uint graphicsFamily, uint presentFamily, uint width, uint height)
    {
        VkSurfaceCapabilitiesKHR capabilities;
        enforce(vkGetPhysicalDeviceSurfaceCapabilitiesKHR(physicalDevice, surface, &capabilities) == VkResult.VK_SUCCESS, "vkGetPhysicalDeviceSurfaceCapabilitiesKHR failed.");

        auto surfaceFormat = chooseSurfaceFormat(physicalDevice, surface);
        auto presentMode = choosePresentMode(physicalDevice, surface);
        extent = chooseExtent(capabilities, width, height);

        uint imageCount = capabilities.minImageCount + 1;
        if (capabilities.maxImageCount > 0 && imageCount > capabilities.maxImageCount)
            imageCount = capabilities.maxImageCount;

        VkSwapchainCreateInfoKHR createInfo;
        createInfo.sType = VkStructureType.VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR;
        createInfo.surface = surface;
        createInfo.minImageCount = imageCount;
        createInfo.imageFormat = surfaceFormat.format;
        createInfo.imageColorSpace = surfaceFormat.colorSpace;
        createInfo.imageExtent = extent;
        createInfo.imageArrayLayers = 1;
        createInfo.imageUsage = VkImageUsageFlagBits.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT;
        createInfo.preTransform = capabilities.currentTransform;
        createInfo.compositeAlpha = VkCompositeAlphaFlagBitsKHR.VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR;
        createInfo.presentMode = presentMode;
        createInfo.clipped = VK_TRUE;

        if (graphicsFamily != presentFamily)
        {
            uint[2] indices = [graphicsFamily, presentFamily];
            createInfo.imageSharingMode = VkSharingMode.VK_SHARING_MODE_CONCURRENT;
            createInfo.queueFamilyIndexCount = 2;
            createInfo.pQueueFamilyIndices = indices.ptr;
        }
        else
        {
            createInfo.imageSharingMode = VkSharingMode.VK_SHARING_MODE_EXCLUSIVE;
        }

        enforce(vkCreateSwapchainKHR(device, &createInfo, null, &handle) == VkResult.VK_SUCCESS, "vkCreateSwapchainKHR failed.");

        uint swapchainImageCount = 0;
        enforce(vkGetSwapchainImagesKHR(device, handle, &swapchainImageCount, null) == VkResult.VK_SUCCESS, "vkGetSwapchainImagesKHR failed.");
        images.length = swapchainImageCount;
        enforce(vkGetSwapchainImagesKHR(device, handle, &swapchainImageCount, images.ptr) == VkResult.VK_SUCCESS, "vkGetSwapchainImagesKHR failed.");
        imageFormat = surfaceFormat.format;

        imageViews.length = images.length;
        foreach (index, image; images)
        {
            VkImageViewCreateInfo viewInfo;
            viewInfo.sType = VkStructureType.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO;
            viewInfo.image = image;
            viewInfo.viewType = VkImageViewType.VK_IMAGE_VIEW_TYPE_2D;
            viewInfo.format = imageFormat;
            viewInfo.components.r = VkComponentSwizzle.VK_COMPONENT_SWIZZLE_IDENTITY;
            viewInfo.components.g = VkComponentSwizzle.VK_COMPONENT_SWIZZLE_IDENTITY;
            viewInfo.components.b = VkComponentSwizzle.VK_COMPONENT_SWIZZLE_IDENTITY;
            viewInfo.components.a = VkComponentSwizzle.VK_COMPONENT_SWIZZLE_IDENTITY;
            viewInfo.subresourceRange.aspectMask = VkImageAspectFlagBits.VK_IMAGE_ASPECT_COLOR_BIT;
            viewInfo.subresourceRange.baseMipLevel = 0;
            viewInfo.subresourceRange.levelCount = 1;
            viewInfo.subresourceRange.baseArrayLayer = 0;
            viewInfo.subresourceRange.layerCount = 1;

            enforce(vkCreateImageView(device, &viewInfo, null, &imageViews[index]) == VkResult.VK_SUCCESS, "vkCreateImageView failed.");
        }
    }

    /** Destroys the image views and swapchain handle if they are still alive.
     *
     * @param device = Logical Vulkan device that owns the resources.
     * @returns Nothing.
     */
    void destroy(VkDevice device)
    {
        foreach (view; imageViews)
        {
            if (view != VK_NULL_HANDLE)
                vkDestroyImageView(device, view, null);
        }
        imageViews.length = 0;

        if (handle != VK_NULL_HANDLE)
        {
            vkDestroySwapchainKHR(device, handle, null);
            handle = VK_NULL_HANDLE;
        }
    }
}

/** Chooses the most suitable surface format supported by the device.
 *
 * @param physicalDevice = Vulkan physical device handle.
 * @param surface = Presentation surface.
 * @returns A supported surface format.
 */
private VkSurfaceFormatKHR chooseSurfaceFormat(VkPhysicalDevice physicalDevice, VkSurfaceKHR surface)
{
    uint count = 0;
    enforce(vkGetPhysicalDeviceSurfaceFormatsKHR(physicalDevice, surface, &count, null) == VkResult.VK_SUCCESS, "vkGetPhysicalDeviceSurfaceFormatsKHR failed.");

    VkSurfaceFormatKHR[] formats;
    formats.length = count;
    enforce(vkGetPhysicalDeviceSurfaceFormatsKHR(physicalDevice, surface, &count, formats.ptr) == VkResult.VK_SUCCESS, "vkGetPhysicalDeviceSurfaceFormatsKHR failed.");

    foreach (format; formats)
    {
        if (format.format == VkFormat.VK_FORMAT_B8G8R8A8_SRGB && format.colorSpace == VkColorSpaceKHR.VK_COLORSPACE_SRGB_NONLINEAR_KHR)
            return format;
    }

    return formats[0];
}

/** Chooses the preferred present mode for the surface.
 *
 * @param physicalDevice = Vulkan physical device handle.
 * @param surface = Presentation surface.
 * @returns A supported present mode, preferring mailbox when available.
 */
private VkPresentModeKHR choosePresentMode(VkPhysicalDevice physicalDevice, VkSurfaceKHR surface)
{
    uint count = 0;
    enforce(vkGetPhysicalDeviceSurfacePresentModesKHR(physicalDevice, surface, &count, null) == VkResult.VK_SUCCESS, "vkGetPhysicalDeviceSurfacePresentModesKHR failed.");

    VkPresentModeKHR[] modes;
    modes.length = count;
    enforce(vkGetPhysicalDeviceSurfacePresentModesKHR(physicalDevice, surface, &count, modes.ptr) == VkResult.VK_SUCCESS, "vkGetPhysicalDeviceSurfacePresentModesKHR failed.");

    foreach (mode; modes)
    {
        if (mode == VkPresentModeKHR.VK_PRESENT_MODE_MAILBOX_KHR)
            return mode;
    }

    return VkPresentModeKHR.VK_PRESENT_MODE_FIFO_KHR;
}

/** Chooses the final swapchain extent, clamping to surface capabilities.
 *
 * @param capabilities = Surface capability structure.
 * @param width = Requested width.
 * @param height = Requested height.
 * @returns The extent that will be used for the swapchain.
 */
private VkExtent2D chooseExtent(VkSurfaceCapabilitiesKHR capabilities, uint width, uint height)
{
    if (capabilities.currentExtent.width != uint.max)
        return capabilities.currentExtent;

    VkExtent2D chosenExtent;
    chosenExtent.width = width;
    chosenExtent.height = height;
    chosenExtent.width = chosenExtent.width < capabilities.minImageExtent.width ? capabilities.minImageExtent.width : chosenExtent.width;
    chosenExtent.height = chosenExtent.height < capabilities.minImageExtent.height ? capabilities.minImageExtent.height : chosenExtent.height;
    chosenExtent.width = chosenExtent.width > capabilities.maxImageExtent.width ? capabilities.maxImageExtent.width : chosenExtent.width;
    chosenExtent.height = chosenExtent.height > capabilities.maxImageExtent.height ? capabilities.maxImageExtent.height : chosenExtent.height;
    return chosenExtent;
}
