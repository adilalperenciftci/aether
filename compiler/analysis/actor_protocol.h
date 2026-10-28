/* Actor protocols (#385).
 *
 * A protocol names the messages an actor reference may be sent and the order
 * they may come in:
 *
 *     protocol FileWriter {
 *         start -> Open -> writing
 *         writing -> Write -> writing
 *         writing -> Close -> done
 *     }
 *
 *     actor Writer implements FileWriter { receive { ... } }
 *
 * The first transition's state is where a new reference starts; a state with
 * no transition out takes no message. An actor that implements a protocol has
 * a receive arm for every message of it. A reference to it (a `spawn` result,
 * or one typed `actor_ref[Writer]` or `actor_ref[FileWriter]`) is followed
 * through the function that holds it, and a send or ask the protocol does not
 * allow in the state the reference may be in there is an error.
 */

#ifndef AETHER_ACTOR_PROTOCOL_H
#define AETHER_ACTOR_PROTOCOL_H

#include "../ast.h"

/* Records the program's protocols for the lookups below. Called once at the
 * start of type checking; a later call starts again. */
void aether_protocols_collect(ASTNode* program);

/* The protocol named `name`, or NULL. */
ASTNode* aether_protocol_lookup(const char* name);

/* Whether protocol `proto` has a transition on message `msg`. */
int aether_protocol_has_message(ASTNode* proto, const char* msg);

/* The protocol actor `actor` declares it implements, by name, or NULL. */
const char* aether_actor_protocol_name(const ASTNode* actor);

/* Checks the protocols, the actors that implement them and every send or
 * ask through a reference that follows one. Asked of the type-checked
 * program. Returns the number of errors reported. */
int check_actor_protocols(ASTNode* program);

#endif /* AETHER_ACTOR_PROTOCOL_H */
