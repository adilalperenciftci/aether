/* A draw into a VK_FORMAT_D32_SFLOAT_S8_UINT depth-stencil attachment in
 * plain C, with no Aether code: what contrib/vulkan does for a depth-stencil
 * target. One 8x8 RGBA8 colour attachment and one depth-stencil attachment
 * viewed with both aspects, a quad at depth 0.5 under a LESS_OR_EQUAL depth
 * test (no stencil test), drawn `frames` times, each frame submitted and
 * waited on. The shaders are contrib/vulkan/shaders/depth.vert and
 * depth.frag, read as SPIR-V from the directory given.
 *
 * lavapipe (Mesa 26.1.8, llvmpipe) crashes in this draw, a SIGSEGV in
 * JIT-compiled code on one of its rasteriser threads, in about half the runs
 * with D32S8; the same program with D24_UNORM_S8_UINT, nothing else changed,
 * does not crash (aether#2410). Under gdb the faulting instruction is an
 * aligned 32-byte load, `vmovaps (%r11,%r12,1),%ymm5`, from an address that
 * is 16 mod 32: the 256-bit depth path reads D32S8 depth storage that is only
 * 16-byte aligned, so whether it crashes depends on where that run's
 * allocation landed. With LP_NATIVE_VECTOR_WIDTH=128 it never crashes.
 * CI runs it a number of times in each format where lavapipe is the driver
 * and reports the counts, without judging them.
 *
 *   cc -O1 -g lavapipe_d32s8_draw.c -o lavapipe_d32s8_draw -lvulkan   (-lvulkan-1 on MinGW)
 *   VK_DRIVER_FILES=<lvp_icd json> ./lavapipe_d32s8_draw [d32s8|d24s8] [frames] [shader dir]
 *
 * Exit 0 when every frame was drawn, 2 when a call failed, 3 when the device
 * cannot use the format as a depth-stencil attachment; a crash is the
 * driver's.
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <vulkan/vulkan.h>

#define CHECK(x) do { VkResult r_ = (x); if (r_ != VK_SUCCESS) { \
    printf("FAILED %s = %d (line %d)\n", #x, (int)r_, __LINE__); fflush(stdout); exit(2); } } while (0)

static void* read_file(const char* path, size_t* len) {
    FILE* f = fopen(path, "rb");
    if (!f) { printf("cannot open %s\n", path); exit(2); }
    fseek(f, 0, SEEK_END);
    *len = (size_t)ftell(f);
    fseek(f, 0, SEEK_SET);
    void* p = malloc(*len);
    if (!p || fread(p, 1, *len, f) != *len) { printf("cannot read %s\n", path); exit(2); }
    fclose(f);
    return p;
}

static uint32_t find_memory(VkPhysicalDevice phys, uint32_t bits, VkMemoryPropertyFlags want) {
    VkPhysicalDeviceMemoryProperties mp;
    vkGetPhysicalDeviceMemoryProperties(phys, &mp);
    for (uint32_t i = 0; i < mp.memoryTypeCount; i++)
        if ((bits & (1u << i)) && (mp.memoryTypes[i].propertyFlags & want) == want) return i;
    printf("no memory type\n");
    exit(2);
}

static void make_image(VkDevice dev, VkPhysicalDevice phys, VkFormat fmt, VkImageUsageFlags usage,
                       VkImageAspectFlags aspect, VkImage* img, VkDeviceMemory* mem, VkImageView* view) {
    VkImageCreateInfo ici = { VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO };
    ici.imageType = VK_IMAGE_TYPE_2D;
    ici.format = fmt;
    ici.extent.width = 8;
    ici.extent.height = 8;
    ici.extent.depth = 1;
    ici.mipLevels = 1;
    ici.arrayLayers = 1;
    ici.samples = VK_SAMPLE_COUNT_1_BIT;
    ici.tiling = VK_IMAGE_TILING_OPTIMAL;
    ici.usage = usage;
    CHECK(vkCreateImage(dev, &ici, NULL, img));
    VkMemoryRequirements req;
    vkGetImageMemoryRequirements(dev, *img, &req);
    VkMemoryAllocateInfo mai = { VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO };
    mai.allocationSize = req.size;
    mai.memoryTypeIndex = find_memory(phys, req.memoryTypeBits, VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT);
    CHECK(vkAllocateMemory(dev, &mai, NULL, mem));
    CHECK(vkBindImageMemory(dev, *img, *mem, 0));
    VkImageViewCreateInfo vci = { VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO };
    vci.image = *img;
    vci.viewType = VK_IMAGE_VIEW_TYPE_2D;
    vci.format = fmt;
    vci.subresourceRange.aspectMask = aspect;
    vci.subresourceRange.levelCount = 1;
    vci.subresourceRange.layerCount = 1;
    CHECK(vkCreateImageView(dev, &vci, NULL, view));
}

static VkShaderModule load_shader(VkDevice dev, const char* dir, const char* name) {
    char path[1024];
    snprintf(path, sizeof path, "%s/%s", dir, name);
    size_t len = 0;
    void* code = read_file(path, &len);
    VkShaderModuleCreateInfo sci = { VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO };
    sci.codeSize = len;
    sci.pCode = (const uint32_t*)code;
    VkShaderModule m;
    CHECK(vkCreateShaderModule(dev, &sci, NULL, &m));
    free(code);
    return m;
}

int main(int argc, char** argv) {
    VkFormat depth_fmt = VK_FORMAT_D32_SFLOAT_S8_UINT;
    int frames = 50;
    const char* shaders = "contrib/vulkan/shaders";
    if (argc > 1 && strcmp(argv[1], "d24s8") == 0) depth_fmt = VK_FORMAT_D24_UNORM_S8_UINT;
    else if (argc > 1 && strcmp(argv[1], "d32s8") != 0) { printf("format: d32s8 or d24s8\n"); return 2; }
    if (argc > 2) frames = atoi(argv[2]);
    if (argc > 3) shaders = argv[3];

    VkApplicationInfo app = { VK_STRUCTURE_TYPE_APPLICATION_INFO };
    app.apiVersion = VK_API_VERSION_1_0;
    VkInstanceCreateInfo ii = { VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO };
    ii.pApplicationInfo = &app;
    VkInstance inst;
    CHECK(vkCreateInstance(&ii, NULL, &inst));
    uint32_t n = 1;
    VkPhysicalDevice phys;
    VkResult er = vkEnumeratePhysicalDevices(inst, &n, &phys);
    if ((er != VK_SUCCESS && er != VK_INCOMPLETE) || n == 0) { printf("no device\n"); return 2; }
    VkPhysicalDeviceProperties props;
    vkGetPhysicalDeviceProperties(phys, &props);
    VkFormatProperties fp;
    vkGetPhysicalDeviceFormatProperties(phys, depth_fmt, &fp);
    printf("device: %s, driver version 0x%x, depth format %s, %d frames\n", props.deviceName,
           props.driverVersion, depth_fmt == VK_FORMAT_D32_SFLOAT_S8_UINT ? "D32_SFLOAT_S8_UINT"
                                                                      : "D24_UNORM_S8_UINT", frames);
    fflush(stdout);
    if (!(fp.optimalTilingFeatures & VK_FORMAT_FEATURE_DEPTH_STENCIL_ATTACHMENT_BIT)) {
        printf("the device has no optimal-tiling depth-stencil attachment in this format\n");
        return 3;
    }

    float prio = 1.0f;
    VkDeviceQueueCreateInfo qci = { VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO };
    qci.queueFamilyIndex = 0;
    qci.queueCount = 1;
    qci.pQueuePriorities = &prio;
    VkDeviceCreateInfo dci = { VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO };
    dci.queueCreateInfoCount = 1;
    dci.pQueueCreateInfos = &qci;
    VkDevice dev;
    CHECK(vkCreateDevice(phys, &dci, NULL, &dev));
    VkQueue queue;
    vkGetDeviceQueue(dev, 0, 0, &queue);

    VkImage cimg, dimg;
    VkDeviceMemory cmem, dmem;
    VkImageView cview, dview;
    make_image(dev, phys, VK_FORMAT_R8G8B8A8_UNORM,
               VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT | VK_IMAGE_USAGE_TRANSFER_SRC_BIT,
               VK_IMAGE_ASPECT_COLOR_BIT, &cimg, &cmem, &cview);
    make_image(dev, phys, depth_fmt,
               VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT | VK_IMAGE_USAGE_TRANSIENT_ATTACHMENT_BIT,
               VK_IMAGE_ASPECT_DEPTH_BIT | VK_IMAGE_ASPECT_STENCIL_BIT, &dimg, &dmem, &dview);

    VkAttachmentDescription atts[2];
    memset(atts, 0, sizeof atts);
    atts[0].format = VK_FORMAT_R8G8B8A8_UNORM;
    atts[0].samples = VK_SAMPLE_COUNT_1_BIT;
    atts[0].loadOp = VK_ATTACHMENT_LOAD_OP_CLEAR;
    atts[0].storeOp = VK_ATTACHMENT_STORE_OP_STORE;
    atts[0].stencilLoadOp = VK_ATTACHMENT_LOAD_OP_DONT_CARE;
    atts[0].stencilStoreOp = VK_ATTACHMENT_STORE_OP_DONT_CARE;
    atts[0].initialLayout = VK_IMAGE_LAYOUT_UNDEFINED;
    atts[0].finalLayout = VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL;
    atts[1].format = depth_fmt;
    atts[1].samples = VK_SAMPLE_COUNT_1_BIT;
    atts[1].loadOp = VK_ATTACHMENT_LOAD_OP_CLEAR;
    atts[1].storeOp = VK_ATTACHMENT_STORE_OP_DONT_CARE;
    atts[1].stencilLoadOp = VK_ATTACHMENT_LOAD_OP_CLEAR;
    atts[1].stencilStoreOp = VK_ATTACHMENT_STORE_OP_DONT_CARE;
    atts[1].initialLayout = VK_IMAGE_LAYOUT_UNDEFINED;
    atts[1].finalLayout = VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL;
    VkAttachmentReference cref = { 0, VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL };
    VkAttachmentReference dref = { 1, VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL };
    VkSubpassDescription sub;
    memset(&sub, 0, sizeof sub);
    sub.pipelineBindPoint = VK_PIPELINE_BIND_POINT_GRAPHICS;
    sub.colorAttachmentCount = 1;
    sub.pColorAttachments = &cref;
    sub.pDepthStencilAttachment = &dref;
    VkRenderPassCreateInfo rpi = { VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO };
    rpi.attachmentCount = 2;
    rpi.pAttachments = atts;
    rpi.subpassCount = 1;
    rpi.pSubpasses = &sub;
    VkRenderPass pass;
    CHECK(vkCreateRenderPass(dev, &rpi, NULL, &pass));

    VkImageView views[2] = { cview, dview };
    VkFramebufferCreateInfo fci = { VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO };
    fci.renderPass = pass;
    fci.attachmentCount = 2;
    fci.pAttachments = views;
    fci.width = 8;
    fci.height = 8;
    fci.layers = 1;
    VkFramebuffer fb;
    CHECK(vkCreateFramebuffer(dev, &fci, NULL, &fb));

    VkShaderModule vs = load_shader(dev, shaders, "depth.vert.spv");
    VkShaderModule fs = load_shader(dev, shaders, "depth.frag.spv");
    VkPipelineShaderStageCreateInfo stages[2];
    memset(stages, 0, sizeof stages);
    stages[0].sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
    stages[0].stage = VK_SHADER_STAGE_VERTEX_BIT;
    stages[0].module = vs;
    stages[0].pName = "main";
    stages[1].sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
    stages[1].stage = VK_SHADER_STAGE_FRAGMENT_BIT;
    stages[1].module = fs;
    stages[1].pName = "main";
    /* depth.vert reads a position (x, y, z) and a colour. */
    VkVertexInputBindingDescription bind = { 0, 24, VK_VERTEX_INPUT_RATE_VERTEX };
    VkVertexInputAttributeDescription attrs[2] = {
        { 0, 0, VK_FORMAT_R32G32B32_SFLOAT, 0 },
        { 1, 0, VK_FORMAT_R32G32B32_SFLOAT, 12 },
    };
    VkPipelineVertexInputStateCreateInfo vin = { VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO };
    vin.vertexBindingDescriptionCount = 1;
    vin.pVertexBindingDescriptions = &bind;
    vin.vertexAttributeDescriptionCount = 2;
    vin.pVertexAttributeDescriptions = attrs;
    VkPipelineInputAssemblyStateCreateInfo ia = { VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO };
    ia.topology = VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST;
    VkPipelineViewportStateCreateInfo vps = { VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO };
    vps.viewportCount = 1;
    vps.scissorCount = 1;
    VkDynamicState dyn_states[2] = { VK_DYNAMIC_STATE_VIEWPORT, VK_DYNAMIC_STATE_SCISSOR };
    VkPipelineDynamicStateCreateInfo dyn = { VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO };
    dyn.dynamicStateCount = 2;
    dyn.pDynamicStates = dyn_states;
    VkPipelineRasterizationStateCreateInfo rs = { VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO };
    rs.polygonMode = VK_POLYGON_MODE_FILL;
    rs.cullMode = VK_CULL_MODE_NONE;
    rs.frontFace = VK_FRONT_FACE_COUNTER_CLOCKWISE;
    rs.lineWidth = 1.0f;
    VkPipelineMultisampleStateCreateInfo ms = { VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO };
    ms.rasterizationSamples = VK_SAMPLE_COUNT_1_BIT;
    VkPipelineDepthStencilStateCreateInfo ds = { VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO };
    ds.depthTestEnable = VK_TRUE;
    ds.depthWriteEnable = VK_TRUE;
    ds.depthCompareOp = VK_COMPARE_OP_LESS_OR_EQUAL;
    ds.maxDepthBounds = 1.0f;
    VkPipelineColorBlendAttachmentState cba;
    memset(&cba, 0, sizeof cba);
    cba.colorWriteMask = 0xF;
    VkPipelineColorBlendStateCreateInfo cb = { VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO };
    cb.attachmentCount = 1;
    cb.pAttachments = &cba;
    VkPipelineLayoutCreateInfo pli = { VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO };
    VkPipelineLayout layout;
    CHECK(vkCreatePipelineLayout(dev, &pli, NULL, &layout));
    VkGraphicsPipelineCreateInfo gpi = { VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO };
    gpi.stageCount = 2;
    gpi.pStages = stages;
    gpi.pVertexInputState = &vin;
    gpi.pInputAssemblyState = &ia;
    gpi.pViewportState = &vps;
    gpi.pRasterizationState = &rs;
    gpi.pMultisampleState = &ms;
    gpi.pDepthStencilState = &ds;
    gpi.pColorBlendState = &cb;
    gpi.pDynamicState = &dyn;
    gpi.layout = layout;
    gpi.renderPass = pass;
    VkPipeline pipe;
    CHECK(vkCreateGraphicsPipelines(dev, VK_NULL_HANDLE, 1, &gpi, NULL, &pipe));

    /* Two triangles covering the target at depth 0.5, coloured red. */
    float verts[6][6] = {
        { -1, -1, 0.5f, 1, 0, 0 }, { 1, -1, 0.5f, 1, 0, 0 }, { 1, 1, 0.5f, 1, 0, 0 },
        { 1, 1, 0.5f, 1, 0, 0 }, { -1, 1, 0.5f, 1, 0, 0 }, { -1, -1, 0.5f, 1, 0, 0 },
    };
    VkBufferCreateInfo bci = { VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO };
    bci.size = sizeof verts;
    bci.usage = VK_BUFFER_USAGE_VERTEX_BUFFER_BIT;
    VkBuffer vbuf;
    CHECK(vkCreateBuffer(dev, &bci, NULL, &vbuf));
    VkMemoryRequirements breq;
    vkGetBufferMemoryRequirements(dev, vbuf, &breq);
    VkMemoryAllocateInfo bmai = { VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO };
    bmai.allocationSize = breq.size;
    bmai.memoryTypeIndex = find_memory(phys, breq.memoryTypeBits,
                                       VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT);
    VkDeviceMemory vmem;
    CHECK(vkAllocateMemory(dev, &bmai, NULL, &vmem));
    CHECK(vkBindBufferMemory(dev, vbuf, vmem, 0));
    void* map;
    CHECK(vkMapMemory(dev, vmem, 0, sizeof verts, 0, &map));
    memcpy(map, verts, sizeof verts);
    vkUnmapMemory(dev, vmem);

    VkCommandPoolCreateInfo pci = { VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO };
    pci.flags = VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT;
    VkCommandPool pool;
    CHECK(vkCreateCommandPool(dev, &pci, NULL, &pool));
    VkCommandBufferAllocateInfo cai = { VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO };
    cai.commandPool = pool;
    cai.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY;
    cai.commandBufferCount = 1;
    VkCommandBuffer cmd;
    CHECK(vkAllocateCommandBuffers(dev, &cai, &cmd));
    VkFenceCreateInfo fe = { VK_STRUCTURE_TYPE_FENCE_CREATE_INFO };
    VkFence fence;
    CHECK(vkCreateFence(dev, &fe, NULL, &fence));

    for (int f = 0; f < frames; f++) {
        CHECK(vkResetCommandBuffer(cmd, 0));
        VkCommandBufferBeginInfo bi = { VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO };
        CHECK(vkBeginCommandBuffer(cmd, &bi));
        VkClearValue clears[2];
        memset(clears, 0, sizeof clears);
        clears[0].color.float32[2] = 1.0f;
        clears[0].color.float32[3] = 1.0f;
        clears[1].depthStencil.depth = 1.0f;
        VkRenderPassBeginInfo rbi = { VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO };
        rbi.renderPass = pass;
        rbi.framebuffer = fb;
        rbi.renderArea.extent.width = 8;
        rbi.renderArea.extent.height = 8;
        rbi.clearValueCount = 2;
        rbi.pClearValues = clears;
        vkCmdBeginRenderPass(cmd, &rbi, VK_SUBPASS_CONTENTS_INLINE);
        VkViewport vp = { 0, 0, 8, 8, 0, 1 };
        VkRect2D sc = { { 0, 0 }, { 8, 8 } };
        vkCmdSetViewport(cmd, 0, 1, &vp);
        vkCmdSetScissor(cmd, 0, 1, &sc);
        vkCmdBindPipeline(cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, pipe);
        VkDeviceSize off = 0;
        vkCmdBindVertexBuffers(cmd, 0, 1, &vbuf, &off);
        vkCmdDraw(cmd, 6, 1, 0, 0);
        vkCmdEndRenderPass(cmd);
        CHECK(vkEndCommandBuffer(cmd));
        VkSubmitInfo si = { VK_STRUCTURE_TYPE_SUBMIT_INFO };
        si.commandBufferCount = 1;
        si.pCommandBuffers = &cmd;
        CHECK(vkResetFences(dev, 1, &fence));
        CHECK(vkQueueSubmit(queue, 1, &si, fence));
        CHECK(vkWaitForFences(dev, 1, &fence, VK_TRUE, 5000000000ull));
    }
    printf("done: %d frames drawn\n", frames);
    fflush(stdout);

    vkDeviceWaitIdle(dev);
    vkDestroyFence(dev, fence, NULL);
    vkDestroyCommandPool(dev, pool, NULL);
    vkDestroyBuffer(dev, vbuf, NULL);
    vkFreeMemory(dev, vmem, NULL);
    vkDestroyPipeline(dev, pipe, NULL);
    vkDestroyPipelineLayout(dev, layout, NULL);
    vkDestroyShaderModule(dev, vs, NULL);
    vkDestroyShaderModule(dev, fs, NULL);
    vkDestroyFramebuffer(dev, fb, NULL);
    vkDestroyRenderPass(dev, pass, NULL);
    vkDestroyImageView(dev, cview, NULL);
    vkDestroyImageView(dev, dview, NULL);
    vkDestroyImage(dev, cimg, NULL);
    vkDestroyImage(dev, dimg, NULL);
    vkFreeMemory(dev, cmem, NULL);
    vkFreeMemory(dev, dmem, NULL);
    vkDestroyDevice(dev, NULL);
    vkDestroyInstance(inst, NULL);
    return 0;
}
