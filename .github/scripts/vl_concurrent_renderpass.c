/* Threads creating and destroying render passes on one device at once, in
 * plain C, with no Aether code. vkCreateRenderPass and vkDestroyRenderPass
 * of distinct render passes need no external synchronisation, so this must
 * never fail or corrupt the heap, whatever the driver and whatever layers
 * are loaded.
 *
 * Under the Khronos validation layer 1.4.357 (VK_INSTANCE_LAYERS=
 * VK_LAYER_KHRONOS_validation) on Windows it corrupts the heap: the process
 * dies with STATUS_HEAP_CORRUPTION (0xC0000374), the heap reporting a block
 * "modified past requested size of 80" in a free() inside the layer during
 * vkCreateRenderPass, or an access violation. Without the layer, or with one
 * thread, it never does, on lavapipe as on a GPU driver (aether#2371, the
 * crash of contrib/vulkan/test_vulkan_actors under the layer). It takes the
 * layer's handle wrapping: with VK_KHRONOS_VALIDATION_UNIQUE_HANDLES=false
 * it never crashed in 80 runs, and with only unique_handles and
 * stateless_param on it crashes in more than half the runs of four threads.
 *
 *   cc -O1 -g vl_concurrent_renderpass.c -o vl_concurrent_renderpass -lvulkan -pthread   (-lvulkan-1 on MinGW)
 *   VK_INSTANCE_LAYERS=VK_LAYER_KHRONOS_validation ./vl_concurrent_renderpass [threads=2] [iterations=2000]
 *
 * It prints the device and the layers the loader enabled, then "ok" and
 * exits 0 when every render pass was created and destroyed, 1 when a
 * vkCreateRenderPass failed, 2 when the setup failed; a crash is the
 * driver's or a layer's.
 */
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <vulkan/vulkan.h>

#define MAX_THREADS 16

static VkDevice g_dev;
static int g_iters = 2000;

static void* worker(void* arg) {
    (void)arg;
    for (int i = 0; i < g_iters; i++) {
        VkAttachmentDescription a;
        memset(&a, 0, sizeof a);
        a.format = VK_FORMAT_R8G8B8A8_UNORM;
        a.samples = VK_SAMPLE_COUNT_1_BIT;
        a.loadOp = VK_ATTACHMENT_LOAD_OP_CLEAR;
        a.storeOp = VK_ATTACHMENT_STORE_OP_STORE;
        a.stencilLoadOp = VK_ATTACHMENT_LOAD_OP_DONT_CARE;
        a.stencilStoreOp = VK_ATTACHMENT_STORE_OP_DONT_CARE;
        a.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED;
        a.finalLayout = VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL;
        VkAttachmentReference ref = { 0, VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL };
        VkSubpassDescription sp;
        memset(&sp, 0, sizeof sp);
        sp.pipelineBindPoint = VK_PIPELINE_BIND_POINT_GRAPHICS;
        sp.colorAttachmentCount = 1;
        sp.pColorAttachments = &ref;
        VkRenderPassCreateInfo ci;
        memset(&ci, 0, sizeof ci);
        ci.sType = VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO;
        ci.attachmentCount = 1;
        ci.pAttachments = &a;
        ci.subpassCount = 1;
        ci.pSubpasses = &sp;
        VkRenderPass rp;
        VkResult r = vkCreateRenderPass(g_dev, &ci, NULL, &rp);
        if (r != VK_SUCCESS) {
            printf("FAILED vkCreateRenderPass = %d (iteration %d)\n", (int)r, i);
            fflush(stdout);
            return (void*)1;
        }
        vkDestroyRenderPass(g_dev, rp, NULL);
    }
    return NULL;
}

int main(int argc, char** argv) {
    int threads = argc > 1 ? atoi(argv[1]) : 2;
    if (argc > 2) g_iters = atoi(argv[2]);
    if (threads < 1 || threads > MAX_THREADS || g_iters < 1) {
        printf("threads 1 to %d, iterations at least 1\n", MAX_THREADS);
        return 2;
    }

    VkApplicationInfo app;
    memset(&app, 0, sizeof app);
    app.sType = VK_STRUCTURE_TYPE_APPLICATION_INFO;
    app.apiVersion = VK_API_VERSION_1_0;
    VkInstanceCreateInfo ici;
    memset(&ici, 0, sizeof ici);
    ici.sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO;
    ici.pApplicationInfo = &app;
    VkInstance inst;
    if (vkCreateInstance(&ici, NULL, &inst) != VK_SUCCESS) { printf("FAILED vkCreateInstance\n"); return 2; }
    uint32_t n = 1;
    VkPhysicalDevice phys;
    VkResult er = vkEnumeratePhysicalDevices(inst, &n, &phys);
    if ((er != VK_SUCCESS && er != VK_INCOMPLETE) || n == 0) { printf("FAILED: no device\n"); return 2; }
    VkPhysicalDeviceProperties props;
    vkGetPhysicalDeviceProperties(phys, &props);

    /* The loader answers this with the layers it enabled on the instance,
     * those VK_INSTANCE_LAYERS named included, so the output says whether
     * the run was under the validation layer. */
    VkLayerProperties layers[32];
    uint32_t nl = 32;
    vkEnumerateDeviceLayerProperties(phys, &nl, layers);
    printf("device: %s, driver version 0x%x, %d threads x %d render passes, layers:",
           props.deviceName, props.driverVersion, threads, g_iters);
    if (nl == 0) printf(" none");
    for (uint32_t i = 0; i < nl; i++) printf(" %s", layers[i].layerName);
    printf("\n");
    fflush(stdout);

    float prio = 1.0f;
    VkDeviceQueueCreateInfo q;
    memset(&q, 0, sizeof q);
    q.sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO;
    q.queueCount = 1;
    q.pQueuePriorities = &prio;
    VkDeviceCreateInfo dci;
    memset(&dci, 0, sizeof dci);
    dci.sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO;
    dci.queueCreateInfoCount = 1;
    dci.pQueueCreateInfos = &q;
    if (vkCreateDevice(phys, &dci, NULL, &g_dev) != VK_SUCCESS) { printf("FAILED vkCreateDevice\n"); return 2; }

    pthread_t th[MAX_THREADS];
    for (int i = 0; i < threads; i++)
        if (pthread_create(&th[i], NULL, worker, NULL) != 0) { printf("FAILED pthread_create\n"); return 2; }
    int bad = 0;
    for (int i = 0; i < threads; i++) {
        void* r;
        pthread_join(th[i], &r);
        if (r) bad = 1;
    }
    vkDestroyDevice(g_dev, NULL);
    vkDestroyInstance(inst, NULL);
    printf("%s\n", bad ? "FAILED" : "ok");
    return bad;
}
