# Real-session audit: UE4SS(5).log (20 Nov 2026)

## Evidence
- Runtime is **UE4SS 3.0.1 Beta #0, source commit `1c1a1497`**.
- At 19:22:12 the mod is installed and loaded. Both mouse buttons, G/H, 1-0, comma/period binds register successfully.
- Hooks `HeldenPlayerController.InventoryAction_Server` and `HeldenCharacter.GrabObject_Server` register, and the second receives real callbacks.
- From 19:22:47 onward, pressing mouse / G/H outputs `authoritative host pawn unavailable` many times; no `PROBE native inventory slots` and no `NATIVE` extension output. Therefore the original poll never made it through real pawn resolution.
- In the *same* session, `ExpeditionSaver` reports `host=true, mode=1, playerControllers=1`, so neither missing UE4SS nor lack of server authority explains the error.
- Large `FName_Constructor.lua` AOB retry logs did not block UE4SS and the Lua mods from loading. Do not conflate with missing player pawn.

## Corrections in v0.2.1-contextfix
1. Replaced the string-only `UObject:IsA` dependency with a `HeldenCharacter` structural check on the PC's actual pawn: `CharacterStats`, `InventorySettings`, and `ItemSlots`. Blueprint-derived player characters qualify. Also falls back to `HeldenPlayerController.LastPlayerChar` when `GetPawn` is empty or references `SoulCharacter`.
2. Checks same-world real `GameMode` plus `HasAuthority` where available, without guessing multiplayer writes.
3. Produces periodic `DIAG controllers=N ... source= ... world= ... host=...` every six seconds, and logs every relevant native slot attempt and its rejection reason. A future game log must show these, unlike the failing build.
4. Confirmed **from the exact installed source** rather than only public docs: [LuaTArray.cpp lines 232–251](https://github.com/UE4SS-RE/RE-UE4SS/blob/1c1a1497/UE4SS/src/LuaType/LuaTArray.cpp#L232-L251) calls `FScriptArray::AddZeroed` when an indexed access uses an index beyond the current array length. Do **not** access a nonexistent element just to probe it; write sequentially and verify `#arr`.
5. Confirmed [LuaUObject.cpp](https://github.com/UE4SS-RE/RE-UE4SS/blob/1c1a1497/UE4SS/src/LuaType/LuaUObject.cpp#L707-L779) accepts a Lua table for struct property setter; [LuaFName.cpp](https://github.com/UE4SS-RE/RE-UE4SS/blob/1c1a1497/UE4SS/src/LuaType/LuaFName.cpp#L46-L98) provides `FName` as a **callable table**, with Lua default `FNAME_Add`. Earlier `type(FName)=="function"` test was wrong and silently blocked slot creation.
6. Added native quickbar UI extension: when `HeldenCharacter.ItemSlots` contains ten verified elements, create six **actual `HeldenInventorySlotWidget`** instances from `HeldenInventoryWidget.SlotWidgetClass` and attach them to native `InventorySlotBox`; never show cosmetic slots unless real capacity exists.
7. BP-derived physics actors are now recognized even if `IsA(string)` fails.

## Acceptance conditions still pending
- Actual log must show: `DIAG controllers=1`, `[QUICK] APPENDED six SlotSettings`, `READY 10/10 native ItemSlots`, `[QUICK UI]` appended six, followed by working key binds, correct item assignment, and native save/reload.
- Two-player network replication, physics storage of the *same* actor (not a clone), item persistence across levels/death, and stable FPS must be tested in game.
- Mock Actions tests validate source-level call sequences only; green CI is **not** confirmation of gameplay.

## Installation/test hygiene
Use a backed-up disposable save; keep prior `GrainRotQuickJunk` folder replaced (not nested); test host only first. Do not use valuable items in Junk Slots until persistence and recovery have been verified. Send the new UE4SS.log after loading the new version, especially `DIAG`, `NATIVE`, `[QUICK UI]`, `JUNK` lines.
