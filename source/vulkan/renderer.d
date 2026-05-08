module vulkan.renderer;

import bindbc.sdl : SDL_Delay, SDL_Event, SDL_EventType, SDL_GetError, SDL_GetTicks, SDL_PollEvent, SDL_Scancode, SDL_Vulkan_DestroySurface;
import bindbc.vulkan;
import core.stdc.string : memcpy;
import std.exception : enforce;
import std.format : format;
import std.math : PI, cos, sin;
import std.string : fromStringz;

import math.matrix;
import window;
import vulkan.device;
import vulkan.instance;
import vulkan.pipeline;
import vulkan.swapchain;

enum maxFramesInFlight = 2;

struct BufferResource
{
    VkBuffer buffer = VK_NULL_HANDLE;
    VkDeviceMemory memory = VK_NULL_HANDLE;
    void* mapped = null;
}

class VulkanRenderer
{
    private SdlWindow* window;
    private string baseTitle;
    private VulkanInstance instance;
    private VkSurfaceKHR surface = VK_NULL_HANDLE;
    private VulkanDevice device;
    private Swapchain swapchain;
    private PipelineResources pipeline;

    private VkImage depthImage = VK_NULL_HANDLE;
    private VkDeviceMemory depthImageMemory = VK_NULL_HANDLE;
    private VkImageView depthImageView = VK_NULL_HANDLE;

    private VkCommandPool commandPool = VK_NULL_HANDLE;
    private VkCommandBuffer[] commandBuffers;
    private VkFramebuffer[] framebuffers;

    private BufferResource cubeVertexBuffer;
    private BufferResource cubeIndexBuffer;
    private BufferResource[maxFramesInFlight] uniformBuffers;
    private VkDescriptorPool descriptorPool = VK_NULL_HANDLE;
    private VkDescriptorSet[maxFramesInFlight] descriptorSets;

    private VkSemaphore[maxFramesInFlight] imageAvailableSemaphores;
    private VkSemaphore[maxFramesInFlight] renderFinishedSemaphores;
    private VkFence[maxFramesInFlight] inFlightFences;
    private VkFence[] imagesInFlight;
    private size_t currentFrame;
    private bool framebufferResized;
    private uint frameCounter;
    private ulong fpsStartTicks;
    private bool rotateLeft;
    private bool rotateRight;
    private bool rotateUp;
    private bool rotateDown;
    private float yawAngle = 0.22f;
    private float pitchAngle = 0.14f;
    private ulong lastRotationTicks;

    private enum vertexShaderPath = "build/shaders/main.vert.spv";
    private enum fragmentShaderPath = "build/shaders/main.frag.spv";

    private enum Vertex[] cubeVertices = [
        Vertex([-1, -1,  1], [0.95f, 0.25f, 0.25f]),
        Vertex([ 1, -1,  1], [0.95f, 0.25f, 0.25f]),
        Vertex([ 1,  1,  1], [0.95f, 0.25f, 0.25f]),
        Vertex([-1,  1,  1], [0.95f, 0.25f, 0.25f]),

        Vertex([ 1, -1, -1], [0.25f, 0.85f, 0.35f]),
        Vertex([-1, -1, -1], [0.25f, 0.85f, 0.35f]),
        Vertex([-1,  1, -1], [0.25f, 0.85f, 0.35f]),
        Vertex([ 1,  1, -1], [0.25f, 0.85f, 0.35f]),

        Vertex([-1, -1, -1], [0.25f, 0.45f, 0.95f]),
        Vertex([-1, -1,  1], [0.25f, 0.45f, 0.95f]),
        Vertex([-1,  1,  1], [0.25f, 0.45f, 0.95f]),
        Vertex([-1,  1, -1], [0.25f, 0.45f, 0.95f]),

        Vertex([ 1, -1,  1], [0.95f, 0.85f, 0.25f]),
        Vertex([ 1, -1, -1], [0.95f, 0.85f, 0.25f]),
        Vertex([ 1,  1, -1], [0.95f, 0.85f, 0.25f]),
        Vertex([ 1,  1,  1], [0.95f, 0.85f, 0.25f]),

        Vertex([-1,  1,  1], [0.80f, 0.35f, 0.95f]),
        Vertex([ 1,  1,  1], [0.80f, 0.35f, 0.95f]),
        Vertex([ 1,  1, -1], [0.80f, 0.35f, 0.95f]),
        Vertex([-1,  1, -1], [0.80f, 0.35f, 0.95f]),

        Vertex([-1, -1, -1], [0.25f, 0.90f, 0.90f]),
        Vertex([ 1, -1, -1], [0.25f, 0.90f, 0.90f]),
        Vertex([ 1, -1,  1], [0.25f, 0.90f, 0.90f]),
        Vertex([-1, -1,  1], [0.25f, 0.90f, 0.90f]),
    ];

    private enum uint[] cubeIndices = [
        0, 1, 2, 0, 2, 3,
        4, 5, 6, 4, 6, 7,
        8, 9, 10, 8, 10, 11,
        12, 13, 14, 12, 14, 15,
        16, 17, 18, 16, 18, 19,
        20, 21, 22, 20, 22, 23,
    ];

    this(SdlWindow* window, string buildVersion)
    {
        this.window = window;
        baseTitle = "SDL2 Vulkan Demo " ~ buildVersion;
        window.setTitle(baseTitle);

        instance = VulkanInstance(window.handle);
        enforce(window.createVulkanSurface(instance.handle, surface), "SDL_Vulkan_CreateSurface failed: " ~ fromStringz(SDL_GetError()).idup);

        device = VulkanDevice(instance.handle, surface);

        uint width = 0;
        uint height = 0;
        window.getSize(width, height);
        if (width == 0 || height == 0)
        {
            width = 1280;
            height = 720;
        }

        swapchain = Swapchain(device.physicalDevice, device.handle, surface, device.queueFamilies.graphicsFamily, device.queueFamilies.presentFamily, width, height);
        pipeline = PipelineResources(device.handle, swapchain.extent, swapchain.imageFormat, device.depthFormat, vertexShaderPath, fragmentShaderPath);

        createCommandPool();
        createDepthResources();
        createGeometryBuffers();
        createUniformBuffers();
        createDescriptorPoolAndSets();
        createFramebuffers();
        allocateCommandBuffers();
        createSyncObjects();

        lastRotationTicks = SDL_GetTicks();
        fpsStartTicks = SDL_GetTicks();
    }

    void destroy()
    {
        if (device.handle != VK_NULL_HANDLE)
            vkDeviceWaitIdle(device.handle);

        destroySyncObjects();
        destroyDescriptors();
        destroyGeometryBuffers();
        destroyDepthResources();
        destroyFramebuffers();
        destroyCommandBuffers();
        destroyCommandPool();
        pipeline.destroy(device.handle);
        swapchain.destroy(device.handle);
        device.destroy();

        if (surface != VK_NULL_HANDLE)
        {
            SDL_Vulkan_DestroySurface(instance.handle, cast(ulong)surface, null);
            surface = VK_NULL_HANDLE;
        }

        instance.destroy();
    }

    void run()
    {
        bool running = true;
        while (running)
        {
            SDL_Event event;
            while (SDL_PollEvent(&event))
            {
                if (handleEvent(event))
                {
                    running = false;
                    break;
                }
            }

            if (!running)
                break;

            drawFrame();
        }

        vkDeviceWaitIdle(device.handle);
    }

    bool handleEvent(ref SDL_Event event)
    {
        switch (event.type)
        {
            case SDL_EventType.quit:
                return true;
            case SDL_EventType.keyDown:
                if (event.key.scancode == SDL_Scancode.escape)
                    return true;
                if (event.key.scancode == SDL_Scancode.left)
                    rotateLeft = true;
                else if (event.key.scancode == SDL_Scancode.right)
                    rotateRight = true;
                else if (event.key.scancode == SDL_Scancode.up)
                    rotateUp = true;
                else if (event.key.scancode == SDL_Scancode.down)
                    rotateDown = true;
                return false;
            case SDL_EventType.keyUp:
                if (event.key.scancode == SDL_Scancode.left)
                    rotateLeft = false;
                else if (event.key.scancode == SDL_Scancode.right)
                    rotateRight = false;
                else if (event.key.scancode == SDL_Scancode.up)
                    rotateUp = false;
                else if (event.key.scancode == SDL_Scancode.down)
                    rotateDown = false;
                return false;
            case SDL_EventType.windowResized:
            case SDL_EventType.windowPixelSizeChanged:
            case SDL_EventType.windowCloseRequested:
                framebufferResized = true;
                return false;
            default:
                return false;
        }
    }

    void drawFrame()
    {
        vkWaitForFences(device.handle, 1, &inFlightFences[currentFrame], VK_TRUE, ulong.max);

        uint imageIndex = 0;
        const acquireResult = vkAcquireNextImageKHR(device.handle, swapchain.handle, ulong.max, imageAvailableSemaphores[currentFrame], VK_NULL_HANDLE, &imageIndex);
        if (acquireResult == VkResult.VK_ERROR_OUT_OF_DATE_KHR)
        {
            recreateSwapchain();
            return;
        }

        if (imagesInFlight[imageIndex] != VK_NULL_HANDLE)
            vkWaitForFences(device.handle, 1, &imagesInFlight[imageIndex], VK_TRUE, ulong.max);
        imagesInFlight[imageIndex] = inFlightFences[currentFrame];

        updateGeometryBuffer(currentFrame);

        vkResetFences(device.handle, 1, &inFlightFences[currentFrame]);
        vkResetCommandBuffer(commandBuffers[imageIndex], 0);
        recordCommandBuffer(commandBuffers[imageIndex], imageIndex);

        VkSemaphore[1] waitSemaphores = [imageAvailableSemaphores[currentFrame]];
        VkPipelineStageFlags[1] waitStages = [VkPipelineStageFlagBits.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT];
        VkSemaphore[1] signalSemaphores = [renderFinishedSemaphores[currentFrame]];

        VkSubmitInfo submitInfo;
        submitInfo.sType = VkStructureType.VK_STRUCTURE_TYPE_SUBMIT_INFO;
        submitInfo.waitSemaphoreCount = 1;
        submitInfo.pWaitSemaphores = waitSemaphores.ptr;
        submitInfo.pWaitDstStageMask = waitStages.ptr;
        submitInfo.commandBufferCount = 1;
        submitInfo.pCommandBuffers = &commandBuffers[imageIndex];
        submitInfo.signalSemaphoreCount = 1;
        submitInfo.pSignalSemaphores = signalSemaphores.ptr;

        enforce(vkQueueSubmit(device.graphicsQueue, 1, &submitInfo, inFlightFences[currentFrame]) == VkResult.VK_SUCCESS, "vkQueueSubmit failed.");

        VkSwapchainKHR[1] swapchains = [swapchain.handle];
        VkPresentInfoKHR presentInfo;
        presentInfo.sType = VkStructureType.VK_STRUCTURE_TYPE_PRESENT_INFO_KHR;
        presentInfo.waitSemaphoreCount = 1;
        presentInfo.pWaitSemaphores = signalSemaphores.ptr;
        presentInfo.swapchainCount = 1;
        presentInfo.pSwapchains = swapchains.ptr;
        presentInfo.pImageIndices = &imageIndex;

        const presentResult = vkQueuePresentKHR(device.presentQueue, &presentInfo);
        if (presentResult == VkResult.VK_ERROR_OUT_OF_DATE_KHR || presentResult == VkResult.VK_SUBOPTIMAL_KHR || framebufferResized)
        {
            framebufferResized = false;
            recreateSwapchain();
        }

        currentFrame = (currentFrame + 1) % maxFramesInFlight;

        frameCounter++;
        const now = SDL_GetTicks();
        if (now - fpsStartTicks >= 1_000)
        {
            const fps = cast(double)frameCounter * 1_000.0 / cast(double)(now - fpsStartTicks);
            window.setTitle(format("%s - %.0f FPS", baseTitle, fps));
            fpsStartTicks = now;
            frameCounter = 0;
        }
    }

    private void recreateSwapchain()
    {
        uint width = 0;
        uint height = 0;
        window.getSize(width, height);
        while (width == 0 || height == 0)
        {
            SDL_Delay(16);
            window.getSize(width, height);
        }

        vkDeviceWaitIdle(device.handle);

        destroyFramebuffers();
        destroyDepthResources();
        destroyCommandBuffers();
        pipeline.destroy(device.handle);
        swapchain.destroy(device.handle);

        swapchain = Swapchain(device.physicalDevice, device.handle, surface, device.queueFamilies.graphicsFamily, device.queueFamilies.presentFamily, width, height);
        pipeline = PipelineResources(device.handle, swapchain.extent, swapchain.imageFormat, device.depthFormat, vertexShaderPath, fragmentShaderPath);
        createDepthResources();
        createFramebuffers();
        allocateCommandBuffers();

        imagesInFlight.length = swapchain.images.length;
        imagesInFlight[] = VK_NULL_HANDLE;
    }

    private void createCommandPool()
    {
        VkCommandPoolCreateInfo createInfo;
        createInfo.sType = VkStructureType.VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO;
        createInfo.flags = VkCommandPoolCreateFlagBits.VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT;
        createInfo.queueFamilyIndex = device.queueFamilies.graphicsFamily;

        enforce(vkCreateCommandPool(device.handle, &createInfo, null, &commandPool) == VkResult.VK_SUCCESS, "vkCreateCommandPool failed.");
    }

    private void destroyCommandPool()
    {
        if (commandPool != VK_NULL_HANDLE)
        {
            vkDestroyCommandPool(device.handle, commandPool, null);
            commandPool = VK_NULL_HANDLE;
        }
    }

    private void allocateCommandBuffers()
    {
        commandBuffers.length = swapchain.images.length;

        VkCommandBufferAllocateInfo allocateInfo;
        allocateInfo.sType = VkStructureType.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO;
        allocateInfo.commandPool = commandPool;
        allocateInfo.level = VkCommandBufferLevel.VK_COMMAND_BUFFER_LEVEL_PRIMARY;
        allocateInfo.commandBufferCount = cast(uint)commandBuffers.length;

        enforce(vkAllocateCommandBuffers(device.handle, &allocateInfo, commandBuffers.ptr) == VkResult.VK_SUCCESS, "vkAllocateCommandBuffers failed.");

        imagesInFlight.length = swapchain.images.length;
        imagesInFlight[] = VK_NULL_HANDLE;
    }

    private void destroyCommandBuffers()
    {
        if (commandBuffers.length > 0 && commandPool != VK_NULL_HANDLE)
        {
            vkFreeCommandBuffers(device.handle, commandPool, cast(uint)commandBuffers.length, commandBuffers.ptr);
            commandBuffers.length = 0;
        }
    }

    private void createGeometryBuffers()
    {
        createBuffer(cubeVertexBuffer, cubeVertices, VkBufferUsageFlagBits.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT);
        createBuffer(cubeIndexBuffer, cubeIndices, VkBufferUsageFlagBits.VK_BUFFER_USAGE_INDEX_BUFFER_BIT);
    }

    private void destroyGeometryBuffers()
    {
        destroyBuffer(cubeVertexBuffer);
        destroyBuffer(cubeIndexBuffer);
    }

    private void createUniformBuffers()
    {
        foreach (frameIndex; 0 .. maxFramesInFlight)
        {
            createBuffer(uniformBuffers[frameIndex], Mat4.sizeof, VkBufferUsageFlagBits.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT);
        }
    }

    private void createDescriptorPoolAndSets()
    {
        VkDescriptorPoolSize poolSize;
        poolSize.type = VkDescriptorType.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER;
        poolSize.descriptorCount = maxFramesInFlight;

        VkDescriptorPoolCreateInfo poolInfo;
        poolInfo.sType = VkStructureType.VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO;
        poolInfo.poolSizeCount = 1;
        poolInfo.pPoolSizes = &poolSize;
        poolInfo.maxSets = maxFramesInFlight;

        enforce(vkCreateDescriptorPool(device.handle, &poolInfo, null, &descriptorPool) == VkResult.VK_SUCCESS, "vkCreateDescriptorPool failed.");

        VkDescriptorSetLayout[maxFramesInFlight] layouts;
        layouts[] = pipeline.descriptorSetLayout;

        VkDescriptorSetAllocateInfo allocateInfo;
        allocateInfo.sType = VkStructureType.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO;
        allocateInfo.descriptorPool = descriptorPool;
        allocateInfo.descriptorSetCount = maxFramesInFlight;
        allocateInfo.pSetLayouts = layouts.ptr;

        enforce(vkAllocateDescriptorSets(device.handle, &allocateInfo, descriptorSets.ptr) == VkResult.VK_SUCCESS, "vkAllocateDescriptorSets failed.");

        foreach (frameIndex; 0 .. maxFramesInFlight)
        {
            VkDescriptorBufferInfo bufferInfo;
            bufferInfo.buffer = uniformBuffers[frameIndex].buffer;
            bufferInfo.offset = 0;
            bufferInfo.range = Mat4.sizeof;

            VkWriteDescriptorSet write;
            write.sType = VkStructureType.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
            write.dstSet = descriptorSets[frameIndex];
            write.dstBinding = 0;
            write.dstArrayElement = 0;
            write.descriptorType = VkDescriptorType.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER;
            write.descriptorCount = 1;
            write.pBufferInfo = &bufferInfo;

            vkUpdateDescriptorSets(device.handle, 1, &write, 0, null);
        }
    }

    private void destroyDescriptors()
    {
        foreach (frameIndex; 0 .. maxFramesInFlight)
            destroyBuffer(uniformBuffers[frameIndex]);

        if (descriptorPool != VK_NULL_HANDLE)
        {
            vkDestroyDescriptorPool(device.handle, descriptorPool, null);
            descriptorPool = VK_NULL_HANDLE;
        }
    }

    private void createFramebuffers()
    {
        framebuffers.length = swapchain.imageViews.length;
        foreach (index, view; swapchain.imageViews)
        {
            VkImageView[2] attachments = [view, depthImageView];

            VkFramebufferCreateInfo createInfo;
            createInfo.sType = VkStructureType.VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO;
            createInfo.renderPass = pipeline.renderPass;
            createInfo.attachmentCount = cast(uint)attachments.length;
            createInfo.pAttachments = attachments.ptr;
            createInfo.width = swapchain.extent.width;
            createInfo.height = swapchain.extent.height;
            createInfo.layers = 1;

            enforce(vkCreateFramebuffer(device.handle, &createInfo, null, &framebuffers[index]) == VkResult.VK_SUCCESS, "vkCreateFramebuffer failed.");
        }
    }

    private void destroyFramebuffers()
    {
        foreach (framebuffer; framebuffers)
        {
            if (framebuffer != VK_NULL_HANDLE)
                vkDestroyFramebuffer(device.handle, framebuffer, null);
        }
        framebuffers.length = 0;
    }

    private void createDepthResources()
    {
        VkImageCreateInfo imageInfo;
        imageInfo.sType = VkStructureType.VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO;
        imageInfo.imageType = VkImageType.VK_IMAGE_TYPE_2D;
        imageInfo.format = device.depthFormat;
        imageInfo.extent.width = swapchain.extent.width;
        imageInfo.extent.height = swapchain.extent.height;
        imageInfo.extent.depth = 1;
        imageInfo.mipLevels = 1;
        imageInfo.arrayLayers = 1;
        imageInfo.samples = VkSampleCountFlagBits.VK_SAMPLE_COUNT_1_BIT;
        imageInfo.tiling = VkImageTiling.VK_IMAGE_TILING_OPTIMAL;
        imageInfo.usage = VkImageUsageFlagBits.VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT;
        imageInfo.sharingMode = VkSharingMode.VK_SHARING_MODE_EXCLUSIVE;
        imageInfo.initialLayout = VkImageLayout.VK_IMAGE_LAYOUT_UNDEFINED;

        enforce(vkCreateImage(device.handle, &imageInfo, null, &depthImage) == VkResult.VK_SUCCESS, "vkCreateImage failed.");

        VkMemoryRequirements memoryRequirements;
        vkGetImageMemoryRequirements(device.handle, depthImage, &memoryRequirements);

        VkMemoryAllocateInfo allocateInfo;
        allocateInfo.sType = VkStructureType.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
        allocateInfo.allocationSize = memoryRequirements.size;
        allocateInfo.memoryTypeIndex = findMemoryType(memoryRequirements.memoryTypeBits, VkMemoryPropertyFlagBits.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT);

        enforce(vkAllocateMemory(device.handle, &allocateInfo, null, &depthImageMemory) == VkResult.VK_SUCCESS, "vkAllocateMemory for depth image failed.");
        enforce(vkBindImageMemory(device.handle, depthImage, depthImageMemory, 0) == VkResult.VK_SUCCESS, "vkBindImageMemory failed.");

        VkImageViewCreateInfo viewInfo;
        viewInfo.sType = VkStructureType.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO;
        viewInfo.image = depthImage;
        viewInfo.viewType = VkImageViewType.VK_IMAGE_VIEW_TYPE_2D;
        viewInfo.format = device.depthFormat;
        viewInfo.subresourceRange.aspectMask = VkImageAspectFlagBits.VK_IMAGE_ASPECT_DEPTH_BIT;
        viewInfo.subresourceRange.baseMipLevel = 0;
        viewInfo.subresourceRange.levelCount = 1;
        viewInfo.subresourceRange.baseArrayLayer = 0;
        viewInfo.subresourceRange.layerCount = 1;

        enforce(vkCreateImageView(device.handle, &viewInfo, null, &depthImageView) == VkResult.VK_SUCCESS, "vkCreateImageView for depth image failed.");

        transitionImageLayout(depthImage, VkImageLayout.VK_IMAGE_LAYOUT_UNDEFINED, VkImageLayout.VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL);
    }

    private void destroyDepthResources()
    {
        if (depthImageView != VK_NULL_HANDLE)
        {
            vkDestroyImageView(device.handle, depthImageView, null);
            depthImageView = VK_NULL_HANDLE;
        }

        if (depthImage != VK_NULL_HANDLE)
        {
            vkDestroyImage(device.handle, depthImage, null);
            depthImage = VK_NULL_HANDLE;
        }

        if (depthImageMemory != VK_NULL_HANDLE)
        {
            vkFreeMemory(device.handle, depthImageMemory, null);
            depthImageMemory = VK_NULL_HANDLE;
        }
    }

    private void createSyncObjects()
    {
        VkSemaphoreCreateInfo semaphoreInfo;
        semaphoreInfo.sType = VkStructureType.VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO;

        VkFenceCreateInfo fenceInfo;
        fenceInfo.sType = VkStructureType.VK_STRUCTURE_TYPE_FENCE_CREATE_INFO;
        fenceInfo.flags = VkFenceCreateFlagBits.VK_FENCE_CREATE_SIGNALED_BIT;

        foreach (frameIndex; 0 .. maxFramesInFlight)
        {
            enforce(vkCreateSemaphore(device.handle, &semaphoreInfo, null, &imageAvailableSemaphores[frameIndex]) == VkResult.VK_SUCCESS, "vkCreateSemaphore failed.");
            enforce(vkCreateSemaphore(device.handle, &semaphoreInfo, null, &renderFinishedSemaphores[frameIndex]) == VkResult.VK_SUCCESS, "vkCreateSemaphore failed.");
            enforce(vkCreateFence(device.handle, &fenceInfo, null, &inFlightFences[frameIndex]) == VkResult.VK_SUCCESS, "vkCreateFence failed.");
        }
    }

    private void destroySyncObjects()
    {
        foreach (frameIndex; 0 .. maxFramesInFlight)
        {
            if (imageAvailableSemaphores[frameIndex] != VK_NULL_HANDLE)
                vkDestroySemaphore(device.handle, imageAvailableSemaphores[frameIndex], null);
            if (renderFinishedSemaphores[frameIndex] != VK_NULL_HANDLE)
                vkDestroySemaphore(device.handle, renderFinishedSemaphores[frameIndex], null);
            if (inFlightFences[frameIndex] != VK_NULL_HANDLE)
                vkDestroyFence(device.handle, inFlightFences[frameIndex], null);
        }
    }

    private void updateGeometryBuffer(size_t frameIndex)
    {
        Mat4 identity = Mat4.identity();
        memcpy(uniformBuffers[frameIndex].mapped, identity.m.ptr, Mat4.sizeof);

        const currentTicks = SDL_GetTicks();
        const elapsedTicks = currentTicks - lastRotationTicks;
        lastRotationTicks = currentTicks;

        const clampedElapsedTicks = elapsedTicks > 50 ? 50 : elapsedTicks;
        const deltaSeconds = cast(float)clampedElapsedTicks / 1_000.0f;
        const rotationSpeed = 0.55f;

        if (rotateLeft)
            yawAngle -= rotationSpeed * deltaSeconds;
        if (rotateRight)
            yawAngle += rotationSpeed * deltaSeconds;
        if (rotateUp)
            pitchAngle -= rotationSpeed * deltaSeconds;
        if (rotateDown)
            pitchAngle += rotationSpeed * deltaSeconds;

        Vertex[cubeVertices.length] cubeTransformed;
        foreach (index, source; cubeVertices)
        {
            const scaleFactor = 0.58f;
            const x = source.position[0] * scaleFactor;
            const y = source.position[1] * scaleFactor;
            const z = source.position[2] * scaleFactor;

            const cy = cos(yawAngle);
            const sy = sin(yawAngle);
            const cx = cos(pitchAngle);
            const sx = sin(pitchAngle);

            const rotatedX = x * cy + z * sy;
            const rotatedZ = -x * sy + z * cy;
            const rotatedY = y * cx - rotatedZ * sx;
            const rotatedDepth = y * sx + rotatedZ * cx;
            const cameraDistance = 2.8f;
            const perspective = cameraDistance / (cameraDistance - rotatedDepth);

            const screenX = rotatedX * 0.56f * perspective * cast(float)swapchain.extent.height / cast(float)swapchain.extent.width;
            const screenY = rotatedY * 0.56f * perspective;

            cubeTransformed[index] = Vertex([screenX, screenY, 0.5f - rotatedDepth * 0.18f], source.color);
        }

        memcpy(cubeVertexBuffer.mapped, cubeTransformed.ptr, Vertex.sizeof * cubeTransformed.length);
    }

    private void recordCommandBuffer(VkCommandBuffer commandBuffer, uint imageIndex)
    {
        VkCommandBufferBeginInfo beginInfo;
        beginInfo.sType = VkStructureType.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;
        enforce(vkBeginCommandBuffer(commandBuffer, &beginInfo) == VkResult.VK_SUCCESS, "vkBeginCommandBuffer failed.");

        VkClearValue[2] clearValues;
        clearValues[0].color.float32[0] = 0.08f;
        clearValues[0].color.float32[1] = 0.12f;
        clearValues[0].color.float32[2] = 0.18f;
        clearValues[0].color.float32[3] = 1.0f;
        clearValues[1].depthStencil.depth = 1.0f;
        clearValues[1].depthStencil.stencil = 0;

        VkRenderPassBeginInfo renderPassInfo;
        renderPassInfo.sType = VkStructureType.VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO;
        renderPassInfo.renderPass = pipeline.renderPass;
        renderPassInfo.framebuffer = framebuffers[imageIndex];
        renderPassInfo.renderArea.extent = swapchain.extent;
        renderPassInfo.clearValueCount = cast(uint)clearValues.length;
        renderPassInfo.pClearValues = clearValues.ptr;

        vkCmdBeginRenderPass(commandBuffer, &renderPassInfo, VkSubpassContents.VK_SUBPASS_CONTENTS_INLINE);
        VkViewport viewport;
        viewport.x = 0;
        viewport.y = 0;
        viewport.width = cast(float)swapchain.extent.width;
        viewport.height = cast(float)swapchain.extent.height;
        viewport.minDepth = 0;
        viewport.maxDepth = 1;

        VkRect2D scissor;
        scissor.extent = swapchain.extent;

        vkCmdSetViewport(commandBuffer, 0, 1, &viewport);
        vkCmdSetScissor(commandBuffer, 0, 1, &scissor);

        VkBuffer[1] cubeVertexBuffers = [cubeVertexBuffer.buffer];
        VkDeviceSize[1] offsets = [0];
        vkCmdBindPipeline(commandBuffer, VkPipelineBindPoint.VK_PIPELINE_BIND_POINT_GRAPHICS, pipeline.graphicsPipeline);
        vkCmdBindDescriptorSets(commandBuffer, VkPipelineBindPoint.VK_PIPELINE_BIND_POINT_GRAPHICS, pipeline.pipelineLayout, 0, 1, &descriptorSets[currentFrame], 0, null);
        vkCmdBindVertexBuffers(commandBuffer, 0, 1, cubeVertexBuffers.ptr, offsets.ptr);
        vkCmdBindIndexBuffer(commandBuffer, cubeIndexBuffer.buffer, 0, VkIndexType.VK_INDEX_TYPE_UINT32);
        vkCmdDrawIndexed(commandBuffer, cast(uint)cubeIndices.length, 1, 0, 0, 0);

        vkCmdEndRenderPass(commandBuffer);
        enforce(vkEndCommandBuffer(commandBuffer) == VkResult.VK_SUCCESS, "vkEndCommandBuffer failed.");
    }

    private void transitionImageLayout(VkImage image, VkImageLayout oldLayout, VkImageLayout newLayout)
    {
        VkCommandBuffer commandBuffer = beginSingleTimeCommands();

        VkImageMemoryBarrier barrier;
        barrier.sType = VkStructureType.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER;
        barrier.oldLayout = oldLayout;
        barrier.newLayout = newLayout;
        barrier.srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
        barrier.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
        barrier.image = image;
        barrier.subresourceRange.aspectMask = VkImageAspectFlagBits.VK_IMAGE_ASPECT_DEPTH_BIT;
        barrier.subresourceRange.baseMipLevel = 0;
        barrier.subresourceRange.levelCount = 1;
        barrier.subresourceRange.baseArrayLayer = 0;
        barrier.subresourceRange.layerCount = 1;

        VkPipelineStageFlags sourceStage = VkPipelineStageFlagBits.VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT;
        VkPipelineStageFlags destinationStage = VkPipelineStageFlagBits.VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT;

        vkCmdPipelineBarrier(commandBuffer, sourceStage, destinationStage, 0, 0, null, 0, null, 1, &barrier);
        endSingleTimeCommands(commandBuffer);
    }

    private VkCommandBuffer beginSingleTimeCommands()
    {
        VkCommandBufferAllocateInfo allocateInfo;
        allocateInfo.sType = VkStructureType.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO;
        allocateInfo.level = VkCommandBufferLevel.VK_COMMAND_BUFFER_LEVEL_PRIMARY;
        allocateInfo.commandPool = commandPool;
        allocateInfo.commandBufferCount = 1;

        VkCommandBuffer commandBuffer;
        enforce(vkAllocateCommandBuffers(device.handle, &allocateInfo, &commandBuffer) == VkResult.VK_SUCCESS, "vkAllocateCommandBuffers failed.");

        VkCommandBufferBeginInfo beginInfo;
        beginInfo.sType = VkStructureType.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;
        beginInfo.flags = VkCommandBufferUsageFlagBits.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;
        enforce(vkBeginCommandBuffer(commandBuffer, &beginInfo) == VkResult.VK_SUCCESS, "vkBeginCommandBuffer failed.");
        return commandBuffer;
    }

    private void endSingleTimeCommands(VkCommandBuffer commandBuffer)
    {
        enforce(vkEndCommandBuffer(commandBuffer) == VkResult.VK_SUCCESS, "vkEndCommandBuffer failed.");

        VkSubmitInfo submitInfo;
        submitInfo.sType = VkStructureType.VK_STRUCTURE_TYPE_SUBMIT_INFO;
        submitInfo.commandBufferCount = 1;
        submitInfo.pCommandBuffers = &commandBuffer;

        enforce(vkQueueSubmit(device.graphicsQueue, 1, &submitInfo, VK_NULL_HANDLE) == VkResult.VK_SUCCESS, "vkQueueSubmit failed.");
        enforce(vkQueueWaitIdle(device.graphicsQueue) == VkResult.VK_SUCCESS, "vkQueueWaitIdle failed.");
        vkFreeCommandBuffers(device.handle, commandPool, 1, &commandBuffer);
    }

    private void createBuffer(T)(ref BufferResource resource, const(T)[] data, VkBufferUsageFlags usage)
    {
        const size = data.length * T.sizeof;
        VkBufferCreateInfo bufferInfo;
        bufferInfo.sType = VkStructureType.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO;
        bufferInfo.size = size;
        bufferInfo.usage = usage;
        bufferInfo.sharingMode = VkSharingMode.VK_SHARING_MODE_EXCLUSIVE;

        enforce(vkCreateBuffer(device.handle, &bufferInfo, null, &resource.buffer) == VkResult.VK_SUCCESS, "vkCreateBuffer failed.");

        VkMemoryRequirements memoryRequirements;
        vkGetBufferMemoryRequirements(device.handle, resource.buffer, &memoryRequirements);

        VkMemoryAllocateInfo allocateInfo;
        allocateInfo.sType = VkStructureType.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
        allocateInfo.allocationSize = memoryRequirements.size;
        allocateInfo.memoryTypeIndex = findMemoryType(memoryRequirements.memoryTypeBits, VkMemoryPropertyFlagBits.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VkMemoryPropertyFlagBits.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT);

        enforce(vkAllocateMemory(device.handle, &allocateInfo, null, &resource.memory) == VkResult.VK_SUCCESS, "vkAllocateMemory failed.");
        enforce(vkBindBufferMemory(device.handle, resource.buffer, resource.memory, 0) == VkResult.VK_SUCCESS, "vkBindBufferMemory failed.");

        enforce(vkMapMemory(device.handle, resource.memory, 0, size, 0, &resource.mapped) == VkResult.VK_SUCCESS, "vkMapMemory failed.");

        memcpy(resource.mapped, data.ptr, size);
    }

    private void createBuffer(ref BufferResource resource, size_t size, VkBufferUsageFlags usage)
    {
        VkBufferCreateInfo bufferInfo;
        bufferInfo.sType = VkStructureType.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO;
        bufferInfo.size = size;
        bufferInfo.usage = usage;
        bufferInfo.sharingMode = VkSharingMode.VK_SHARING_MODE_EXCLUSIVE;

        enforce(vkCreateBuffer(device.handle, &bufferInfo, null, &resource.buffer) == VkResult.VK_SUCCESS, "vkCreateBuffer failed.");

        VkMemoryRequirements memoryRequirements;
        vkGetBufferMemoryRequirements(device.handle, resource.buffer, &memoryRequirements);

        VkMemoryAllocateInfo allocateInfo;
        allocateInfo.sType = VkStructureType.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
        allocateInfo.allocationSize = memoryRequirements.size;
        allocateInfo.memoryTypeIndex = findMemoryType(memoryRequirements.memoryTypeBits, VkMemoryPropertyFlagBits.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VkMemoryPropertyFlagBits.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT);

        enforce(vkAllocateMemory(device.handle, &allocateInfo, null, &resource.memory) == VkResult.VK_SUCCESS, "vkAllocateMemory failed.");
        enforce(vkBindBufferMemory(device.handle, resource.buffer, resource.memory, 0) == VkResult.VK_SUCCESS, "vkBindBufferMemory failed.");

        enforce(vkMapMemory(device.handle, resource.memory, 0, size, 0, &resource.mapped) == VkResult.VK_SUCCESS, "vkMapMemory failed.");
    }

    private void destroyBuffer(ref BufferResource resource)
    {
        if (resource.mapped !is null)
        {
            vkUnmapMemory(device.handle, resource.memory);
            resource.mapped = null;
        }

        if (resource.buffer != VK_NULL_HANDLE)
        {
            vkDestroyBuffer(device.handle, resource.buffer, null);
            resource.buffer = VK_NULL_HANDLE;
        }

        if (resource.memory != VK_NULL_HANDLE)
        {
            vkFreeMemory(device.handle, resource.memory, null);
            resource.memory = VK_NULL_HANDLE;
        }
    }

    private uint findMemoryType(uint typeFilter, VkMemoryPropertyFlags properties)
    {
        VkPhysicalDeviceMemoryProperties memoryProperties;
        vkGetPhysicalDeviceMemoryProperties(device.physicalDevice, &memoryProperties);

        foreach (index; 0 .. memoryProperties.memoryTypeCount)
        {
            if ((typeFilter & (1u << index)) != 0 && (memoryProperties.memoryTypes[index].propertyFlags & properties) == properties)
                return index;
        }

        enforce(false, "No compatible Vulkan memory type found.");
        return 0;
    }
}
