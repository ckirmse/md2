#!/usr/bin/env python3
"""Regenerate the central Types.luau files: consumer-facing interfaces for cross-module singletons.

Types.luau exists to break the type-import cycle in each realm:
- server: the initClass-injected singletons (gameController, itemManager, ...) cannot be
  required from most files for their typeof-based types without recreating the module cycles
  that dependency injection removed.
- client: modules in require cycles declare `local screenGuiManager` at module scope and
  assign it with a lazy require inside init(); those locals are typed through
  src/client/Types.luau for the same reason.

This script derives a methods-only interface for each listed singleton from its annotated
`function X.name(self: X, ...): R` definitions.

Run from the repo root after changing any method signature in the source files:
    python3 tools/generate_types.py
Then re-run luau-lsp analysis (see CLAUDE.md) to confirm zero diagnostics.

Rules enforced here:
- Only methods (first param `self: X`) are exported; constructors/initClass are wiring, not API.
- A method definition without a return annotation is emitted as `-> ()`; annotate the
  definition if it returns values (the analyzer will catch callers if you forget).
- Signatures may only reference builtin/Roblox types; a qualified type like `Foo.Bar`
  would require Types.luau to require realm modules (recreating cycles), so it is an error.
"""
import re
import sys
import os

ROOT = os.path.join(os.path.dirname(__file__), "..")

SERVER_SINGLETONS = [
    "GameController",
    "ItemManager",
    "PlotsManager",
    "PickupMixin",
    "RideMixin",
    "FtueManager",
    "ContextualFtueManager",
    "IslandManager",
    "MutationStoreManager",
    "VanityStoreManager",
    "FirstSessionOfferManager",
    "PlayerData",
]

CLIENT_SINGLETONS = [
    "CameraManager",
    "ClientAnalyticsManager",
    "ClientAudioManager",
    "ClientBuyStore",
    "ClientConsumableCropManager",
    "ClientCrystalManager",
    "ClientDragonManager",
    "ClientEventHandlers",
    "ClientFtueManager",
    "ClientIndexManager",
    "ClientMergeController",
    "ClientNamePlateManager",
    "ClientOptionsManager",
    "ClientPlayerAnimationManager",
    "ClientPlayerAttributesManager",
    "ClientRideController",
    "ClientSellStore",
    "ClientShadowManager",
    "ClientTradePlayerList",
    "ClientTradingManager",
    "CustomProximityPrompt",
    "ClientVanityExpansionsManager",
    "ClientVanityFencesManager",
    "ClientVanityPlotsManager",
    "ClientVanityPreviewManager",
    "ClientVanityUnlockedManager",
    "OverlayTracker",
    "ScreenGuiManager",
    "Teleporters",
]

SERVER_HEADER = """--!strict

--[[
	Central type module: every type used across module boundaries lives here, so any file can
	annotate cross-module values without requiring the module that implements them (which would
	recreate the require cycles that dependency injection removed). Types.luau must never require
	another server module.

	Two sections:
	- HAND-MAINTAINED (top): the class-hierarchy interfaces (Item/BaseObject/DataType/ItemMover
	  families). Subclass types compose by intersection and list only members new to that class;
	  see CLAUDE.md "How the class hierarchies are typed".
	- GENERATED (below the marker): consumer interfaces for the initClass-injected singletons and
	  PlayerData, derived from their annotated definitions by tools/generate_types.py. The values
	  still arrive untyped through initClass(deps), so these are a promise kept in sync by
	  regenerating after signature changes, not something the solver checks.
]]

"""

CLIENT_HEADER = """--!strict

--[[
	Central client type module: types used across client module boundaries live here, so a module
	can annotate a lazily-required singleton (the cycle-breaking `local x` assigned inside init())
	without a module-scope require of the module that implements it. Types.luau must never require
	another client module.

	Two sections:
	- HAND-MAINTAINED (top): interface types for classes whose instances cross module boundaries
	  (TargetBase, CustomProximityPrompt, ...) and shared protocols (Overlay, OverlayNotifier).
	- GENERATED (below the marker): consumer interfaces for the lazily-required singletons,
	  derived from their annotated definitions by tools/generate_types.py. The lazy requires still
	  return untyped-through-annotation values, so these are a promise kept in sync by
	  regenerating after signature changes, not something the solver checks.
]]

"""

REALMS = {
    "server": {
        "src": os.path.join(ROOT, "src", "server"),
        "singletons": SERVER_SINGLETONS,
        "header": SERVER_HEADER,
    },
    "client": {
        "src": os.path.join(ROOT, "src", "client"),
        "singletons": CLIENT_SINGLETONS,
        "header": CLIENT_HEADER,
    },
}

GENERATED_MARKER = "-- ===== GENERATED SECTION -- everything below is written by tools/generate_types.py; do not edit by hand ====="

def parse_methods(cls: str, path: str):
    methods = {}
    problems = []
    for lineno, line in enumerate(open(path).read().split("\n"), 1):
        m = re.match(rf"^function {cls}\.(\w+)\((.*)$", line)
        if not m:
            continue
        name, rest = m.group(1), m.group(2)
        if not rest.startswith(f"self: {cls}"):
            continue  # static / constructor / initClass: not part of the consumer API
        # split params from return annotation at the closing paren of the parameter list
        depth = 1
        for i, ch in enumerate(rest):
            if ch == "(":
                depth += 1
            elif ch == ")":
                depth -= 1
                if depth == 0:
                    break
        else:
            problems.append(f"{path}:{lineno}: could not parse parameter list for {name}")
            continue
        params = rest[:i]
        # varargs in type position need a type: `...` / `...: any` -> `...any`
        params = re.sub(r"\.\.\.(: (any))?$", "...any", params)
        ret = rest[i + 1:].strip()
        ret = ret[1:].strip() if ret.startswith(":") else "()"
        if not (ret.startswith("(") and ret.endswith(")")) :
            # single return type; parenthesize multi-returns as written
            pass
        # signatures may reference other central types as Types.Foo; inside Types.luau the
        # qualifier drops away
        params = re.sub(r"\bTypes\.(\w+)", r"\1", params)
        ret = re.sub(r"\bTypes\.(\w+)", r"\1", ret)
        qualified = re.findall(r"\b([A-Z]\w*)\.\w+", params + " " + ret)
        bad = [q for q in qualified if q not in ("Enum",)]
        if bad:
            problems.append(f"{path}:{lineno}: {name} references module-qualified type(s) {bad}; Types.luau cannot require realm modules")
        methods[name] = (params, ret)
    return methods, problems

def generate(realm: str) -> bool:
    cfg = REALMS[realm]
    src, singletons, header = cfg["src"], cfg["singletons"], cfg["header"]
    out_path = os.path.join(src, "Types.luau")
    # preserve the hand-maintained section of the existing file
    hand = ""
    if os.path.exists(out_path):
        existing = open(out_path).read()
        if GENERATED_MARKER in existing:
            hand = existing.split(GENERATED_MARKER)[0]
            hand = hand[len(header):] if hand.startswith(header) else hand
    out = [header + hand + GENERATED_MARKER + "\n"]
    all_problems = []
    for cls in singletons:
        path = os.path.join(src, cls + ".luau")
        methods, problems = parse_methods(cls, path)
        all_problems.extend(problems)
        out.append(f"export type {cls} = {{")
        for name in sorted(methods):
            params, ret = methods[name]
            ret_s = ret if ret.startswith("(") else ret
            out.append(f"\t{name}: ({params}) -> {ret_s},")
        out.append("}")
        out.append("")
    out.append("return {}")
    out.append("")
    if all_problems:
        print(f"REFUSING to write {out_path}:", file=sys.stderr)
        for p in all_problems:
            print("  " + p, file=sys.stderr)
        return False
    with open(out_path, "w") as f:
        f.write("\n".join(out))
    print(f"wrote {out_path} with {len(singletons)} interfaces")
    return True

def main():
    realms = sys.argv[1:] or list(REALMS)
    ok = True
    for realm in realms:
        ok = generate(realm) and ok
    if not ok:
        sys.exit(1)

if __name__ == "__main__":
    main()
