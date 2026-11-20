# Technical state — 2026-11-20

## Evidence from the real Helden 5.7.4 reflection dump
Source: `SirRosa/Grain-Rot-Mod-Data-Base`, `data/current-schema.json.gz` + segmented UE4SS ObjectDump.
- `HeldenCharacter`: `InventorySettings` (struct `HeldenInventroySettings`), `EquipedItems` (array of UObject), `ItemSlots` (array of `HeldenInventroySlot`), `PhysGrabData` (struct `HeldenPhysGrabData`).
- `HeldenInventroySettings.SlotSettings` is an array of `HeldenInventroySlotSetting`; `HeldenInventroySlot` has only `SlotName`, `SlotComponent`. **These are not the elevator's `HeldenItemtSlot.CurrentItemInSlot`.**
- `HeldenPhysGrabData.Target` is the object currently held with physics grabbing. Check that it is a real actor before any transaction.
- `HeldenPlayerController.InventoryAction_Server` and `HeldenCharacter.GrabObject_Server` appear in the real ObjectDump. Their argument types and side effects are not established by the dump; the mod installs bounded read-only hooks.
- `HeldenInventoryWidget.SlotWidgetClass`, `InventorySlotBox`, `SlotWidgets` and `HeldenHUD.PlayerHudWidget` / `HeldenPlayerHUDWidget.InventoryWidget` exist. Original UMG asset can be reused once constructing/adding children has been verified.
- `HeldenDungeonElevator` inherits `HeldenElevator.InteriorCollisionBox`. Unreal `UPrimitiveComponent.IsOverlappingActor` is used for entry-only trigger (runtime check pending).
- `HeldenRangedWeapon` derives from `HeldenWeapon` -> `HeldenEquipableItem`, with `ItemDurability` and `ItemDurabilityMax`. This representation is also used by the GrainRotQOL reference mod.

## Why this is not yet a 10-slot release
In UE4SS Lua, reflected TArray supports reading and replacing existing elements but **no documented append/resize operation**. Overwriting 4 existing native inventory slots to claim 10 would corrupt inventory. Simply adding 6 icons would not increase capacity. The native `InventoryAction_Server` signature, how item slots are allocated/recreated, and how `ItemSaveData` persists `OwningSlot` need an in-game probe or a compatible native bridge.

Similarly, turning `PhysGrabData.Target` into a hidden world actor without first verifying release, ownership, persistence, reattachment and host/client replication risks deleting items on travel/save/reload. **The alpha build refuses to move any object in response to G/Mouse4 and H/Mouse5.** Keys and selection diagnostics are wired for future implementation.

## Implemented in v0.1.0-alpha
- Keybinds Mouse4/Mouse5, G/H, comma/period, 5–0 (1–4 intentionally remain game-native). Traces button input; no extra inventory exists yet.
- Read-only startup introspection of number of player native slots, HUD slot widgets and current held actor.
- Read-only bounded hooks for `InventoryAction_Server` and `GrabObject_Server` to learn event signatures.
- Host-only firearm refill: on transition from outside to inside `InteriorCollisionBox`, restore `ItemDurability` to `ItemDurabilityMax` only for equipped/owned `HeldenRangedWeapon` actors; read-back verification, no writes to unrelated world objects. One refill per entry, then reset after exit.
- 500 ms polling in game thread; no `os.clock()` for wall time.

## Next stages
1. Live game log: initial inventory/UI slot counts, `InventoryAction_Server` callback argument types and native action for slots 1–4, `GrabObject_Server` callback, `PhysGrabData.Target` under RMB, and `InteriorCollisionBox` overlap on entry.
2. Add 5–0 true inventory indexing via verified native RPC, allocate slots safely, add native slot widgets and verify saves. If Lua cannot resize native TArray, create a small UE4SS C++ bridge or compatible Blueprint asset; don't fake capacity.
3. Implement Junk Slot native ownership transaction for 10 distinct item instances with rollback and persistence across death/map transition. Then render one authentic native `HeldenInventorySlotWidget` at bottom-right and bind selected item.
4. Host/client reload and save tests, no duplicated/lost items, collision and durability tests. Never equate mock Actions with real runtime tests.

## Manual alpha smoke test
Use a backed-up noncritical save, host first with other inventory mods disabled. Enter elevator with damaged firearm, exit and enter again after spending durability. Check UE4SS.log entries with `[GrainRotQuickJunk]`: `PROBE`, `elevator ENTRY`, `REFILL`, and `HOOK`. Test G/Mouse4 while holding item: should log `BLOCKED` and **leave the item unchanged**. After validating, test a separate multiplayer client. No claims of save or multiplayer compatibility yet.
