# Grain Rot — Quickslots & Junk Slots

UE4SS Lua mod (work in progress) for Grain Rot / Helden.

## Scope
- Extend quickslots from 4 to 10, hotkeys 1–9 and 0.
- Add up to 10 Junk Slots for genuinely retained items (Mouse4/G store, Mouse5/H retrieve; < / > to switch), with one compact HUD indicator.
- Refill firearm durability/ammunition on return to the elevator.

## Development status
**Research/implementation in progress; NOT a working release.**
The source must be checked against the actual `Helden` UE5.7 reflection dump and then verified during a real host/client session. Lua syntax and mock tests cannot establish native inventory allocation, UI, input conflicts, or game replication.

Reference: [Grain-Rot-Mod-Data-Base](https://github.com/SirRosa/Grain-Rot-Mod-Data-Base).

Safety priorities: no item destruction, no simulated save guarantee, no direct arbitrary TArray writes without a verified native interface, do not refill remotely on clients, bound polling, and logging of disabled unsupported features.
