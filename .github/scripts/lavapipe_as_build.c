/* The acceleration-structure builds of contrib/vulkan/test_vulkan_ray_query.ae
 * in plain C, with no Aether code: a one-triangle BLAS, then a TLAS over one
 * instance of it, each built on the device in host-visible memory and
 * waited on. Printed step by step, so the last line says which build died.
 * The Ubuntu 24.04 lavapipe job runs it ahead of the spec, to decide whether
 * the driver can build an acceleration structure at all (aether#2562):
 * lavapipe dies in the BLAS build when llvmpipe runs 128-bit vectors (every
 * aarch64 host; LP_NATIVE_VECTOR_WIDTH=128 reproduces it on x86_64), a store
 * far outside the scratch buffer in its JIT-compiled build shader, through
 * Mesa 26.1.8 at least.
 *
 *   cc -O1 -g lavapipe_as_build.c -o lavapipe_as_build -lvulkan
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <vulkan/vulkan.h>

static VkDevice dev;
static VkPhysicalDevice gpu;
static VkQueue queue;
static uint32_t qfam;
static VkDeviceSize scratch_align = 256;
static PFN_vkGetAccelerationStructureBuildSizesKHR get_sizes;
static PFN_vkCreateAccelerationStructureKHR create_as;
static PFN_vkDestroyAccelerationStructureKHR destroy_as;
static PFN_vkGetAccelerationStructureDeviceAddressKHR as_address;
static PFN_vkCmdBuildAccelerationStructuresKHR cmd_build;

#define CHECK(x) do { VkResult r_ = (x); if (r_ != VK_SUCCESS) { \
    printf("FAILED %s = %d\n", #x, (int)r_); fflush(stdout); exit(2); } } while (0)

typedef struct { VkBuffer buf; VkDeviceMemory mem; VkDeviceAddress addr; void* map; } Buf;

static Buf buf_create(VkDeviceSize size, VkBufferUsageFlags usage) {
    Buf b; memset(&b, 0, sizeof b);
    VkBufferCreateInfo bci = { VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO };
    bci.size = size;
    bci.usage = usage | VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT;
    CHECK(vkCreateBuffer(dev, &bci, NULL, &b.buf));
    VkMemoryRequirements req;
    vkGetBufferMemoryRequirements(dev, b.buf, &req);
    VkPhysicalDeviceMemoryProperties mp;
    vkGetPhysicalDeviceMemoryProperties(gpu, &mp);
    uint32_t want = VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT, mt = UINT32_MAX;
    for (uint32_t i = 0; i < mp.memoryTypeCount; i++)
        if ((req.memoryTypeBits & (1u << i)) && (mp.memoryTypes[i].propertyFlags & want) == want) { mt = i; break; }
    if (mt == UINT32_MAX) { printf("no host-visible memory type\n"); exit(2); }
    VkMemoryAllocateFlagsInfo fl = { VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_FLAGS_INFO };
    fl.flags = VK_MEMORY_ALLOCATE_DEVICE_ADDRESS_BIT;
    VkMemoryAllocateInfo mai = { VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO };
    mai.pNext = &fl;
    mai.allocationSize = req.size;
    mai.memoryTypeIndex = mt;
    CHECK(vkAllocateMemory(dev, &mai, NULL, &b.mem));
    CHECK(vkBindBufferMemory(dev, b.buf, b.mem, 0));
    CHECK(vkMapMemory(dev, b.mem, 0, VK_WHOLE_SIZE, 0, &b.map));
    VkBufferDeviceAddressInfo ai = { VK_STRUCTURE_TYPE_BUFFER_DEVICE_ADDRESS_INFO };
    ai.buffer = b.buf;
    b.addr = vkGetBufferDeviceAddress(dev, &ai);
    return b;
}

static void submit_and_wait(void (*record)(VkCommandBuffer, void*), void* arg) {
    VkCommandPoolCreateInfo pci = { VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO };
    pci.queueFamilyIndex = qfam;
    VkCommandPool pool;
    CHECK(vkCreateCommandPool(dev, &pci, NULL, &pool));
    VkCommandBufferAllocateInfo cai = { VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO };
    cai.commandPool = pool;
    cai.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY;
    cai.commandBufferCount = 1;
    VkCommandBuffer cmd;
    CHECK(vkAllocateCommandBuffers(dev, &cai, &cmd));
    VkCommandBufferBeginInfo bi = { VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO };
    bi.flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;
    CHECK(vkBeginCommandBuffer(cmd, &bi));
    record(cmd, arg);
    CHECK(vkEndCommandBuffer(cmd));
    VkSubmitInfo si = { VK_STRUCTURE_TYPE_SUBMIT_INFO };
    si.commandBufferCount = 1;
    si.pCommandBuffers = &cmd;
    CHECK(vkQueueSubmit(queue, 1, &si, VK_NULL_HANDLE));
    CHECK(vkQueueWaitIdle(queue));
    vkDestroyCommandPool(dev, pool, NULL);
}

typedef struct { VkAccelerationStructureBuildGeometryInfoKHR* info; const VkAccelerationStructureBuildRangeInfoKHR* range; } BuildArgs;

static void record_build(VkCommandBuffer cmd, void* p) {
    BuildArgs* a = p;
    cmd_build(cmd, 1, a->info, &a->range);
}

typedef struct { VkAccelerationStructureKHR as; Buf storage, scratch; VkDeviceAddress addr; } Accel;

static Accel build(VkAccelerationStructureTypeKHR type, const VkAccelerationStructureGeometryKHR* geom, const char* what) {
    Accel a; memset(&a, 0, sizeof a);
    VkAccelerationStructureBuildGeometryInfoKHR info = { VK_STRUCTURE_TYPE_ACCELERATION_STRUCTURE_BUILD_GEOMETRY_INFO_KHR };
    info.type = type;
    info.flags = VK_BUILD_ACCELERATION_STRUCTURE_PREFER_FAST_TRACE_BIT_KHR;
    info.mode = VK_BUILD_ACCELERATION_STRUCTURE_MODE_BUILD_KHR;
    info.geometryCount = 1;
    info.pGeometries = geom;
    uint32_t count = 1;
    VkAccelerationStructureBuildSizesInfoKHR sizes = { VK_STRUCTURE_TYPE_ACCELERATION_STRUCTURE_BUILD_SIZES_INFO_KHR };
    get_sizes(dev, VK_ACCELERATION_STRUCTURE_BUILD_TYPE_DEVICE_KHR, &info, &count, &sizes);
    printf("%s: structure %llu bytes, scratch %llu bytes\n", what,
           (unsigned long long)sizes.accelerationStructureSize, (unsigned long long)sizes.buildScratchSize);
    a.storage = buf_create(sizes.accelerationStructureSize, VK_BUFFER_USAGE_ACCELERATION_STRUCTURE_STORAGE_BIT_KHR);
    a.scratch = buf_create(sizes.buildScratchSize + scratch_align, VK_BUFFER_USAGE_STORAGE_BUFFER_BIT);
    VkAccelerationStructureCreateInfoKHR ci = { VK_STRUCTURE_TYPE_ACCELERATION_STRUCTURE_CREATE_INFO_KHR };
    ci.buffer = a.storage.buf;
    ci.size = sizes.accelerationStructureSize;
    ci.type = type;
    CHECK(create_as(dev, &ci, NULL, &a.as));
    VkAccelerationStructureDeviceAddressInfoKHR ai = { VK_STRUCTURE_TYPE_ACCELERATION_STRUCTURE_DEVICE_ADDRESS_INFO_KHR };
    ai.accelerationStructure = a.as;
    a.addr = as_address(dev, &ai);
    info.dstAccelerationStructure = a.as;
    info.scratchData.deviceAddress = (a.scratch.addr + scratch_align - 1) & ~(scratch_align - 1);
    VkAccelerationStructureBuildRangeInfoKHR range; memset(&range, 0, sizeof range);
    range.primitiveCount = 1;
    BuildArgs args = { &info, &range };
    printf("%s: building\n", what); fflush(stdout);
    submit_and_wait(record_build, &args);
    printf("%s: built, address 0x%llx\n", what, (unsigned long long)a.addr); fflush(stdout);
    return a;
}

int main(void) {
    VkApplicationInfo app = { VK_STRUCTURE_TYPE_APPLICATION_INFO };
    app.apiVersion = VK_API_VERSION_1_2;
    VkInstanceCreateInfo ici = { VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO };
    ici.pApplicationInfo = &app;
    VkInstance inst;
    CHECK(vkCreateInstance(&ici, NULL, &inst));
    uint32_t n = 1;
    VkResult er = vkEnumeratePhysicalDevices(inst, &n, &gpu);
    if ((er != VK_SUCCESS && er != VK_INCOMPLETE) || n == 0) { printf("no device\n"); return 2; }
    VkPhysicalDeviceProperties props;
    vkGetPhysicalDeviceProperties(gpu, &props);
    printf("device: %s, driver version 0x%x\n", props.deviceName, props.driverVersion);

    VkPhysicalDeviceAccelerationStructurePropertiesKHR asp = { VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_ACCELERATION_STRUCTURE_PROPERTIES_KHR };
    VkPhysicalDeviceProperties2 p2 = { VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PROPERTIES_2 };
    p2.pNext = &asp;
    vkGetPhysicalDeviceProperties2(gpu, &p2);
    if (asp.minAccelerationStructureScratchOffsetAlignment > 0) scratch_align = asp.minAccelerationStructureScratchOffsetAlignment;

    uint32_t nq = 0;
    vkGetPhysicalDeviceQueueFamilyProperties(gpu, &nq, NULL);
    VkQueueFamilyProperties qf[16];
    if (nq > 16) nq = 16;
    vkGetPhysicalDeviceQueueFamilyProperties(gpu, &nq, qf);
    qfam = UINT32_MAX;
    for (uint32_t i = 0; i < nq; i++) if (qf[i].queueFlags & VK_QUEUE_COMPUTE_BIT) { qfam = i; break; }
    if (qfam == UINT32_MAX) { printf("no compute queue\n"); return 2; }

    VkPhysicalDeviceBufferDeviceAddressFeatures bda = { VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_BUFFER_DEVICE_ADDRESS_FEATURES };
    bda.bufferDeviceAddress = VK_TRUE;
    VkPhysicalDeviceAccelerationStructureFeaturesKHR asf = { VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_ACCELERATION_STRUCTURE_FEATURES_KHR };
    asf.accelerationStructure = VK_TRUE;
    asf.pNext = &bda;
    VkPhysicalDeviceRayQueryFeaturesKHR rqf = { VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_RAY_QUERY_FEATURES_KHR };
    rqf.rayQuery = VK_TRUE;
    rqf.pNext = &asf;
    const char* exts[] = { "VK_KHR_acceleration_structure", "VK_KHR_ray_query", "VK_KHR_deferred_host_operations" };
    float prio = 1.0f;
    VkDeviceQueueCreateInfo qci = { VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO };
    qci.queueFamilyIndex = qfam;
    qci.queueCount = 1;
    qci.pQueuePriorities = &prio;
    VkDeviceCreateInfo dci = { VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO };
    dci.pNext = &rqf;
    dci.queueCreateInfoCount = 1;
    dci.pQueueCreateInfos = &qci;
    dci.enabledExtensionCount = 3;
    dci.ppEnabledExtensionNames = exts;
    CHECK(vkCreateDevice(gpu, &dci, NULL, &dev));
    vkGetDeviceQueue(dev, qfam, 0, &queue);
    get_sizes = (PFN_vkGetAccelerationStructureBuildSizesKHR)vkGetDeviceProcAddr(dev, "vkGetAccelerationStructureBuildSizesKHR");
    create_as = (PFN_vkCreateAccelerationStructureKHR)vkGetDeviceProcAddr(dev, "vkCreateAccelerationStructureKHR");
    destroy_as = (PFN_vkDestroyAccelerationStructureKHR)vkGetDeviceProcAddr(dev, "vkDestroyAccelerationStructureKHR");
    as_address = (PFN_vkGetAccelerationStructureDeviceAddressKHR)vkGetDeviceProcAddr(dev, "vkGetAccelerationStructureDeviceAddressKHR");
    cmd_build = (PFN_vkCmdBuildAccelerationStructuresKHR)vkGetDeviceProcAddr(dev, "vkCmdBuildAccelerationStructuresKHR");
    if (!get_sizes || !create_as || !destroy_as || !as_address || !cmd_build) { printf("no acceleration structure entry points\n"); return 2; }

    /* The triangle, 3 x vec3, exactly 36 bytes as the spec's buffer. */
    Buf verts = buf_create(36, VK_BUFFER_USAGE_ACCELERATION_STRUCTURE_BUILD_INPUT_READ_ONLY_BIT_KHR);
    float tri[9] = { -1, -1, 0, 1, -1, 0, 0, 1, 0 };
    memcpy(verts.map, tri, sizeof tri);
    VkAccelerationStructureGeometryKHR geom = { VK_STRUCTURE_TYPE_ACCELERATION_STRUCTURE_GEOMETRY_KHR };
    geom.geometryType = VK_GEOMETRY_TYPE_TRIANGLES_KHR;
    geom.flags = VK_GEOMETRY_OPAQUE_BIT_KHR;
    geom.geometry.triangles.sType = VK_STRUCTURE_TYPE_ACCELERATION_STRUCTURE_GEOMETRY_TRIANGLES_DATA_KHR;
    geom.geometry.triangles.vertexFormat = VK_FORMAT_R32G32B32_SFLOAT;
    geom.geometry.triangles.vertexData.deviceAddress = verts.addr;
    geom.geometry.triangles.vertexStride = 12;
    geom.geometry.triangles.maxVertex = 2;
    geom.geometry.triangles.indexType = VK_INDEX_TYPE_NONE_KHR;
    Accel blas = build(VK_ACCELERATION_STRUCTURE_TYPE_BOTTOM_LEVEL_KHR, &geom, "BLAS");

    Buf ib = buf_create(sizeof(VkAccelerationStructureInstanceKHR), VK_BUFFER_USAGE_ACCELERATION_STRUCTURE_BUILD_INPUT_READ_ONLY_BIT_KHR);
    VkAccelerationStructureInstanceKHR inst_rec; memset(&inst_rec, 0, sizeof inst_rec);
    inst_rec.transform.matrix[0][0] = inst_rec.transform.matrix[1][1] = inst_rec.transform.matrix[2][2] = 1.0f;
    inst_rec.mask = 0xFF;
    inst_rec.flags = VK_GEOMETRY_INSTANCE_TRIANGLE_FACING_CULL_DISABLE_BIT_KHR;
    inst_rec.accelerationStructureReference = blas.addr;
    memcpy(ib.map, &inst_rec, sizeof inst_rec);
    VkAccelerationStructureGeometryKHR ig = { VK_STRUCTURE_TYPE_ACCELERATION_STRUCTURE_GEOMETRY_KHR };
    ig.geometryType = VK_GEOMETRY_TYPE_INSTANCES_KHR;
    ig.geometry.instances.sType = VK_STRUCTURE_TYPE_ACCELERATION_STRUCTURE_GEOMETRY_INSTANCES_DATA_KHR;
    ig.geometry.instances.data.deviceAddress = ib.addr;
    Accel tlas = build(VK_ACCELERATION_STRUCTURE_TYPE_TOP_LEVEL_KHR, &ig, "TLAS");

    destroy_as(dev, tlas.as, NULL);
    destroy_as(dev, blas.as, NULL);
    vkDeviceWaitIdle(dev);
    printf("ok: both builds finished\n");
    return 0;
}
