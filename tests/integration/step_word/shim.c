/* The step bits of this runtime copy's one word (aether_resource_caps.h). */
#include "aether_resource_caps.h"

int probe_step_bits(void) {
    return (int)(atomic_load_explicit(&aether_caps_slow, memory_order_relaxed) & AETHER_CAPS_STEP_BITS);
}
