#ifndef AETHER_CALLBACKS_H
#define AETHER_CALLBACKS_H

/* @c_callback functions by name (#2297); see aether_callbacks.c.
 *
 * aether_callback_register: record `fn` under `name` (the last registration
 * of a name wins). Generated code calls it from a constructor for each
 * @c_callback function.
 * aether_callback_lookup: the function registered under `name`, or NULL. */
void aether_callback_register(const char* name, void* fn);
void* aether_callback_lookup(const char* name);

/* Why a callback gave its failure value (#3426), for the C that called it,
 * on the same thread: the callback sets it as it refuses, and the caller,
 * which clears it (NULL) before the call, reads it after. The text is
 * copied, up to 511 bytes, and holds until the thread's next set. It lives
 * here, beside the registry the caller already reaches, so that a module
 * explaining a refusal links nothing of its caller's: std.cryptography's
 * pure TLS server, which explains why a chain and key are refused, used to
 * call into the HTTP server for it and so linked the whole of it. */
void aether_callback_set_reason(const char* reason);
const char* aether_callback_reason(void);

#endif /* AETHER_CALLBACKS_H */
