/** Runs the main Vulkan frame loop and scene rendering.
 *
 * Handles input, camera motion, mesh transforms, overlay uploads, and command
 * buffer recording for both the 3D scene and the retained UI layer. See
 * docs/vulkan-quickstart.md for the frame sequence and https://vkguide.dev/
 * for an external Vulkan walkthrough.
 *
 * See_Also:
 *   docs/vulkan-quickstart.md
 *   https://vkguide.dev/
 *
 * Authors: Carsten Schlote, schlote@vahanus.net
 * Copyright: Carsten Schlote, Released under CC-BY-NC-SA 4.0 license, 2018-2026
 * License: CC-BY-NC-SA 4.0
 */
module vulkan.renderer;

import bindbc.sdl : SDL_Delay, SDL_Event, SDL_EventType, SDL_GetError, SDL_GetTicks, SDL_GetModState, SDL_Keymod, SDL_PollEvent, SDL_Scancode, SDL_Vulkan_DestroySurface;
import bindbc.vulkan;
import core.stdc.string : memcpy;
import std.exception : enforce;
import std.format : format;
import std.math : PI, cos, sin, tan;
import std.stdio : writeln;
import std.string : fromStringz;

import vulkan.font : FontAtlas, buildFontAtlas, selectDefaultFontPath;
import vulkan.ui.ui_event : UiPointerEventKind;
import vulkan.ui_layer : HudLayout, HudLayoutState, HudOverlayGeometry, HudWindowDrawRange, buildHudLayout, buildHudOverlayVertices, hudBeginDrag, hudDragTo, hudDispatchCenterWindowPointer, hudDispatchModeButtonDown, hudEndDrag, hudPointInHeader, hudPointInRect;
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

private struct OverlayLayerResources
{
    BufferResource[maxFramesInFlight] vertexBuffers;
    uint[maxFramesInFlight] vertexCounts;
    BufferResource[maxFramesInFlight] uniformBuffers;
    VkDescriptorSet[maxFramesInFlight] descriptorSets;
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
    private TextureResource sceneTexture;
    private FontAtlas[3] fontAtlases;
    private TextureResource[3] fontTextures;
    private OverlayLayerResources overlayPanels;
    private OverlayLayerResources[3] overlayFonts;
    private HudWindowDrawRange[] hudWindowRanges;
    private enum textureWidth = 64;
    private enum textureHeight = 64;
    private enum smallFontPixelHeight = 12;
    private enum mediumFontPixelHeight = 18;
    private enum largeFontPixelHeight = 24;
    private HudLayoutState hudLayoutState;
    private bool sceneMouseDragging;
    private float cameraFieldOfViewY = 55.0f * PI / 180.0f;
    private enum minCameraFieldOfViewY = 28.0f * PI / 180.0f;
    private enum maxCameraFieldOfViewY = 85.0f * PI / 180.0f;
    private enum cameraFovStep = 2.5f * PI / 180.0f;

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
     *
     * Params:
     *   window = SDL window used for surface creation and size queries.
     *   buildVersion = Git describe string used in the window title.
     */
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
        currentShapeIndex = 3;
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
        createFontResources();
        syncHudLayoutState();
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
        destroyFontResources();
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

    /** Handles a single SDL event and updates renderer state.
     *
     * Params:
     *   event = SDL event to process.
     * Returns: `true` when the event requests shutdown, otherwise `false`.
     */
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
            case SDL_EventType.mouseButtonDown:
                return handleMouseButtonDown(event);
            case SDL_EventType.mouseButtonUp:
                return handleMouseButtonUp(event);
            case SDL_EventType.mouseMotion:
                return handleMouseMotion(event);
            case SDL_EventType.mouseWheel:
                return handleMouseWheel(event);
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

    /** Adjusts the camera opening angle when the wheel is used outside the HUD. */
    private bool handleMouseWheel(ref SDL_Event event)
    {
        const layout = buildHudLayout(
            cast(float)swapchain.extent.width,
            cast(float)swapchain.extent.height,
            cast(float)fpsValue,
            yawAngle,
            pitchAngle,
            currentShapeName,
            currentRenderModeName,
            hudLayoutState,
            fontAtlases[0],
            fontAtlases[1],
            fontAtlases[2]);

        const mouseX = event.wheel.mouseX;
        const mouseY = event.wheel.mouseY;
        if (hudPointInRect(layout.status, mouseX, mouseY)
            || hudPointInRect(layout.modes, mouseX, mouseY)
            || hudPointInRect(layout.sample, mouseX, mouseY)
            || hudPointInRect(layout.input, mouseX, mouseY)
            || hudPointInRect(layout.center, mouseX, mouseY))
        {
            return false;
        }

        cameraFieldOfViewY -= event.wheel.y * cameraFovStep;
        if (cameraFieldOfViewY < minCameraFieldOfViewY)
            cameraFieldOfViewY = minCameraFieldOfViewY;
        else if (cameraFieldOfViewY > maxCameraFieldOfViewY)
            cameraFieldOfViewY = maxCameraFieldOfViewY;

        return false;
    }

    /** Acquires a swapchain image, updates buffers, submits rendering work, and presents the frame. */
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
            enforce(vkWaitForFences(device.handle, 1, &imagesInFlight[imageIndex], VK_TRUE, ulong.max) == VkResult.VK_SUCCESS, "vkWaitForFences failed.");

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

    /** Recreates the swapchain and dependent resources after a resize or out-of-date presentation. */
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

    /** Creates the Vulkan command pool used for per-frame command buffers. */
    private void createCommandPool()
    {
        VkCommandPoolCreateInfo createInfo;
        createInfo.sType = VkStructureType.VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO;
        createInfo.flags = VkCommandPoolCreateFlagBits.VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT;
        createInfo.queueFamilyIndex = device.queueFamilies.graphicsFamily;

        enforce(vkCreateCommandPool(device.handle, &createInfo, null, &commandPool) == VkResult.VK_SUCCESS, "vkCreateCommandPool failed.");
    }

    /** Allocates the scene vertex and index buffers. */
    private void createGeometryBuffers()
    {
        createBuffer(meshVertexBuffer, maxShapeVertexCount * Vertex.sizeof, VkBufferUsageFlagBits.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT);
        createBuffer(meshIndexBuffer, maxShapeIndexCount * uint.sizeof, VkBufferUsageFlagBits.VK_BUFFER_USAGE_INDEX_BUFFER_BIT);
    }

    /** Allocates the per-frame vertex buffers used by the HUD overlay. */
    private void createOverlayBuffers()
    {
        createFrameVertexBuffers(overlayPanels);
        foreach (ref fontLayer; overlayFonts)
            createFrameVertexBuffers(fontLayer);
    }

    /** Creates the scene checkerboard texture used by the main 3D pass. */
    private void createTextureResources()
    {
        auto textureData = buildCheckerboardTextureData();
        createTextureResource(sceneTexture, textureData, textureWidth, textureHeight, VkSamplerAddressMode.VK_SAMPLER_ADDRESS_MODE_REPEAT);
    }

    /** Creates one Vulkan texture from raw RGBA pixel data.
     *
     * Params:
     *   resource = Receives the created texture handles.
     *   pixelData = Raw RGBA pixel data.
     *   width = Texture width in pixels.
     *   height = Texture height in pixels.
     *   addressMode = Sampler addressing mode.
     * Returns: Nothing.
     */
    private void createTextureResource(ref TextureResource resource, const(ubyte)[] pixelData, uint width, uint height, VkSamplerAddressMode addressMode = VkSamplerAddressMode.VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE)
    {
        BufferResource stagingBuffer;
        createBuffer(stagingBuffer, pixelData, VkBufferUsageFlagBits.VK_BUFFER_USAGE_TRANSFER_SRC_BIT);
        scope (exit)
            destroyBuffer(stagingBuffer);

        VkImageCreateInfo imageInfo;
        imageInfo.sType = VkStructureType.VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO;
        imageInfo.imageType = VkImageType.VK_IMAGE_TYPE_2D;
        imageInfo.format = VkFormat.VK_FORMAT_R8G8B8A8_UNORM;
        imageInfo.extent.width = width;
        imageInfo.extent.height = height;
        imageInfo.extent.depth = 1;
        imageInfo.mipLevels = 1;
        imageInfo.arrayLayers = 1;
        imageInfo.samples = VkSampleCountFlagBits.VK_SAMPLE_COUNT_1_BIT;
        imageInfo.tiling = VkImageTiling.VK_IMAGE_TILING_OPTIMAL;
        imageInfo.usage = VkImageUsageFlagBits.VK_IMAGE_USAGE_TRANSFER_DST_BIT | VkImageUsageFlagBits.VK_IMAGE_USAGE_SAMPLED_BIT;
        imageInfo.sharingMode = VkSharingMode.VK_SHARING_MODE_EXCLUSIVE;
        imageInfo.initialLayout = VkImageLayout.VK_IMAGE_LAYOUT_UNDEFINED;

        enforce(vkCreateImage(device.handle, &imageInfo, null, &resource.image) == VkResult.VK_SUCCESS, "vkCreateImage for texture failed.");

        VkMemoryRequirements memoryRequirements;
        vkGetImageMemoryRequirements(device.handle, resource.image, &memoryRequirements);

        VkMemoryAllocateInfo allocateInfo;
        allocateInfo.sType = VkStructureType.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
        allocateInfo.allocationSize = memoryRequirements.size;
        allocateInfo.memoryTypeIndex = findMemoryType(memoryRequirements.memoryTypeBits, VkMemoryPropertyFlagBits.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT);

        enforce(vkAllocateMemory(device.handle, &allocateInfo, null, &resource.memory) == VkResult.VK_SUCCESS, "vkAllocateMemory for texture failed.");
        enforce(vkBindImageMemory(device.handle, resource.image, resource.memory, 0) == VkResult.VK_SUCCESS, "vkBindImageMemory for texture failed.");

        transitionImageLayout(resource.image, VkImageLayout.VK_IMAGE_LAYOUT_UNDEFINED, VkImageLayout.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, VkImageAspectFlagBits.VK_IMAGE_ASPECT_COLOR_BIT);
        copyBufferToImage(stagingBuffer.buffer, resource.image, width, height);
        transitionImageLayout(resource.image, VkImageLayout.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, VkImageLayout.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL, VkImageAspectFlagBits.VK_IMAGE_ASPECT_COLOR_BIT);

        VkImageViewCreateInfo viewInfo;
        viewInfo.sType = VkStructureType.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO;
        viewInfo.image = resource.image;
        viewInfo.viewType = VkImageViewType.VK_IMAGE_VIEW_TYPE_2D;
        viewInfo.format = VkFormat.VK_FORMAT_R8G8B8A8_UNORM;
        viewInfo.subresourceRange.aspectMask = VkImageAspectFlagBits.VK_IMAGE_ASPECT_COLOR_BIT;
        viewInfo.subresourceRange.baseMipLevel = 0;
        viewInfo.subresourceRange.levelCount = 1;
        viewInfo.subresourceRange.baseArrayLayer = 0;
        viewInfo.subresourceRange.layerCount = 1;
        enforce(vkCreateImageView(device.handle, &viewInfo, null, &resource.imageView) == VkResult.VK_SUCCESS, "vkCreateImageView for texture failed.");

        VkSamplerCreateInfo samplerInfo;
        samplerInfo.sType = VkStructureType.VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO;
        samplerInfo.magFilter = VkFilter.VK_FILTER_LINEAR;
        samplerInfo.minFilter = VkFilter.VK_FILTER_LINEAR;
        samplerInfo.addressModeU = addressMode;
        samplerInfo.addressModeV = addressMode;
        samplerInfo.addressModeW = addressMode;
        samplerInfo.anisotropyEnable = VK_FALSE;
        samplerInfo.maxAnisotropy = 1.0f;
        samplerInfo.borderColor = VkBorderColor.VK_BORDER_COLOR_INT_OPAQUE_BLACK;
        samplerInfo.unnormalizedCoordinates = VK_FALSE;
        samplerInfo.compareEnable = VK_FALSE;
        samplerInfo.compareOp = VkCompareOp.VK_COMPARE_OP_ALWAYS;
        samplerInfo.mipmapMode = VkSamplerMipmapMode.VK_SAMPLER_MIPMAP_MODE_LINEAR;
        samplerInfo.mipLodBias = 0.0f;
        samplerInfo.minLod = 0.0f;
        samplerInfo.maxLod = 0.0f;
        enforce(vkCreateSampler(device.handle, &samplerInfo, null, &resource.sampler) == VkResult.VK_SUCCESS, "vkCreateSampler failed.");
    }

    /** Releases one Vulkan texture resource.
     *
     * Params:
     *   resource = Texture resource to destroy.
     * Returns: Nothing.
     */
    private void destroyTextureResource(ref TextureResource resource)
    {
        if (resource.sampler != VK_NULL_HANDLE)
        {
            vkDestroySampler(device.handle, resource.sampler, null);
            resource.sampler = VK_NULL_HANDLE;
        }

        if (resource.imageView != VK_NULL_HANDLE)
        {
            vkDestroyImageView(device.handle, resource.imageView, null);
            resource.imageView = VK_NULL_HANDLE;
        }

        if (resource.image != VK_NULL_HANDLE)
        {
            vkDestroyImage(device.handle, resource.image, null);
            resource.image = VK_NULL_HANDLE;
        }

        if (resource.memory != VK_NULL_HANDLE)
        {
            vkFreeMemory(device.handle, resource.memory, null);
            resource.memory = VK_NULL_HANDLE;
        }
    }

    /// Creates the font atlases and Vulkan textures used by the overlay text layers.
    private void createFontResources()
    {
        const fontPath = selectDefaultFontPath();
        fontAtlases[0] = buildFontAtlas(fontPath, smallFontPixelHeight);
        fontAtlases[1] = buildFontAtlas(fontPath, mediumFontPixelHeight);
        fontAtlases[2] = buildFontAtlas(fontPath, largeFontPixelHeight);

        foreach (index, atlas; fontAtlases)
            createTextureResource(fontTextures[index], atlas.pixels, atlas.width, atlas.height);
    }

    /** Releases the scene geometry buffers. */
    private void destroyGeometryBuffers()
    {
        destroyBuffer(meshVertexBuffer);
        destroyBuffer(meshIndexBuffer);
    }

    /** Releases the HUD overlay buffers. */
    private void destroyOverlayBuffers()
    {
        destroyFrameVertexBuffers(overlayPanels);
        foreach (ref fontLayer; overlayFonts)
            destroyFrameVertexBuffers(fontLayer);
    }

    /** Releases the scene texture resources. */
    private void destroyTextureResources()
    {
        destroyTextureResource(sceneTexture);
    }

    /** Releases the font atlas textures. */
    private void destroyFontResources()
    {
        foreach (ref fontTexture; fontTextures)
            destroyTextureResource(fontTexture);
    }

    /** Allocates the per-frame uniform buffers used for the scene and overlay layers. */
    private void createUniformBuffers()
    {
        foreach (frameIndex; 0 .. maxFramesInFlight)
        {
            createBuffer(uniformBuffers[frameIndex], SceneUniforms.sizeof, VkBufferUsageFlagBits.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT);
            createBuffer(overlayPanels.uniformBuffers[frameIndex], SceneUniforms.sizeof, VkBufferUsageFlagBits.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT);
            foreach (ref fontLayer; overlayFonts)
                createBuffer(fontLayer.uniformBuffers[frameIndex], SceneUniforms.sizeof, VkBufferUsageFlagBits.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT);
        }
    }

    /** Creates the descriptor pool and descriptor sets for the scene and all overlay layers. */
    private void createDescriptorPoolAndSets()
    {
        enum descriptorLayerCount = 1 + 1 + fontTextures.length;

        VkDescriptorPoolSize[2] poolSizes;
        poolSizes[0].type = VkDescriptorType.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER;
        poolSizes[0].descriptorCount = maxFramesInFlight * descriptorLayerCount;
        poolSizes[1].type = VkDescriptorType.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER;
        poolSizes[1].descriptorCount = maxFramesInFlight * descriptorLayerCount;

        VkDescriptorPoolCreateInfo poolInfo;
        poolInfo.sType = VkStructureType.VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO;
        poolInfo.poolSizeCount = cast(uint)poolSizes.length;
        poolInfo.pPoolSizes = poolSizes.ptr;
        poolInfo.maxSets = maxFramesInFlight * descriptorLayerCount;

        enforce(vkCreateDescriptorPool(device.handle, &poolInfo, null, &descriptorPool) == VkResult.VK_SUCCESS, "vkCreateDescriptorPool failed.");

        createDescriptorSetsForScene();
        createDescriptorSetsForLayer(overlayPanels, sceneTexture);
        createDescriptorSetsForLayer(overlayFonts[0], fontTextures[0]);
        createDescriptorSetsForLayer(overlayFonts[1], fontTextures[1]);
        createDescriptorSetsForLayer(overlayFonts[2], fontTextures[2]);
    }

    /** Allocates the descriptor sets for the 3D scene pass. */
    private void createDescriptorSetsForScene()
    {
        createDescriptorSets(descriptorSets, uniformBuffers, sceneTexture);
    }

    /** Allocates the descriptor sets for one overlay layer.
     *
     * Params:
     *   layer = Overlay layer to receive descriptor sets.
     *   texture = Texture bound by the layer.
     * Returns: Nothing.
     */
    private void createDescriptorSetsForLayer(ref OverlayLayerResources layer, TextureResource texture)
    {
        createDescriptorSets(layer.descriptorSets, layer.uniformBuffers, texture);
    }

    /** Allocates and writes descriptor sets for a uniform-buffer-plus-texture layer.
     *
     * Params:
     *   targetSets = Destination descriptor-set array.
     *   layerUniformBuffers = Uniform buffers bound by the sets.
     *   texture = Texture bound by the sets.
     * Returns: Nothing.
     */
    private void createDescriptorSets(ref VkDescriptorSet[maxFramesInFlight] targetSets, ref BufferResource[maxFramesInFlight] layerUniformBuffers, TextureResource texture)
    {
        VkDescriptorSetLayout[maxFramesInFlight] layouts;
        layouts[] = pipeline.descriptorSetLayout;

        VkDescriptorSetAllocateInfo allocateInfo;
        allocateInfo.sType = VkStructureType.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO;
        allocateInfo.descriptorPool = descriptorPool;
        allocateInfo.descriptorSetCount = maxFramesInFlight;
        allocateInfo.pSetLayouts = layouts.ptr;

        enforce(vkAllocateDescriptorSets(device.handle, &allocateInfo, targetSets.ptr) == VkResult.VK_SUCCESS, "vkAllocateDescriptorSets failed.");

        foreach (frameIndex; 0 .. maxFramesInFlight)
        {
            VkDescriptorBufferInfo bufferInfo;
            bufferInfo.buffer = layerUniformBuffers[frameIndex].buffer;
            bufferInfo.offset = 0;
            bufferInfo.range = SceneUniforms.sizeof;

            VkDescriptorImageInfo imageInfo;
            imageInfo.sampler = texture.sampler;
            imageInfo.imageView = texture.imageView;
            imageInfo.imageLayout = VkImageLayout.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;

            VkWriteDescriptorSet[2] writes;
            writes[0].sType = VkStructureType.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
            writes[0].dstSet = targetSets[frameIndex];
            writes[0].dstBinding = 0;
            writes[0].descriptorType = VkDescriptorType.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER;
            writes[0].descriptorCount = 1;
            writes[0].pBufferInfo = &bufferInfo;

            writes[1].sType = VkStructureType.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
            writes[1].dstSet = targetSets[frameIndex];
            writes[1].dstBinding = 1;
            writes[1].descriptorType = VkDescriptorType.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER;
            writes[1].descriptorCount = 1;
            writes[1].pImageInfo = &imageInfo;

            vkUpdateDescriptorSets(device.handle, cast(uint)writes.length, writes.ptr, 0, null);
        }
    }

    /** Releases the descriptor pool and all uniform buffers. */
    private void destroyDescriptors()
    {
        foreach (frameIndex; 0 .. maxFramesInFlight)
            destroyBuffer(uniformBuffers[frameIndex]);

        destroyFrameUniformBuffers(overlayPanels);
        foreach (ref fontLayer; overlayFonts)
            destroyFrameUniformBuffers(fontLayer);

        if (descriptorPool != VK_NULL_HANDLE)
        {
            vkDestroyDescriptorPool(device.handle, descriptorPool, null);
            descriptorPool = VK_NULL_HANDLE;
        }
    }

    /** Allocates one command buffer per swapchain image. */
    private void allocateCommandBuffers()
    {
        commandBuffers.length = framebuffers.length;
        imagesInFlight.length = framebuffers.length;
        imagesInFlight[] = VK_NULL_HANDLE;

        VkCommandBufferAllocateInfo allocateInfo;
        allocateInfo.sType = VkStructureType.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO;
        allocateInfo.commandPool = commandPool;
        allocateInfo.level = VkCommandBufferLevel.VK_COMMAND_BUFFER_LEVEL_PRIMARY;
        allocateInfo.commandBufferCount = cast(uint)commandBuffers.length;

        enforce(vkAllocateCommandBuffers(device.handle, &allocateInfo, commandBuffers.ptr) == VkResult.VK_SUCCESS, "vkAllocateCommandBuffers failed.");
    }

    /** Frees the per-frame command buffers. */
    private void destroyCommandBuffers()
    {
        if (commandBuffers.length != 0)
        {
            vkFreeCommandBuffers(device.handle, commandPool, cast(uint)commandBuffers.length, commandBuffers.ptr);
            commandBuffers.length = 0;
        }
    }

    /** Creates one framebuffer per swapchain image view. */
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

    /** Releases the command pool. */
    private void destroyCommandPool()
    {
        if (commandPool != VK_NULL_HANDLE)
        {
            vkDestroyCommandPool(device.handle, commandPool, null);
            commandPool = VK_NULL_HANDLE;
        }
    }

    /** Creates and maps a frame-local vertex buffer for an overlay layer. */
    private void createFrameVertexBuffers(ref OverlayLayerResources layer)
    {
        foreach (frameIndex; 0 .. maxFramesInFlight)
        {
            createBuffer(layer.vertexBuffers[frameIndex], maxOverlayVertices * Vertex.sizeof, VkBufferUsageFlagBits.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT);
            layer.vertexCounts[frameIndex] = 0;
        }
    }

    /** Releases the frame-local vertex buffers for an overlay layer. */
    private void destroyFrameVertexBuffers(ref OverlayLayerResources layer)
    {
        foreach (frameIndex; 0 .. maxFramesInFlight)
            destroyBuffer(layer.vertexBuffers[frameIndex]);
    }

    /** Releases the frame-local uniform buffers for an overlay layer. */
    private void destroyFrameUniformBuffers(ref OverlayLayerResources layer)
    {
        foreach (frameIndex; 0 .. maxFramesInFlight)
            destroyBuffer(layer.uniformBuffers[frameIndex]);
    }

    /** Destroys the framebuffers created for the swapchain images. */
    private void destroyFramebuffers()
    {
        foreach (framebuffer; framebuffers)
        {
            if (framebuffer != VK_NULL_HANDLE)
                vkDestroyFramebuffer(device.handle, framebuffer, null);
        }
        framebuffers.length = 0;
    }

    /** Creates the depth attachment image, image view, and backing memory. */
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

    /** Releases the depth attachment image, image view, and backing memory. */
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

    /** Creates the per-frame semaphores and fences used for frame submission. */
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

    /** Destroys the semaphores and fences used for frame submission. */
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

        SceneUniforms panelUniforms;
        panelUniforms.lightDirectionMode = [0.35f, 0.72f, 1.0f, -1.0f];
        panelUniforms.shadingParams = [0.18f, 0.82f, 0.22f, 18.0f];
        memcpy(overlayPanels.uniformBuffers[frameIndex].mapped, &panelUniforms, SceneUniforms.sizeof);

        SceneUniforms textUniforms;
        textUniforms.lightDirectionMode = [0.35f, 0.72f, 1.0f, -2.0f];
        textUniforms.shadingParams = [0.18f, 0.82f, 0.22f, 18.0f];
        foreach (ref fontLayer; overlayFonts)
            memcpy(fontLayer.uniformBuffers[frameIndex].mapped, &textUniforms, SceneUniforms.sizeof);

        const currentTicks = SDL_GetTicks();
        const elapsedTicks = currentTicks - lastRotationTicks;
        lastRotationTicks = currentTicks;

        const clampedElapsedTicks = elapsedTicks > 50 ? 50 : elapsedTicks;
        const deltaSeconds = cast(float)clampedElapsedTicks / 1_000.0f;
        const rotationSpeed = 0.55f * ((SDL_GetModState() & SDL_Keymod.shift) != 0 ? 3.0f : 1.0f);

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
            const perspective = 1.0f / tan(cameraFieldOfViewY * 0.5f);

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

        auto overlayVertices = buildHudOverlayVertices(
            cast(float)swapchain.extent.width,
            cast(float)swapchain.extent.height,
            cast(float)fpsValue,
            yawAngle,
            pitchAngle,
            currentShapeName,
            currentRenderModeName,
            hudLayoutState,
            fontAtlases[0],
            fontAtlases[1],
            fontAtlases[2]);

        enforce(overlayVertices.panels.length <= maxOverlayVertices, "HUD overlay panel vertex limit exceeded.");
        enforce(overlayVertices.smallText.length <= maxOverlayVertices, "HUD overlay small-text vertex limit exceeded.");
        enforce(overlayVertices.mediumText.length <= maxOverlayVertices, "HUD overlay medium-text vertex limit exceeded.");
        enforce(overlayVertices.largeText.length <= maxOverlayVertices, "HUD overlay large-text vertex limit exceeded.");

        hudWindowRanges = overlayVertices.windows;

        overlayPanels.vertexCounts[frameIndex] = cast(uint)overlayVertices.panels.length;
        memcpy(overlayPanels.vertexBuffers[frameIndex].mapped, overlayVertices.panels.ptr, Vertex.sizeof * overlayVertices.panels.length);

        overlayFonts[0].vertexCounts[frameIndex] = cast(uint)overlayVertices.smallText.length;
        memcpy(overlayFonts[0].vertexBuffers[frameIndex].mapped, overlayVertices.smallText.ptr, Vertex.sizeof * overlayVertices.smallText.length);

        overlayFonts[1].vertexCounts[frameIndex] = cast(uint)overlayVertices.mediumText.length;
        memcpy(overlayFonts[1].vertexBuffers[frameIndex].mapped, overlayVertices.mediumText.ptr, Vertex.sizeof * overlayVertices.mediumText.length);

        overlayFonts[2].vertexCounts[frameIndex] = cast(uint)overlayVertices.largeText.length;
        memcpy(overlayFonts[2].vertexBuffers[frameIndex].mapped, overlayVertices.largeText.ptr, Vertex.sizeof * overlayVertices.largeText.length);
    }

    /// Records the render pass commands for the current frame.

            /** Recomputes the draggable HUD window clamp state for the current swapchain size. */
            private void syncHudLayoutState()
            {
                buildHudLayout(
                    cast(float)swapchain.extent.width,
                    cast(float)swapchain.extent.height,
                    cast(float)fpsValue,
                    yawAngle,
                    pitchAngle,
                    currentShapeName,
                    currentRenderModeName,
                    hudLayoutState,
                    fontAtlases[0],
                    fontAtlases[1],
                    fontAtlases[2]);
            }

            /** Starts a scene drag when a mouse press does not hit the HUD. */
            private bool handleMouseButtonDown(ref SDL_Event event)
            {
                if (event.button.button != 1)
                    return false;

                const layout = buildHudLayout(
                    cast(float)swapchain.extent.width,
                    cast(float)swapchain.extent.height,
                    cast(float)fpsValue,
                    yawAngle,
                    pitchAngle,
                    currentShapeName,
                    currentRenderModeName,
                    hudLayoutState,
                    fontAtlases[0],
                    fontAtlases[1],
                    fontAtlases[2]);

                const mouseX = cast(float)event.button.x;
                const mouseY = cast(float)event.button.y;
                if (hudDispatchModeButtonDown(
                    layout.modes,
                    mouseX,
                    mouseY,
                    fontAtlases[0],
                    { setRenderMode(RenderMode.flatColor); },
                    { setRenderMode(RenderMode.litTextured); },
                    { setRenderMode(RenderMode.wireframe); },
                    { setRenderMode(RenderMode.hiddenLine); }))
                {
                    return false;
                }

                if (hudDispatchCenterWindowPointer(layout.center, hudLayoutState, cast(float)swapchain.extent.width, cast(float)swapchain.extent.height, mouseX, mouseY, UiPointerEventKind.buttonDown, cast(uint)event.button.button, fontAtlases[0], fontAtlases[1]))
                {
                    sceneMouseDragging = false;
                    return false;
                }

                const hitHud = hudPointInRect(layout.status, mouseX, mouseY)
                    || hudPointInRect(layout.modes, mouseX, mouseY)
                    || hudPointInRect(layout.sample, mouseX, mouseY)
                    || hudPointInRect(layout.input, mouseX, mouseY)
                    || hudPointInRect(layout.center, mouseX, mouseY);

                if (hudPointInHeader(layout.center, mouseX, mouseY))
                {
                    hudBeginDrag(hudLayoutState, layout.center, mouseX, mouseY);
                    sceneMouseDragging = false;
                    return false;
                }

                sceneMouseDragging = !hitHud;
                return false;
            }

            /** Ends any active mouse drag when the button is released. */
            private bool handleMouseButtonUp(ref SDL_Event event)
            {
                if (event.button.button != 1)
                    return false;

                const layout = buildHudLayout(
                    cast(float)swapchain.extent.width,
                    cast(float)swapchain.extent.height,
                    cast(float)fpsValue,
                    yawAngle,
                    pitchAngle,
                    currentShapeName,
                    currentRenderModeName,
                    hudLayoutState,
                    fontAtlases[0],
                    fontAtlases[1],
                    fontAtlases[2]);

                if (hudLayoutState.middleDragging)
                {
                    hudDispatchCenterWindowPointer(layout.center, hudLayoutState, cast(float)swapchain.extent.width, cast(float)swapchain.extent.height, cast(float)event.button.x, cast(float)event.button.y, UiPointerEventKind.buttonUp, cast(uint)event.button.button, fontAtlases[0], fontAtlases[1]);
                }

                if (hudLayoutState.middleDragging)
                    hudEndDrag(hudLayoutState);

                sceneMouseDragging = false;
                return false;
            }

            /** Routes mouse motion either to the draggable window or to the 3D layer. */
            private bool handleMouseMotion(ref SDL_Event event)
            {
                if (hudLayoutState.middleDragging)
                {
                    const layout = buildHudLayout(
                        cast(float)swapchain.extent.width,
                        cast(float)swapchain.extent.height,
                        cast(float)fpsValue,
                        yawAngle,
                        pitchAngle,
                        currentShapeName,
                        currentRenderModeName,
                        hudLayoutState,
                        fontAtlases[0],
                        fontAtlases[1],
                        fontAtlases[2]);

                    hudDispatchCenterWindowPointer(layout.center, hudLayoutState, cast(float)swapchain.extent.width, cast(float)swapchain.extent.height, cast(float)event.motion.x, cast(float)event.motion.y, UiPointerEventKind.move, 0, fontAtlases[0], fontAtlases[1]);
                    return false;
                }

                if (sceneMouseDragging)
                {
                    yawAngle += cast(float)event.motion.xrel * 0.006f;
                    pitchAngle += cast(float)event.motion.yrel * 0.006f;
                    if (pitchAngle < -1.40f)
                        pitchAngle = -1.40f;
                    else if (pitchAngle > 1.40f)
                        pitchAngle = 1.40f;
                }

                return false;
            }
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

        foreach (windowRange; hudWindowRanges)
        {
            vkCmdBindPipeline(commandBuffer, VkPipelineBindPoint.VK_PIPELINE_BIND_POINT_GRAPHICS, pipeline.overlayPipeline);
            if (windowRange.panelsCount > 0)
            {
                vkCmdBindDescriptorSets(commandBuffer, VkPipelineBindPoint.VK_PIPELINE_BIND_POINT_GRAPHICS, pipeline.pipelineLayout, 0, 1, &overlayPanels.descriptorSets[currentFrame], 0, null);
                VkBuffer[1] panelVertexBuffers = [overlayPanels.vertexBuffers[currentFrame].buffer];
                vkCmdBindVertexBuffers(commandBuffer, 0, 1, panelVertexBuffers.ptr, offsets.ptr);
                vkCmdDraw(commandBuffer, windowRange.panelsCount, 1, windowRange.panelsStart, 0);
            }

            if (windowRange.smallTextCount > 0)
            {
                vkCmdBindDescriptorSets(commandBuffer, VkPipelineBindPoint.VK_PIPELINE_BIND_POINT_GRAPHICS, pipeline.pipelineLayout, 0, 1, &overlayFonts[0].descriptorSets[currentFrame], 0, null);
                VkBuffer[1] textVertexBuffers = [overlayFonts[0].vertexBuffers[currentFrame].buffer];
                vkCmdBindVertexBuffers(commandBuffer, 0, 1, textVertexBuffers.ptr, offsets.ptr);
                vkCmdDraw(commandBuffer, windowRange.smallTextCount, 1, windowRange.smallTextStart, 0);
            }

            if (windowRange.mediumTextCount > 0)
            {
                vkCmdBindDescriptorSets(commandBuffer, VkPipelineBindPoint.VK_PIPELINE_BIND_POINT_GRAPHICS, pipeline.pipelineLayout, 0, 1, &overlayFonts[1].descriptorSets[currentFrame], 0, null);
                VkBuffer[1] textVertexBuffers = [overlayFonts[1].vertexBuffers[currentFrame].buffer];
                vkCmdBindVertexBuffers(commandBuffer, 0, 1, textVertexBuffers.ptr, offsets.ptr);
                vkCmdDraw(commandBuffer, windowRange.mediumTextCount, 1, windowRange.mediumTextStart, 0);
            }

            if (windowRange.largeTextCount > 0)
            {
                vkCmdBindDescriptorSets(commandBuffer, VkPipelineBindPoint.VK_PIPELINE_BIND_POINT_GRAPHICS, pipeline.pipelineLayout, 0, 1, &overlayFonts[2].descriptorSets[currentFrame], 0, null);
                VkBuffer[1] textVertexBuffers = [overlayFonts[2].vertexBuffers[currentFrame].buffer];
                vkCmdBindVertexBuffers(commandBuffer, 0, 1, textVertexBuffers.ptr, offsets.ptr);
                vkCmdDraw(commandBuffer, windowRange.largeTextCount, 1, windowRange.largeTextStart, 0);
            }
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

    /** Copies a staging buffer into a Vulkan image.
     *
     * Params:
     *   buffer = Source buffer containing the pixel data.
     *   image = Destination Vulkan image.
     *   width = Copy width in pixels.
     *   height = Copy height in pixels.
     * Returns: Nothing.
     */
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

    /** Builds the checkerboard texture used by the main scene material.
     *
     * @returns RGBA pixel data for the generated checkerboard.
     */
    private ubyte[] buildCheckerboardTextureData()
    {
        ubyte[] data;
        data.length = textureWidth * textureHeight * 4;
        enum checkerCellSize = 16;
        enum darkR = 40;
        enum darkG = 48;
        enum darkB = 64;
        enum lightR = 224;
        enum lightG = 228;
        enum lightB = 236;

        foreach (y; 0 .. textureHeight)
        {
            foreach (x; 0 .. textureWidth)
            {
                const cell = ((x / checkerCellSize) + (y / checkerCellSize)) % 2;
                const base = (y * textureWidth + x) * 4;
                data[base + 0] = cell == 0 ? cast(ubyte)darkR : cast(ubyte)lightR;
                data[base + 1] = cell == 0 ? cast(ubyte)darkG : cast(ubyte)lightG;
                data[base + 2] = cell == 0 ? cast(ubyte)darkB : cast(ubyte)lightB;
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

    /** Updates the active render mode and refreshes the window title.
     *
     * Params:
     *   mode = Render mode to activate.
     * Returns: Nothing.
     */
    private void setRenderMode(RenderMode mode)
    {
        currentRenderMode = mode;
        currentRenderModeName = renderModeLabel(mode);
        updateWindowTitle();
    }

    /** Returns the human-readable label for a render mode.
     *
     * Params:
     *   mode = Render mode to describe.
     * Returns: Upper-case render mode label.
     */
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
