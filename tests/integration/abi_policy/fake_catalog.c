/* A library with a hand-made catalog (#2957), so the importer's checks can
 * be shown on catalogs no Aether of this version writes: another major, a
 * duty this importer does not know, a newer minor with nothing new to do,
 * and shared-runtime libraries of another runtime ABI or of none recorded.
 * Built with -DSCHEMA="..." -DREQUIRES="..." (NULL for none) and, for a
 * shared-runtime one, -DSHARED -DRUNTIME_ABI="..." (NULL for none). */
#include <stddef.h>
#include "aether_lib_meta.h"

#ifndef REQUIRES
#define REQUIRES NULL
#endif
#ifndef RUNTIME_ABI
#define RUNTIME_ABI NULL
#endif
#ifdef SHARED
#define RUNTIME "shared"
#else
#define RUNTIME NULL
#endif

int aether_add(int a, int b) { return a + b; }
int aether_fake_outcome(void) { return 0; }
const char* aether_fake_outcome_text(void) { return ""; }

static const AetherLibFunction fns[] = {
    { "add", "aether_add", "(int, int) -> int", "fake.ae", 1 },
};

static const AetherLibMeta meta = {
    SCHEMA, "9.9.9", "fake.ae", 1, fns, 0, NULL, 0, NULL, 0, NULL,
    NULL, NULL, NULL, RUNTIME, NULL, 0, NULL, NULL, "aether_fake_outcome",
    1, RUNTIME_ABI, REQUIRES,
};

const AetherLibMeta* aether_lib_meta(void) { return &meta; }
