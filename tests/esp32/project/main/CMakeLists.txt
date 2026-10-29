# The generated program plus the runtime the WASM leg links too, with the
# cooperative scheduler: runtime/coop_runtime_sources.txt is the one list
# both read. The generated C supplies app_main() under ESP_PLATFORM.
set(AE /aether)
file(STRINGS "${AE}/runtime/coop_runtime_sources.txt" AE_RUNTIME REGEX "^[^#]")
list(TRANSFORM AE_RUNTIME PREPEND "${AE}/")
idf_component_register(
    SRCS "/gen/${AE_PROG}.c" ${AE_RUNTIME}
    INCLUDE_DIRS "${AE}/include" "${AE}/runtime" "${AE}/runtime/actors" "${AE}/runtime/scheduler"
                 "${AE}/runtime/utils" "${AE}/runtime/memory" "${AE}/runtime/config"
                 "${AE}/std" "${AE}/std/string" "${AE}/std/io" "${AE}/std/math"
                 "${AE}/std/net" "${AE}/std/collections" "${AE}/std/json")
# No threads, files, sockets or environment yet (FreeRTOS pthreads and lwIP
# are a later step). The scheduler is sized for ~320 KB of DRAM: at the
# defaults its static tables alone are about 10 MB.
target_compile_definitions(${COMPONENT_LIB} PRIVATE
    AETHER_NO_THREADING AETHER_NO_FILESYSTEM AETHER_NO_NETWORKING AETHER_NO_GETENV
    AETHER_NO_SIMD AETHER_NO_AFFINITY AETHER_NO_NUMA
    MAX_CORES=1 QUEUE_SIZE=64 SCHEDULER_DRAIN_BATCH=32 MAX_ACTORS_PER_CORE=256)
target_compile_options(${COMPONENT_LIB} PRIVATE -w)
