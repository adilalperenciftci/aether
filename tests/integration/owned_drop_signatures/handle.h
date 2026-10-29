/* #3413: a C handle whose release takes it typed, as fclose takes a FILE*.
 * Force-included into the generated C (aether.toml), so the probe's
 * `@c_import` extern is the C compiler's to check against this prototype. */
#ifndef OWNED_DROP_HANDLE_H
#define OWNED_DROP_HANDLE_H

typedef struct Handle Handle;

int handle_close(Handle* h);

#endif
