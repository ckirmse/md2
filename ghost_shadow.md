# Item Ghost/Shadow proposal

## problem: replicating a floating, wing-flapping dragon takes a ton of bandwidth

## proposed solution: only replicate, at low time-fidelity, an invisible part (for streaming sake)
## client creates a ghost model

Clients know which dragons they care about by the existence/disappearance of a shadow part, with an attribute of its itemId.
Clients then request the info from the server about the item, and subscribes to changes.

The server sends precise location/orientation changes frequently (or higher level plans?), and client moves the ghost appropriately

# Issue: clients need to ride dragons (ghosts)

If a client is allowed to ride a dragon, when it begins riding, it can tell the server where the dragon is, and server moves the shadow and
echoes the data to other listening clients

# Issue: what does a player look like while riding a dragon (shadow)?

# Issue: inventory/holding items

When being held by a player, a normal model/instance will be parented by a tool and held in backpack (or hand) same as any other item
