/** $purposeofFile
 *
 * Authors: Carsten Schlote, schlote@vahanus.net
 * Copyright: Carsten Schlote, Released under CC-BY-NC-SA 4.0 license, 2018
 * License: CC-BY-NC-SA 4.0
 */
module vulkan.pipeline;

import bindbc.vulkan;
import std.exception : enforce;
import std.file : read;

/** Shared vertex format used by the scene and overlay pipelines. */
struct Vertex
{
    float[3] position;
    float[4] color;
    float[3] normal;
    float[2] uv;

    /** Creates a vertex from RGB color data and adds an implicit opaque alpha channel.
     *
     * @param position = Vertex position in clip-space coordinates.
     * @param color = Vertex color in RGB format.
     * @returns Nothing.
     */
    this(float[3] position, float[3] color, float[3] normal = [0.0f, 0.0f, 1.0f], float[2] uv = [0.0f, 0.0f])
    {
        this.position = position;
        this.color = [color[0], color[1], color[2], 1.0f];
        this.normal = normal;
        this.uv = uv;
    }

    /** Creates a vertex from RGBA color data.
     *
     * @param position = Vertex position in clip-space coordinates.
     * @param color = Vertex color in RGBA format.
     * @returns Nothing.
     */
    this(float[3] position, float[4] color, float[3] normal = [0.0f, 0.0f, 1.0f], float[2] uv = [0.0f, 0.0f])
    {
        this.position = position;
        this.color = color;
        this.normal = normal;
        this.uv = uv;
    }
}

/** Owns the Vulkan render pass, descriptor layout, and scene/overlay pipelines. */
struct PipelineResources
{
    /** Render pass shared by the scene and overlay pipelines. */
    VkRenderPass renderPass = VK_NULL_HANDLE;
    /** Descriptor set layout used for the scene uniforms and texture sampler. */
    VkDescriptorSetLayout descriptorSetLayout = VK_NULL_HANDLE;
    /** Pipeline layout shared by all graphics pipelines. */
    VkPipelineLayout pipelineLayout = VK_NULL_HANDLE;
    /** Main filled 3D scene pipeline. */
    VkPipeline graphicsPipeline = VK_NULL_HANDLE;
    /** Alpha-blended overlay pipeline used for HUD rendering. */
    VkPipeline overlayPipeline = VK_NULL_HANDLE;
    /** Wireframe pipeline used for diagnostic rendering. */
    VkPipeline wireframePipeline = VK_NULL_HANDLE;

    /** Creates the descriptor set layout, render pass, and graphics pipelines.
     *
     * @param device = Logical Vulkan device.
     * @param extent = Swapchain extent used for viewport state.
     * @param colorFormat = Swapchain color format.
     * @param depthFormat = Depth attachment format.
     * @param vertexShaderPath = Path to the vertex shader SPIR-V file.
     * @param fragmentShaderPath = Path to the fragment shader SPIR-V file.
     * @returns Nothing.
     */
    this(VkDevice device, VkExtent2D extent, VkFormat colorFormat, VkFormat depthFormat, string vertexShaderPath, string fragmentShaderPath)
    {
        createDescriptorSetLayout(device);
        createRenderPass(device, colorFormat, depthFormat);
        createGraphicsPipeline(device, extent, vertexShaderPath, fragmentShaderPath, VkPrimitiveTopology.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST, VkPolygonMode.VK_POLYGON_MODE_FILL, true, true, false, false, graphicsPipeline);
        createGraphicsPipeline(device, extent, vertexShaderPath, fragmentShaderPath, VkPrimitiveTopology.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST, VkPolygonMode.VK_POLYGON_MODE_FILL, true, true, false, true, overlayPipeline);
        createGraphicsPipeline(device, extent, vertexShaderPath, fragmentShaderPath, VkPrimitiveTopology.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST, VkPolygonMode.VK_POLYGON_MODE_LINE, false, false, false, false, wireframePipeline);
    }

    /** Releases all pipeline-related Vulkan objects owned by the structure.
     *
     * @param device = Logical Vulkan device that owns the resources.
     * @returns Nothing.
     */
    void destroy(VkDevice device)
    {
        if (graphicsPipeline != VK_NULL_HANDLE)
        {
            vkDestroyPipeline(device, graphicsPipeline, null);
            graphicsPipeline = VK_NULL_HANDLE;
        }

        if (overlayPipeline != VK_NULL_HANDLE)
        {
            vkDestroyPipeline(device, overlayPipeline, null);
            overlayPipeline = VK_NULL_HANDLE;
        }

        if (wireframePipeline != VK_NULL_HANDLE)
        {
            vkDestroyPipeline(device, wireframePipeline, null);
            wireframePipeline = VK_NULL_HANDLE;
        }

        if (pipelineLayout != VK_NULL_HANDLE)
        {
            vkDestroyPipelineLayout(device, pipelineLayout, null);
            pipelineLayout = VK_NULL_HANDLE;
        }

        if (renderPass != VK_NULL_HANDLE)
        {
            vkDestroyRenderPass(device, renderPass, null);
            renderPass = VK_NULL_HANDLE;
        }

        if (descriptorSetLayout != VK_NULL_HANDLE)
        {
            vkDestroyDescriptorSetLayout(device, descriptorSetLayout, null);
            descriptorSetLayout = VK_NULL_HANDLE;
        }
    }

private:
    /** Creates the descriptor set layout used by the renderer's uniform buffer binding.
     *
     * @param device = Logical Vulkan device.
     * @returns Nothing.
     */
    void createDescriptorSetLayout(VkDevice device)
    {
        VkDescriptorSetLayoutBinding[2] bindings;
        bindings[0].binding = 0;
        bindings[0].descriptorType = VkDescriptorType.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER;
        bindings[0].descriptorCount = 1;
        bindings[0].stageFlags = VkShaderStageFlagBits.VK_SHADER_STAGE_VERTEX_BIT | VkShaderStageFlagBits.VK_SHADER_STAGE_FRAGMENT_BIT;

        bindings[1].binding = 1;
        bindings[1].descriptorType = VkDescriptorType.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER;
        bindings[1].descriptorCount = 1;
        bindings[1].stageFlags = VkShaderStageFlagBits.VK_SHADER_STAGE_FRAGMENT_BIT;

        VkDescriptorSetLayoutCreateInfo createInfo;
        createInfo.sType = VkStructureType.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO;
        createInfo.bindingCount = cast(uint)bindings.length;
        createInfo.pBindings = bindings.ptr;

        enforce(vkCreateDescriptorSetLayout(device, &createInfo, null, &descriptorSetLayout) == VkResult.VK_SUCCESS, "vkCreateDescriptorSetLayout failed.");
    }

    /** Creates the render pass with color and depth attachments.
     *
     * @param device = Logical Vulkan device.
     * @param colorFormat = Swapchain color format.
     * @param depthFormat = Depth attachment format.
     * @returns Nothing.
     */
    void createRenderPass(VkDevice device, VkFormat colorFormat, VkFormat depthFormat)
    {
        VkAttachmentDescription[2] attachments;

        attachments[0].format = colorFormat;
        attachments[0].samples = VkSampleCountFlagBits.VK_SAMPLE_COUNT_1_BIT;
        attachments[0].loadOp = VkAttachmentLoadOp.VK_ATTACHMENT_LOAD_OP_CLEAR;
        attachments[0].storeOp = VkAttachmentStoreOp.VK_ATTACHMENT_STORE_OP_STORE;
        attachments[0].stencilLoadOp = VkAttachmentLoadOp.VK_ATTACHMENT_LOAD_OP_DONT_CARE;
        attachments[0].stencilStoreOp = VkAttachmentStoreOp.VK_ATTACHMENT_STORE_OP_DONT_CARE;
        attachments[0].initialLayout = VkImageLayout.VK_IMAGE_LAYOUT_UNDEFINED;
        attachments[0].finalLayout = VkImageLayout.VK_IMAGE_LAYOUT_PRESENT_SRC_KHR;

        attachments[1].format = depthFormat;
        attachments[1].samples = VkSampleCountFlagBits.VK_SAMPLE_COUNT_1_BIT;
        attachments[1].loadOp = VkAttachmentLoadOp.VK_ATTACHMENT_LOAD_OP_CLEAR;
        attachments[1].storeOp = VkAttachmentStoreOp.VK_ATTACHMENT_STORE_OP_DONT_CARE;
        attachments[1].stencilLoadOp = VkAttachmentLoadOp.VK_ATTACHMENT_LOAD_OP_DONT_CARE;
        attachments[1].stencilStoreOp = VkAttachmentStoreOp.VK_ATTACHMENT_STORE_OP_DONT_CARE;
        attachments[1].initialLayout = VkImageLayout.VK_IMAGE_LAYOUT_UNDEFINED;
        attachments[1].finalLayout = VkImageLayout.VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL;

        VkAttachmentReference colorRef;
        colorRef.attachment = 0;
        colorRef.layout = VkImageLayout.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;

        VkAttachmentReference depthRef;
        depthRef.attachment = 1;
        depthRef.layout = VkImageLayout.VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL;

        VkSubpassDescription subpass;
        subpass.pipelineBindPoint = VkPipelineBindPoint.VK_PIPELINE_BIND_POINT_GRAPHICS;
        subpass.colorAttachmentCount = 1;
        subpass.pColorAttachments = &colorRef;
        subpass.pDepthStencilAttachment = &depthRef;

        VkSubpassDependency dependency;
        dependency.srcSubpass = VK_SUBPASS_EXTERNAL;
        dependency.dstSubpass = 0;
        dependency.srcStageMask = VkPipelineStageFlagBits.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT | VkPipelineStageFlagBits.VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT;
        dependency.srcAccessMask = 0;
        dependency.dstStageMask = VkPipelineStageFlagBits.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT | VkPipelineStageFlagBits.VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT;
        dependency.dstAccessMask = VkAccessFlagBits.VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT | VkAccessFlagBits.VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT;

        VkRenderPassCreateInfo createInfo;
        createInfo.sType = VkStructureType.VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO;
        createInfo.attachmentCount = cast(uint)attachments.length;
        createInfo.pAttachments = attachments.ptr;
        createInfo.subpassCount = 1;
        createInfo.pSubpasses = &subpass;
        createInfo.dependencyCount = 1;
        createInfo.pDependencies = &dependency;

        enforce(vkCreateRenderPass(device, &createInfo, null, &renderPass) == VkResult.VK_SUCCESS, "vkCreateRenderPass failed.");
    }

    /** Creates a graphics pipeline with the requested raster and depth state.
     *
     * @param device = Logical Vulkan device.
     * @param extent = Swapchain extent used for viewport state.
     * @param vertexShaderPath = Path to the vertex shader SPIR-V file.
     * @param fragmentShaderPath = Path to the fragment shader SPIR-V file.
     * @param topology = Primitive topology for the pipeline.
     * @param depthTestEnable = Enables depth testing when true.
     * @param depthWriteEnable = Enables depth writes when true.
     * @param depthBiasEnable = Enables depth bias when true.
     * @param blendEnable = Enables alpha blending when true.
     * @param pipeline = Receives the created Vulkan pipeline handle.
     * @returns Nothing.
     */
    void createGraphicsPipeline(VkDevice device, VkExtent2D extent, string vertexShaderPath, string fragmentShaderPath, VkPrimitiveTopology topology, VkPolygonMode polygonMode, bool depthTestEnable, bool depthWriteEnable, bool depthBiasEnable, bool blendEnable, ref VkPipeline pipeline)
    {
        auto vertexShaderCode = cast(ubyte[])read(vertexShaderPath);
        auto fragmentShaderCode = cast(ubyte[])read(fragmentShaderPath);

        VkShaderModule vertexShaderModule = createShaderModule(device, vertexShaderCode);
        scope (exit)
            vkDestroyShaderModule(device, vertexShaderModule, null);

        VkShaderModule fragmentShaderModule = createShaderModule(device, fragmentShaderCode);
        scope (exit)
            vkDestroyShaderModule(device, fragmentShaderModule, null);

        const(char)* entryPoint = "main".ptr;

        VkPipelineShaderStageCreateInfo[2] shaderStages;
        shaderStages[0].sType = VkStructureType.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
        shaderStages[0].stage = VkShaderStageFlagBits.VK_SHADER_STAGE_VERTEX_BIT;
        shaderStages[0].module_ = vertexShaderModule;
        shaderStages[0].pName = entryPoint;

        shaderStages[1].sType = VkStructureType.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
        shaderStages[1].stage = VkShaderStageFlagBits.VK_SHADER_STAGE_FRAGMENT_BIT;
        shaderStages[1].module_ = fragmentShaderModule;
        shaderStages[1].pName = entryPoint;

        VkVertexInputBindingDescription bindingDescription;
        bindingDescription.binding = 0;
        bindingDescription.stride = Vertex.sizeof;
        bindingDescription.inputRate = VkVertexInputRate.VK_VERTEX_INPUT_RATE_VERTEX;

        VkVertexInputAttributeDescription[2] attributes;
        attributes[0].binding = 0;
        attributes[0].location = 0;
        attributes[0].format = VkFormat.VK_FORMAT_R32G32B32_SFLOAT;
        attributes[0].offset = Vertex.position.offsetof;
        attributes[1].binding = 0;
        attributes[1].location = 1;
        attributes[1].format = VkFormat.VK_FORMAT_R32G32B32A32_SFLOAT;
        attributes[1].offset = Vertex.color.offsetof;
        VkVertexInputAttributeDescription[2] extraAttributes;
        extraAttributes[0].binding = 0;
        extraAttributes[0].location = 2;
        extraAttributes[0].format = VkFormat.VK_FORMAT_R32G32B32_SFLOAT;
        extraAttributes[0].offset = Vertex.normal.offsetof;
        extraAttributes[1].binding = 0;
        extraAttributes[1].location = 3;
        extraAttributes[1].format = VkFormat.VK_FORMAT_R32G32_SFLOAT;
        extraAttributes[1].offset = Vertex.uv.offsetof;

        VkVertexInputAttributeDescription[4] allAttributes = [attributes[0], attributes[1], extraAttributes[0], extraAttributes[1]];

        VkPipelineVertexInputStateCreateInfo vertexInputInfo;
        vertexInputInfo.sType = VkStructureType.VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO;
        vertexInputInfo.vertexBindingDescriptionCount = 1;
        vertexInputInfo.pVertexBindingDescriptions = &bindingDescription;
        vertexInputInfo.vertexAttributeDescriptionCount = cast(uint)allAttributes.length;
        vertexInputInfo.pVertexAttributeDescriptions = allAttributes.ptr;

        VkPipelineInputAssemblyStateCreateInfo inputAssembly;
        inputAssembly.sType = VkStructureType.VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO;
        inputAssembly.topology = topology;
        inputAssembly.primitiveRestartEnable = VK_FALSE;

        VkViewport viewport;
        viewport.x = 0;
        viewport.y = 0;
        viewport.width = cast(float)extent.width;
        viewport.height = cast(float)extent.height;
        viewport.minDepth = 0;
        viewport.maxDepth = 1;

        VkRect2D scissor;
        scissor.extent = extent;

        VkPipelineViewportStateCreateInfo viewportState;
        viewportState.sType = VkStructureType.VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO;
        viewportState.viewportCount = 1;
        viewportState.pViewports = &viewport;
        viewportState.scissorCount = 1;
        viewportState.pScissors = &scissor;

        VkPipelineRasterizationStateCreateInfo rasterizer;
        rasterizer.sType = VkStructureType.VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO;
        rasterizer.depthClampEnable = VK_FALSE;
        rasterizer.rasterizerDiscardEnable = VK_FALSE;
        rasterizer.polygonMode = polygonMode;
        rasterizer.lineWidth = 1;
        rasterizer.cullMode = VkCullModeFlagBits.VK_CULL_MODE_NONE;
        rasterizer.frontFace = VkFrontFace.VK_FRONT_FACE_COUNTER_CLOCKWISE;
        rasterizer.depthBiasEnable = depthBiasEnable ? VK_TRUE : VK_FALSE;
        rasterizer.depthBiasConstantFactor = depthBiasEnable ? 1.0f : 0.0f;
        rasterizer.depthBiasClamp = 0.0f;
        rasterizer.depthBiasSlopeFactor = depthBiasEnable ? 1.0f : 0.0f;

        VkPipelineMultisampleStateCreateInfo multisampling;
        multisampling.sType = VkStructureType.VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO;
        multisampling.sampleShadingEnable = VK_FALSE;
        multisampling.rasterizationSamples = VkSampleCountFlagBits.VK_SAMPLE_COUNT_1_BIT;

        VkPipelineDepthStencilStateCreateInfo depthStencil;
        depthStencil.sType = VkStructureType.VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO;
        depthStencil.depthTestEnable = depthTestEnable ? VK_TRUE : VK_FALSE;
        depthStencil.depthWriteEnable = depthWriteEnable ? VK_TRUE : VK_FALSE;
        depthStencil.depthCompareOp = VkCompareOp.VK_COMPARE_OP_LESS_OR_EQUAL;
        depthStencil.depthBoundsTestEnable = VK_FALSE;
        depthStencil.stencilTestEnable = VK_FALSE;

        VkPipelineColorBlendAttachmentState colorBlendAttachment;
        colorBlendAttachment.colorWriteMask =
            VkColorComponentFlagBits.VK_COLOR_COMPONENT_R_BIT |
            VkColorComponentFlagBits.VK_COLOR_COMPONENT_G_BIT |
            VkColorComponentFlagBits.VK_COLOR_COMPONENT_B_BIT |
            VkColorComponentFlagBits.VK_COLOR_COMPONENT_A_BIT;
        colorBlendAttachment.blendEnable = blendEnable ? VK_TRUE : VK_FALSE;
        colorBlendAttachment.srcColorBlendFactor = VkBlendFactor.VK_BLEND_FACTOR_SRC_ALPHA;
        colorBlendAttachment.dstColorBlendFactor = VkBlendFactor.VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA;
        colorBlendAttachment.colorBlendOp = VkBlendOp.VK_BLEND_OP_ADD;
        colorBlendAttachment.srcAlphaBlendFactor = VkBlendFactor.VK_BLEND_FACTOR_ONE;
        colorBlendAttachment.dstAlphaBlendFactor = VkBlendFactor.VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA;
        colorBlendAttachment.alphaBlendOp = VkBlendOp.VK_BLEND_OP_ADD;

        VkPipelineColorBlendStateCreateInfo colorBlending;
        colorBlending.sType = VkStructureType.VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO;
        colorBlending.attachmentCount = 1;
        colorBlending.pAttachments = &colorBlendAttachment;

        VkDynamicState[2] dynamicStates = [VkDynamicState.VK_DYNAMIC_STATE_VIEWPORT, VkDynamicState.VK_DYNAMIC_STATE_SCISSOR];
        VkPipelineDynamicStateCreateInfo dynamicState;
        dynamicState.sType = VkStructureType.VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO;
        dynamicState.dynamicStateCount = cast(uint)dynamicStates.length;
        dynamicState.pDynamicStates = dynamicStates.ptr;

        VkPipelineLayoutCreateInfo pipelineLayoutInfo;
        pipelineLayoutInfo.sType = VkStructureType.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO;
        pipelineLayoutInfo.setLayoutCount = 1;
        pipelineLayoutInfo.pSetLayouts = &descriptorSetLayout;

        enforce(vkCreatePipelineLayout(device, &pipelineLayoutInfo, null, &pipelineLayout) == VkResult.VK_SUCCESS, "vkCreatePipelineLayout failed.");

        VkGraphicsPipelineCreateInfo pipelineInfo;
        pipelineInfo.sType = VkStructureType.VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO;
        pipelineInfo.stageCount = cast(uint)shaderStages.length;
        pipelineInfo.pStages = shaderStages.ptr;
        pipelineInfo.pVertexInputState = &vertexInputInfo;
        pipelineInfo.pInputAssemblyState = &inputAssembly;
        pipelineInfo.pViewportState = &viewportState;
        pipelineInfo.pRasterizationState = &rasterizer;
        pipelineInfo.pMultisampleState = &multisampling;
        pipelineInfo.pDepthStencilState = &depthStencil;
        pipelineInfo.pColorBlendState = &colorBlending;
        pipelineInfo.pDynamicState = &dynamicState;
        pipelineInfo.layout = pipelineLayout;
        pipelineInfo.renderPass = renderPass;
        pipelineInfo.subpass = 0;

        enforce(vkCreateGraphicsPipelines(device, VK_NULL_HANDLE, 1, &pipelineInfo, null, &pipeline) == VkResult.VK_SUCCESS, "vkCreateGraphicsPipelines failed.");
    }

    /** Creates a Vulkan shader module from SPIR-V bytecode.
     *
     * @param device = Logical Vulkan device.
     * @param code = SPIR-V bytecode.
     * @returns The created shader module handle.
     */
    VkShaderModule createShaderModule(VkDevice device, const(ubyte)[] code)
    {
        VkShaderModuleCreateInfo createInfo;
        createInfo.sType = VkStructureType.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO;
        createInfo.codeSize = code.length;
        createInfo.pCode = cast(const(uint)*)code.ptr;

        VkShaderModule shaderModule;
        enforce(vkCreateShaderModule(device, &createInfo, null, &shaderModule) == VkResult.VK_SUCCESS, "vkCreateShaderModule failed.");
        return shaderModule;
    }
}
