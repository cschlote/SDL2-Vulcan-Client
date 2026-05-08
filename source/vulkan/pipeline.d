module vulkan.pipeline;

import bindbc.vulkan;
import std.exception : enforce;
import std.file : read;

struct Vertex
{
    float[3] position;
    float[3] color;
}

struct PipelineResources
{
    VkRenderPass renderPass = VK_NULL_HANDLE;
    VkDescriptorSetLayout descriptorSetLayout = VK_NULL_HANDLE;
    VkPipelineLayout pipelineLayout = VK_NULL_HANDLE;
    VkPipeline graphicsPipeline = VK_NULL_HANDLE;

    this(VkDevice device, VkExtent2D extent, VkFormat colorFormat, VkFormat depthFormat, string vertexShaderPath, string fragmentShaderPath)
    {
        createDescriptorSetLayout(device);
        createRenderPass(device, colorFormat, depthFormat);
        createGraphicsPipeline(device, extent, vertexShaderPath, fragmentShaderPath);
    }

    void destroy(VkDevice device)
    {
        if (graphicsPipeline != VK_NULL_HANDLE)
        {
            vkDestroyPipeline(device, graphicsPipeline, null);
            graphicsPipeline = VK_NULL_HANDLE;
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
    void createDescriptorSetLayout(VkDevice device)
    {
        VkDescriptorSetLayoutBinding binding;
        binding.binding = 0;
        binding.descriptorType = VkDescriptorType.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER;
        binding.descriptorCount = 1;
        binding.stageFlags = VkShaderStageFlagBits.VK_SHADER_STAGE_VERTEX_BIT;

        VkDescriptorSetLayoutCreateInfo createInfo;
        createInfo.sType = VkStructureType.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO;
        createInfo.bindingCount = 1;
        createInfo.pBindings = &binding;

        enforce(vkCreateDescriptorSetLayout(device, &createInfo, null, &descriptorSetLayout) == VkResult.VK_SUCCESS, "vkCreateDescriptorSetLayout failed.");
    }

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

    void createGraphicsPipeline(VkDevice device, VkExtent2D extent, string vertexShaderPath, string fragmentShaderPath)
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
        attributes[1].format = VkFormat.VK_FORMAT_R32G32B32_SFLOAT;
        attributes[1].offset = Vertex.color.offsetof;

        VkPipelineVertexInputStateCreateInfo vertexInputInfo;
        vertexInputInfo.sType = VkStructureType.VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO;
        vertexInputInfo.vertexBindingDescriptionCount = 1;
        vertexInputInfo.pVertexBindingDescriptions = &bindingDescription;
        vertexInputInfo.vertexAttributeDescriptionCount = cast(uint)attributes.length;
        vertexInputInfo.pVertexAttributeDescriptions = attributes.ptr;

        VkPipelineInputAssemblyStateCreateInfo inputAssembly;
        inputAssembly.sType = VkStructureType.VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO;
        inputAssembly.topology = VkPrimitiveTopology.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST;
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
        rasterizer.polygonMode = VkPolygonMode.VK_POLYGON_MODE_FILL;
        rasterizer.lineWidth = 1;
        rasterizer.cullMode = VkCullModeFlagBits.VK_CULL_MODE_NONE;
        rasterizer.frontFace = VkFrontFace.VK_FRONT_FACE_COUNTER_CLOCKWISE;
        rasterizer.depthBiasEnable = VK_FALSE;

        VkPipelineMultisampleStateCreateInfo multisampling;
        multisampling.sType = VkStructureType.VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO;
        multisampling.sampleShadingEnable = VK_FALSE;
        multisampling.rasterizationSamples = VkSampleCountFlagBits.VK_SAMPLE_COUNT_1_BIT;

        VkPipelineDepthStencilStateCreateInfo depthStencil;
        depthStencil.sType = VkStructureType.VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO;
        depthStencil.depthTestEnable = VK_TRUE;
        depthStencil.depthWriteEnable = VK_TRUE;
        depthStencil.depthCompareOp = VkCompareOp.VK_COMPARE_OP_LESS;
        depthStencil.depthBoundsTestEnable = VK_FALSE;
        depthStencil.stencilTestEnable = VK_FALSE;

        VkPipelineColorBlendAttachmentState colorBlendAttachment;
        colorBlendAttachment.colorWriteMask =
            VkColorComponentFlagBits.VK_COLOR_COMPONENT_R_BIT |
            VkColorComponentFlagBits.VK_COLOR_COMPONENT_G_BIT |
            VkColorComponentFlagBits.VK_COLOR_COMPONENT_B_BIT |
            VkColorComponentFlagBits.VK_COLOR_COMPONENT_A_BIT;
        colorBlendAttachment.blendEnable = VK_FALSE;

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

        enforce(vkCreateGraphicsPipelines(device, VK_NULL_HANDLE, 1, &pipelineInfo, null, &graphicsPipeline) == VkResult.VK_SUCCESS, "vkCreateGraphicsPipelines failed.");
    }

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
