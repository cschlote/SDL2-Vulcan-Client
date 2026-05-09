/** Main Vulkan renderer that owns the scene buffers, swapchain resources, and HUD overlay.
 *
 * The renderer keeps the 3D scene in the background and uploads a separate
 * screen-space overlay each frame so the native-resolution UI stays sharp.
 */
module vulkan.renderer;

import bindbc.sdl : SDL_Delay, SDL_Event, SDL_EventType, SDL_GetError, SDL_GetTicks, SDL_PollEvent, SDL_Scancode, SDL_Vulkan_DestroySurface;
import bindbc.vulkan;
import core.stdc.string : memcpy;
import std.exception : enforce;
import std.format : format;
import std.math : PI, cos, sin;
import std.string : fromStringz;

import vulkan.hud : buildHudOverlayVertices;
import math.matrix;
import window;
import vulkan.device;
import vulkan.instance;
import vulkan.polyhedra : MeshData, buildPlatonicSolids;
import vulkan.pipeline;
import vulkan.swapchain;

private enum maxFramesInFlight = 2;

private enum RenderMode
{
    flatColor,
    litTextured,
    wireframe,
    hiddenLine,
}

private struct SceneUniforms
{
    /** XYZ light direction with the active render mode encoded in `w`. */
    float[4] lightDirectionMode;
    /** Lighting and specular parameters used by the fragment shader. */
    float[4] shadingParams;
}

private struct TextureResource
{
    /** Vulkan image that stores the sampled texture data. */
    VkImage image = VK_NULL_HANDLE;
    /** Device memory backing the texture image. */
    VkDeviceMemory memory = VK_NULL_HANDLE;
    /** Image view used for shader sampling. */
    VkImageView imageView = VK_NULL_HANDLE;
    /** Sampler state bound to the fragment shader. */
    VkSampler sampler = VK_NULL_HANDLE;
}

private struct BufferResource
{
    /** Vulkan buffer handle. */
    VkBuffer buffer = VK_NULL_HANDLE;
    /** Device memory backing the buffer. */
    VkDeviceMemory memory = VK_NULL_HANDLE;
    /** Persistently mapped pointer when the buffer stays mapped. */
    void* mapped = null;
}

/** Owns the full renderer pipeline, scene state, and frame resources. */
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

    private MeshData[] shapeMeshes;
    private size_t currentShapeIndex;
    private string currentShapeName;
    private RenderMode currentRenderMode = RenderMode.litTextured;
    private string currentRenderModeName = "LIT TEXTURED";
    private uint currentIndexCount;
    private size_t maxShapeVertexCount;
    private size_t maxShapeIndexCount;
    private BufferResource meshVertexBuffer;
    private BufferResource meshIndexBuffer;
    private enum maxOverlayVertices = 32_768;
    private BufferResource[maxFramesInFlight] overlayVertexBuffers;
    private uint[maxFramesInFlight] overlayVertexCounts;
    private BufferResource[maxFramesInFlight] uniformBuffers;
    private VkDescriptorPool descriptorPool = VK_NULL_HANDLE;
    private VkDescriptorSet[maxFramesInFlight] descriptorSets;
    private TextureResource texture;
    private enum textureWidth = 64;
    private enum textureHeight = 64;

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
    private double fpsValue;
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

    /** Creates the full renderer stack for the current SDL window and build version.
     *
     * The constructor initializes Vulkan, creates the swapchain and pipelines,
     * and allocates the per-frame resources used for both the 3D scene and
     * the overlay UI.
     */
    ///
    /// Params:
    ///   window = SDL window used for surface creation and size queries.
    ///   buildVersion = Git describe string used in the window title.
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

        shapeMeshes = buildPlatonicSolids();
        currentShapeIndex = 1;
        currentShapeName = shapeMeshes[currentShapeIndex].name;
        currentIndexCount = cast(uint)shapeMeshes[currentShapeIndex].indices.length;
        foreach (mesh; shapeMeshes)
        {
            if (mesh.vertices.length > maxShapeVertexCount)
                maxShapeVertexCount = mesh.vertices.length;
            if (mesh.indices.length > maxShapeIndexCount)
                maxShapeIndexCount = mesh.indices.length;
        }

        createCommandPool();
        createDepthResources();
        createGeometryBuffers();
        createOverlayBuffers();
        createTextureResources();
        createUniformBuffers();
        createDescriptorPoolAndSets();
        createFramebuffers();
        allocateCommandBuffers();
        createSyncObjects();

        updateWindowTitle();
        lastRotationTicks = SDL_GetTicks();
        fpsStartTicks = SDL_GetTicks();
    }

    /** Destroys all renderer-owned Vulkan resources and the SDL surface. */
    void destroy()
    {
        if (device.handle != VK_NULL_HANDLE)
            vkDeviceWaitIdle(device.handle);

        destroySyncObjects();
        destroyDescriptors();
        destroyTextureResources();
        destroyOverlayBuffers();
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

    /** Runs the SDL event loop and renders frames until the application quits. */
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

    /// Handles a single SDL event and updates renderer state.
    ///
    /// Params:
    ///   event = SDL event to process.
    /// Returns: `true` when the event requests shutdown, otherwise `false`.
    bool handleEvent(ref SDL_Event event)
    {
        switch (event.type)
        {
            case SDL_EventType.quit:
                return true;
            case SDL_EventType.keyDown:
                if (event.key.scancode == SDL_Scancode.escape)
                    return true;
                if (!event.key.repeat && (event.key.scancode == SDL_Scancode.equals || event.key.scancode == SDL_Scancode.kpPlus))
                    advanceShape(1);
                else if (!event.key.repeat && (event.key.scancode == SDL_Scancode.minus || event.key.scancode == SDL_Scancode.kpMinus))
                    advanceShape(-1);
                else if (!event.key.repeat && event.key.scancode == SDL_Scancode.f)
                    setRenderMode(RenderMode.flatColor);
                else if (!event.key.repeat && event.key.scancode == SDL_Scancode.t)
                    setRenderMode(RenderMode.litTextured);
                else if (!event.key.repeat && event.key.scancode == SDL_Scancode.w)
                    setRenderMode(RenderMode.wireframe);
                else if (!event.key.repeat && event.key.scancode == SDL_Scancode.h)
                    setRenderMode(RenderMode.hiddenLine);
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

    /// Acquires a swapchain image, updates buffers, submits rendering work, and presents the frame.
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
            fpsValue = fps;
            updateWindowTitle();
            fpsStartTicks = now;
            frameCounter = 0;
        }
    }

    /// Recreates the swapchain and dependent resources after a resize or out-of-date presentation.
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

    /// Creates the Vulkan command pool used for per-frame command buffers.
    private void createCommandPool()
    {
        VkCommandPoolCreateInfo createInfo;
        createInfo.sType = VkStructureType.VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO;
        createInfo.flags = VkCommandPoolCreateFlagBits.VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT;
        createInfo.queueFamilyIndex = device.queueFamilies.graphicsFamily;

        enforce(vkCreateCommandPool(device.handle, &createInfo, null, &commandPool) == VkResult.VK_SUCCESS, "vkCreateCommandPool failed.");
    }

    /// Destroys the command pool if it is still alive.
    private void destroyCommandPool()
    {
        if (commandPool != VK_NULL_HANDLE)
        {
            vkDestroyCommandPool(device.handle, commandPool, null);
            commandPool = VK_NULL_HANDLE;
        }
    }

    /// Allocates one primary command buffer per swapchain image.
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

    /// Frees all allocated command buffers.
    private void destroyCommandBuffers()
    {
        if (commandBuffers.length > 0 && commandPool != VK_NULL_HANDLE)
        {
            vkFreeCommandBuffers(device.handle, commandPool, cast(uint)commandBuffers.length, commandBuffers.ptr);
            commandBuffers.length = 0;
        }
    }

    /// Allocates the vertex and index buffers used by the current polyhedron mesh.
    private void createGeometryBuffers()
    {
        createBuffer(meshVertexBuffer, maxShapeVertexCount * Vertex.sizeof, VkBufferUsageFlagBits.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT);
        createBuffer(meshIndexBuffer, maxShapeIndexCount * uint.sizeof, VkBufferUsageFlagBits.VK_BUFFER_USAGE_INDEX_BUFFER_BIT);
    }

    /// Allocates the per-frame vertex buffers used by the HUD overlay.
    private void createOverlayBuffers()
    {
        foreach (frameIndex; 0 .. maxFramesInFlight)
        {
            createBuffer(overlayVertexBuffers[frameIndex], maxOverlayVertices * Vertex.sizeof, VkBufferUsageFlagBits.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT);
        }
    }

    private void createTextureResources()
    {
        auto textureData = buildCheckerboardTextureData();

        BufferResource stagingBuffer;
        createBuffer(stagingBuffer, textureData, VkBufferUsageFlagBits.VK_BUFFER_USAGE_TRANSFER_SRC_BIT);
        scope (exit)
            destroyBuffer(stagingBuffer);

        VkImageCreateInfo imageInfo;
        imageInfo.sType = VkStructureType.VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO;
        imageInfo.imageType = VkImageType.VK_IMAGE_TYPE_2D;
        imageInfo.format = VkFormat.VK_FORMAT_R8G8B8A8_UNORM;
        imageInfo.extent.width = textureWidth;
        imageInfo.extent.height = textureHeight;
        imageInfo.extent.depth = 1;
        imageInfo.mipLevels = 1;
        imageInfo.arrayLayers = 1;
        imageInfo.samples = VkSampleCountFlagBits.VK_SAMPLE_COUNT_1_BIT;
        imageInfo.tiling = VkImageTiling.VK_IMAGE_TILING_OPTIMAL;
        imageInfo.usage = VkImageUsageFlagBits.VK_IMAGE_USAGE_TRANSFER_DST_BIT | VkImageUsageFlagBits.VK_IMAGE_USAGE_SAMPLED_BIT;
        imageInfo.sharingMode = VkSharingMode.VK_SHARING_MODE_EXCLUSIVE;
        imageInfo.initialLayout = VkImageLayout.VK_IMAGE_LAYOUT_UNDEFINED;

        enforce(vkCreateImage(device.handle, &imageInfo, null, &texture.image) == VkResult.VK_SUCCESS, "vkCreateImage for texture failed.");

        VkMemoryRequirements memoryRequirements;
        vkGetImageMemoryRequirements(device.handle, texture.image, &memoryRequirements);

        VkMemoryAllocateInfo allocateInfo;
        allocateInfo.sType = VkStructureType.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
        allocateInfo.allocationSize = memoryRequirements.size;
        allocateInfo.memoryTypeIndex = findMemoryType(memoryRequirements.memoryTypeBits, VkMemoryPropertyFlagBits.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT);

        enforce(vkAllocateMemory(device.handle, &allocateInfo, null, &texture.memory) == VkResult.VK_SUCCESS, "vkAllocateMemory for texture failed.");
        enforce(vkBindImageMemory(device.handle, texture.image, texture.memory, 0) == VkResult.VK_SUCCESS, "vkBindImageMemory for texture failed.");

        transitionImageLayout(texture.image, VkImageLayout.VK_IMAGE_LAYOUT_UNDEFINED, VkImageLayout.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, VkImageAspectFlagBits.VK_IMAGE_ASPECT_COLOR_BIT);
        copyBufferToImage(stagingBuffer.buffer, texture.image, textureWidth, textureHeight);
        transitionImageLayout(texture.image, VkImageLayout.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, VkImageLayout.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL, VkImageAspectFlagBits.VK_IMAGE_ASPECT_COLOR_BIT);

        VkImageViewCreateInfo viewInfo;
        viewInfo.sType = VkStructureType.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO;
        viewInfo.image = texture.image;
        viewInfo.viewType = VkImageViewType.VK_IMAGE_VIEW_TYPE_2D;
        viewInfo.format = VkFormat.VK_FORMAT_R8G8B8A8_UNORM;
        viewInfo.subresourceRange.aspectMask = VkImageAspectFlagBits.VK_IMAGE_ASPECT_COLOR_BIT;
        viewInfo.subresourceRange.baseMipLevel = 0;
        viewInfo.subresourceRange.levelCount = 1;
        viewInfo.subresourceRange.baseArrayLayer = 0;
        viewInfo.subresourceRange.layerCount = 1;
        enforce(vkCreateImageView(device.handle, &viewInfo, null, &texture.imageView) == VkResult.VK_SUCCESS, "vkCreateImageView for texture failed.");

        VkSamplerCreateInfo samplerInfo;
        samplerInfo.sType = VkStructureType.VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO;
        samplerInfo.magFilter = VkFilter.VK_FILTER_LINEAR;
        samplerInfo.minFilter = VkFilter.VK_FILTER_LINEAR;
        samplerInfo.addressModeU = VkSamplerAddressMode.VK_SAMPLER_ADDRESS_MODE_REPEAT;
        samplerInfo.addressModeV = VkSamplerAddressMode.VK_SAMPLER_ADDRESS_MODE_REPEAT;
        samplerInfo.addressModeW = VkSamplerAddressMode.VK_SAMPLER_ADDRESS_MODE_REPEAT;
        samplerInfo.anisotropyEnable = VK_FALSE;
        samplerInfo.maxAnisotropy = 1.0f;
        samplerInfo.borderColor = VkBorderColor.VK_BORDER_COLOR_INT_OPAQUE_BLACK;
        samplerInfo.unnormalizedCoordinates = VK_FALSE;
        samplerInfo.compareEnable = VK_FALSE;
        samplerInfo.mipmapMode = VkSamplerMipmapMode.VK_SAMPLER_MIPMAP_MODE_LINEAR;
        samplerInfo.mipLodBias = 0.0f;
        samplerInfo.minLod = 0.0f;
        samplerInfo.maxLod = 0.0f;
        enforce(vkCreateSampler(device.handle, &samplerInfo, null, &texture.sampler) == VkResult.VK_SUCCESS, "vkCreateSampler failed.");
    }

    /// Releases the scene geometry buffers.
    private void destroyGeometryBuffers()
    {
        destroyBuffer(meshVertexBuffer);
        destroyBuffer(meshIndexBuffer);
    }

    /// Releases the HUD overlay buffers.
    private void destroyOverlayBuffers()
    {
        foreach (frameIndex; 0 .. maxFramesInFlight)
            destroyBuffer(overlayVertexBuffers[frameIndex]);
    }

    private void destroyTextureResources()
    {
        if (texture.sampler != VK_NULL_HANDLE)
        {
            vkDestroySampler(device.handle, texture.sampler, null);
            texture.sampler = VK_NULL_HANDLE;
        }

        if (texture.imageView != VK_NULL_HANDLE)
        {
            vkDestroyImageView(device.handle, texture.imageView, null);
            texture.imageView = VK_NULL_HANDLE;
        }

        if (texture.image != VK_NULL_HANDLE)
        {
            vkDestroyImage(device.handle, texture.image, null);
            texture.image = VK_NULL_HANDLE;
        }

        if (texture.memory != VK_NULL_HANDLE)
        {
            vkFreeMemory(device.handle, texture.memory, null);
            texture.memory = VK_NULL_HANDLE;
        }
    }

    /// Allocates the per-frame uniform buffers used for the 3D scene.
    private void createUniformBuffers()
    {
        foreach (frameIndex; 0 .. maxFramesInFlight)
        {
            createBuffer(uniformBuffers[frameIndex], SceneUniforms.sizeof, VkBufferUsageFlagBits.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT);
        }
    }

    /// Creates the descriptor pool and descriptor sets for the uniform buffers.
    private void createDescriptorPoolAndSets()
    {
        VkDescriptorPoolSize[2] poolSizes;
        poolSizes[0].type = VkDescriptorType.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER;
        poolSizes[0].descriptorCount = maxFramesInFlight;
        poolSizes[1].type = VkDescriptorType.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER;
        poolSizes[1].descriptorCount = maxFramesInFlight;

        VkDescriptorPoolCreateInfo poolInfo;
        poolInfo.sType = VkStructureType.VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO;
        poolInfo.poolSizeCount = cast(uint)poolSizes.length;
        poolInfo.pPoolSizes = poolSizes.ptr;
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
            bufferInfo.range = SceneUniforms.sizeof;

            VkDescriptorImageInfo imageInfo;
            imageInfo.sampler = texture.sampler;
            imageInfo.imageView = texture.imageView;
            imageInfo.imageLayout = VkImageLayout.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;

            VkWriteDescriptorSet[2] writes;
            writes[0].sType = VkStructureType.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
            writes[0].dstSet = descriptorSets[frameIndex];
            writes[0].dstBinding = 0;
            writes[0].dstArrayElement = 0;
            writes[0].descriptorType = VkDescriptorType.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER;
            writes[0].descriptorCount = 1;
            writes[0].pBufferInfo = &bufferInfo;

            writes[1].sType = VkStructureType.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
            writes[1].dstSet = descriptorSets[frameIndex];
            writes[1].dstBinding = 1;
            writes[1].dstArrayElement = 0;
            writes[1].descriptorType = VkDescriptorType.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER;
            writes[1].descriptorCount = 1;
            writes[1].pImageInfo = &imageInfo;

            vkUpdateDescriptorSets(device.handle, cast(uint)writes.length, writes.ptr, 0, null);
        }
    }

    /// Releases the descriptor pool and uniform buffers.
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

    /// Creates one framebuffer per swapchain image view.
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

    /// Destroys the framebuffers created for the swapchain images.
    private void destroyFramebuffers()
    {
        foreach (framebuffer; framebuffers)
        {
            if (framebuffer != VK_NULL_HANDLE)
                vkDestroyFramebuffer(device.handle, framebuffer, null);
        }
        framebuffers.length = 0;
    }

    /// Creates the depth attachment image, image view, and backing memory.
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

    /// Releases the depth attachment image, image view, and backing memory.
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

    /// Creates the per-frame semaphores and fences used for frame submission.
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

    /// Destroys the semaphores and fences used for frame submission.
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

    /// Updates the current mesh transform, uniform buffer, and HUD vertex data.
    ///
    /// Params:
    ///   frameIndex = Index of the current in-flight frame.
    private void updateGeometryBuffer(size_t frameIndex)
    {
        SceneUniforms uniforms;
        uniforms.lightDirectionMode = [0.35f, 0.72f, 1.0f, currentRenderMode == RenderMode.flatColor ? 0.0f : 1.0f];
        uniforms.shadingParams = [0.18f, 0.82f, 0.22f, 18.0f];
        memcpy(uniformBuffers[frameIndex].mapped, &uniforms, SceneUniforms.sizeof);

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

        const mesh = shapeMeshes[currentShapeIndex];
        currentIndexCount = cast(uint)mesh.indices.length;

        Vertex[] meshTransformed;
        meshTransformed.length = mesh.vertices.length;
        const cy = cos(yawAngle);
        const sy = sin(yawAngle);
        const cx = cos(pitchAngle);
        const sx = sin(pitchAngle);
        foreach (index, source; mesh.vertices)
        {
            const scaleFactor = 0.58f;
            const x = source.position[0] * scaleFactor;
            const y = source.position[1] * scaleFactor;
            const z = source.position[2] * scaleFactor;

            const rotatedX = x * cy + z * sy;
            const rotatedZ = -x * sy + z * cy;
            const rotatedY = y * cx - rotatedZ * sx;
            const rotatedDepth = y * sx + rotatedZ * cx;
            const cameraDistance = 2.8f;
            const perspective = cameraDistance / (cameraDistance - rotatedDepth);

            const screenX = rotatedX * 0.56f * perspective * cast(float)swapchain.extent.height / cast(float)swapchain.extent.width;
            const screenY = rotatedY * 0.56f * perspective;

            const normalX = source.normal[0];
            const normalY = source.normal[1];
            const normalZ = source.normal[2];
            const rotatedNormalX = normalX * cy + normalZ * sy;
            const rotatedNormalZ = -normalX * sy + normalZ * cy;
            const rotatedNormalY = normalY * cx - rotatedNormalZ * sx;
            const finalNormalZ = normalY * sx + rotatedNormalZ * cx;

            meshTransformed[index] = Vertex([screenX, screenY, 0.5f - rotatedDepth * 0.18f], source.color, [rotatedNormalX, rotatedNormalY, finalNormalZ], source.uv);
        }

        memcpy(meshVertexBuffer.mapped, meshTransformed.ptr, Vertex.sizeof * meshTransformed.length);
        memcpy(meshIndexBuffer.mapped, mesh.indices.ptr, uint.sizeof * mesh.indices.length);

        auto overlayVertices = buildHudOverlayVertices(cast(float)swapchain.extent.width, cast(float)swapchain.extent.height, cast(float)fpsValue, yawAngle, pitchAngle, currentShapeName, currentRenderModeName);
        enforce(overlayVertices.length <= maxOverlayVertices, "HUD overlay vertex limit exceeded.");
        overlayVertexCounts[frameIndex] = cast(uint)overlayVertices.length;
        memcpy(overlayVertexBuffers[frameIndex].mapped, overlayVertices.ptr, Vertex.sizeof * overlayVertices.length);
    }

    /// Records the render pass commands for the current frame.
    ///
    /// Params:
    ///   commandBuffer = Command buffer to record into.
    ///   imageIndex = Swapchain image index that is being rendered.
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

        VkBuffer[1] meshVertexBuffers = [meshVertexBuffer.buffer];
        VkDeviceSize[1] offsets = [0];
        vkCmdBindDescriptorSets(commandBuffer, VkPipelineBindPoint.VK_PIPELINE_BIND_POINT_GRAPHICS, pipeline.pipelineLayout, 0, 1, &descriptorSets[currentFrame], 0, null);

        if (currentRenderMode != RenderMode.wireframe)
        {
            vkCmdBindPipeline(commandBuffer, VkPipelineBindPoint.VK_PIPELINE_BIND_POINT_GRAPHICS, pipeline.graphicsPipeline);
            vkCmdBindVertexBuffers(commandBuffer, 0, 1, meshVertexBuffers.ptr, offsets.ptr);
            vkCmdBindIndexBuffer(commandBuffer, meshIndexBuffer.buffer, 0, VkIndexType.VK_INDEX_TYPE_UINT32);
            vkCmdDrawIndexed(commandBuffer, currentIndexCount, 1, 0, 0, 0);
        }

        if (currentRenderMode == RenderMode.wireframe || currentRenderMode == RenderMode.hiddenLine)
        {
            vkCmdBindPipeline(commandBuffer, VkPipelineBindPoint.VK_PIPELINE_BIND_POINT_GRAPHICS, pipeline.wireframePipeline);
            vkCmdBindVertexBuffers(commandBuffer, 0, 1, meshVertexBuffers.ptr, offsets.ptr);
            vkCmdBindIndexBuffer(commandBuffer, meshIndexBuffer.buffer, 0, VkIndexType.VK_INDEX_TYPE_UINT32);
            vkCmdDrawIndexed(commandBuffer, currentIndexCount, 1, 0, 0, 0);
        }

        const overlayCount = overlayVertexCounts[currentFrame];
        if (overlayCount > 0)
        {
            VkBuffer[1] overlayVertexBufferHandles = [overlayVertexBuffers[currentFrame].buffer];
            vkCmdBindPipeline(commandBuffer, VkPipelineBindPoint.VK_PIPELINE_BIND_POINT_GRAPHICS, pipeline.overlayPipeline);
            vkCmdBindVertexBuffers(commandBuffer, 0, 1, overlayVertexBufferHandles.ptr, offsets.ptr);
            vkCmdDraw(commandBuffer, overlayCount, 1, 0, 0);
        }

        vkCmdEndRenderPass(commandBuffer);
        enforce(vkEndCommandBuffer(commandBuffer) == VkResult.VK_SUCCESS, "vkEndCommandBuffer failed.");
    }

    /// Inserts a pipeline barrier that transitions an image layout.
    ///
    /// Params:
    ///   image = Image to transition.
    ///   oldLayout = Previous image layout.
    ///   newLayout = Target image layout.
    ///   aspectMask = Image aspect mask to apply.
    private void transitionImageLayout(VkImage image, VkImageLayout oldLayout, VkImageLayout newLayout, VkImageAspectFlags aspectMask = VkImageAspectFlagBits.VK_IMAGE_ASPECT_DEPTH_BIT)
    {
        VkCommandBuffer commandBuffer = beginSingleTimeCommands();

        VkImageMemoryBarrier barrier;
        barrier.sType = VkStructureType.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER;
        barrier.oldLayout = oldLayout;
        barrier.newLayout = newLayout;
        barrier.srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
        barrier.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
        barrier.image = image;
        barrier.subresourceRange.aspectMask = aspectMask;
        barrier.subresourceRange.baseMipLevel = 0;
        barrier.subresourceRange.levelCount = 1;
        barrier.subresourceRange.baseArrayLayer = 0;
        barrier.subresourceRange.layerCount = 1;

        VkPipelineStageFlags sourceStage = VkPipelineStageFlagBits.VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT;
        VkPipelineStageFlags destinationStage = VkPipelineStageFlagBits.VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT;
        if (newLayout == VkImageLayout.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL)
        {
            destinationStage = VkPipelineStageFlagBits.VK_PIPELINE_STAGE_TRANSFER_BIT;
        }
        if (newLayout == VkImageLayout.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL)
        {
            sourceStage = VkPipelineStageFlagBits.VK_PIPELINE_STAGE_TRANSFER_BIT;
            destinationStage = VkPipelineStageFlagBits.VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT;
        }

        vkCmdPipelineBarrier(commandBuffer, sourceStage, destinationStage, 0, 0, null, 0, null, 1, &barrier);
        endSingleTimeCommands(commandBuffer);
    }

    /// Allocates and begins a one-time-use command buffer.
    ///
    /// Returns: The begun command buffer.
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

    /// Ends, submits, waits for, and frees a one-time-use command buffer.
    ///
    /// Params:
    ///   commandBuffer = Command buffer to submit and free.
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

    private void copyBufferToImage(VkBuffer buffer, VkImage image, uint width, uint height)
    {
        VkCommandBuffer commandBuffer = beginSingleTimeCommands();

        VkBufferImageCopy region;
        region.bufferOffset = 0;
        region.bufferRowLength = 0;
        region.bufferImageHeight = 0;
        region.imageSubresource.aspectMask = VkImageAspectFlagBits.VK_IMAGE_ASPECT_COLOR_BIT;
        region.imageSubresource.mipLevel = 0;
        region.imageSubresource.baseArrayLayer = 0;
        region.imageSubresource.layerCount = 1;
        region.imageOffset.x = 0;
        region.imageOffset.y = 0;
        region.imageOffset.z = 0;
        region.imageExtent.width = width;
        region.imageExtent.height = height;
        region.imageExtent.depth = 1;

        vkCmdCopyBufferToImage(commandBuffer, buffer, image, VkImageLayout.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &region);
        endSingleTimeCommands(commandBuffer);
    }

    private ubyte[] buildCheckerboardTextureData()
    {
        ubyte[] data;
        data.length = textureWidth * textureHeight * 4;
        foreach (y; 0 .. textureHeight)
        {
            foreach (x; 0 .. textureWidth)
            {
                const cell = ((x / 8) + (y / 8)) % 2;
                const base = (y * textureWidth + x) * 4;
                data[base + 0] = cell == 0 ? cast(ubyte)42 : cast(ubyte)218;
                data[base + 1] = cell == 0 ? cast(ubyte)78 : cast(ubyte)198;
                data[base + 2] = cell == 0 ? cast(ubyte)168 : cast(ubyte)248;
                data[base + 3] = 255;
            }
        }

        return data;
    }

    /// Advances or reverses the selected polyhedron and updates the window title.
    ///
    /// Params:
    ///   direction = Positive for the next shape and negative for the previous shape.
    private void advanceShape(int direction)
    {
        if (shapeMeshes.length == 0)
            return;

        const shapeCount = shapeMeshes.length;
        if (direction > 0)
            currentShapeIndex = (currentShapeIndex + 1) % shapeCount;
        else if (currentShapeIndex == 0)
            currentShapeIndex = shapeCount - 1;
        else
            currentShapeIndex -= 1;

        currentShapeName = shapeMeshes[currentShapeIndex].name;
        currentIndexCount = cast(uint)shapeMeshes[currentShapeIndex].indices.length;
        updateWindowTitle();
    }

    private void setRenderMode(RenderMode mode)
    {
        currentRenderMode = mode;
        currentRenderModeName = renderModeLabel(mode);
        updateWindowTitle();
    }

    private static string renderModeLabel(RenderMode mode)
    {
        final switch (mode)
        {
            case RenderMode.flatColor: return "FLAT COLOR";
            case RenderMode.litTextured: return "LIT TEXTURED";
            case RenderMode.wireframe: return "WIREFRAME";
            case RenderMode.hiddenLine: return "HIDDEN LINE";
        }
    }

    /// Rebuilds the window title from the build version, shape name, and FPS value.
    private void updateWindowTitle()
    {
        if (fpsValue > 0)
            window.setTitle(format("%s - %s - %s - %.0f FPS", baseTitle, currentShapeName, currentRenderModeName, fpsValue));
        else
            window.setTitle(format("%s - %s - %s", baseTitle, currentShapeName, currentRenderModeName));
    }

    /// Creates and maps a host-visible Vulkan buffer from initial data.
    ///
    /// Params:
    ///   resource = Receives the buffer, memory, and mapped pointer.
    ///   data = Initial contents copied into the mapped buffer.
    ///   usage = Vulkan buffer usage flags.
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

    /// Creates and maps a host-visible Vulkan buffer of the requested size.
    ///
    /// Params:
    ///   resource = Receives the buffer, memory, and mapped pointer.
    ///   size = Buffer size in bytes.
    ///   usage = Vulkan buffer usage flags.
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

    /// Releases a mapped Vulkan buffer together with its memory.
    ///
    /// Params:
    ///   resource = Buffer resource to destroy.
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

    /// Finds a memory type that satisfies the requested property flags.
    ///
    /// Params:
    ///   typeFilter = Bitmask of supported memory types.
    ///   properties = Required memory properties.
    /// Returns: The selected memory type index.
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
