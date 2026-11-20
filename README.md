# Grain Rot — Quickslots & Junk Slots

UE4SS Lua mod for **Grain Rot / Helden**. Active development, **v0.1.0-alpha**.

## Requested target

| Feature | Goal | Current implementation |
|---|---|---|
| Quickslots | 4 → 10; keys `1`–`9`, `0` | Native `1`–`4` untouched; `5`–`0` diagnostics only, not extra inventory |
| Junk Slots | 10 hidden item slots | Transaction/rollback model for 10 item identities; no transfer yet |
| Store / retrieve | Mouse4/G and Mouse5/H, while carrying object with RMB | Buttons active for read-only grab detection; no objects moved/destroyed |
| Junk selection | `<` and `>` | Shift+comma / Shift+period cycle 1–10, logged, not HUD |
| Junk HUD | One genuine inventory slot at bottom-right | Game's UMG slot widget identified; not created yet |
| Firearms | Refill ammunition/durability at elevator entry | Experimental host-only implementation, pending actual game test |

**Do not mistake CI success for a working 10-slot inventory mod.** The game has a four-element native inventory array. Stock UE4SS Lua exposes its elements but has no documented way to safely append new entries, regenerate replicated native slot components and extend save serialization. See [technical evidence](docs/TECHNICAL_STATUS.md).

## Experimental installation (firearm refill + diagnostics only)

1. Download `GrainRotQuickJunk-v0.1.0-alpha` from the newest successful [GitHub Actions run](https://github.com/SirRosa/Grain-Rot-Quickslots-Junk-Slots/actions/workflows/ci.yml).
2. Extract the artifact ZIP, then the inner mod ZIP.
3. Copy `GrainRotQuickJunk` to the game's UE4SS `Mods` folder, resulting in `Mods/GrainRotQuickJunk/Scripts/main.lua` and `Mods/GrainRotQuickJunk/enabled.txt`.
4. Back up the save, initially run as the host with other inventory-modification mods disabled. Enter the elevator carrying a damaged firearm, exit, then re-enter. Review entries prefixed `[GrainRotQuickJunk]` in UE4SS.log.

Requires the already-working UE4SS v3 setup used for other Grain Rot mods. Do not install the entire `ue4ss` repository folder as a mod.

## Implementation and test discipline

- Derived from [Grain-Rot-Mod-Data-Base](https://github.com/SirRosa/Grain-Rot-Mod-Data-Base), which includes the actual 2026-11-20 Helden UE5.7 reflection and sanitized session logs.
- Refill writes only `HeldenRangedWeapon.ItemDurability` for known equipped/owned items on the authoritative server, only on a new overlap with `HeldenElevator.InteriorCollisionBox`. No constant durability cheat. Same-world and player filtering.
- Inventory RPC and physics grabbing signatures are traced through bounded **read-only hooks**.
- New item storage will only be enabled when host-side ownership transfer, verification, serialization, and multiplayer replication have a proven native mechanism.
- CI: Lua syntax, mock gameplay tests, pure 10-item state-machine tests, ZIP packaging. **No Grain Rot executable runs in Actions.**

See [technical status and test plan](docs/TECHNICAL_STATUS.md).
