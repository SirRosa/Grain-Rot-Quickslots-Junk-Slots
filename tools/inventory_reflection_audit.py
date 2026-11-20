#!/usr/bin/env python3
"""Audit only minimal reflected properties relevant to quickbar and crash.
Run from a workspace holding reference database in ./reference.
"""
import gzip,json
from pathlib import Path

p=Path("reference/data/current-schema.json.gz")
with gzip.open(p,"rt",encoding="utf8") as f: data=json.load(f)
need=("HeldenInventorySlotWidget","HeldenInventoryWidget","WBP_InventorySlot",
      "HeldenInventroySlot","HeldenInventroySettings","HeldenInventorySlotComponent",
      "HeldenPlayerController","HeldenCharacter","HeldenPhysGrabData",
      "HeldenPhysicsActor","HeldenPhysicsHandle","HeldenPhysGrabAnimData","HeldenInventoryAction")
for n,v in data["structs"].items():
    if any(n==k or n.endswith("."+k) or k in n and k in ("WBP_InventorySlot",) for k in need):
        print("\nTYPE:",n)
        print(json.dumps(v,ensure_ascii=False)[:15000])
print("\nRELATED KEY/INPUT TYPES")
for n,v in data["structs"].items():
    if any(t.lower() in n.lower() for t in ("HeldenInventorySlotWidget","HeldenInventorySlotComponent","HeldenInput","HeldenPhysGrabInterface")):
        print(n, json.dumps(v,ensure_ascii=False)[:10000])

print('\nOBJECT DUMP METHODS')
parts=b''.join(p.read_bytes() for p in sorted(Path('reference/data').glob('UE4SS-ObjectDump.txt.gz.part*')))
txt=gzip.decompress(parts).decode('utf-8',errors='replace')
keys=('HeldenInputIconWidget','WBP_InventorySlot_C','HeldenPlayerController.InventoryAction','HeldenCharacter.Grab','HeldenCharacter.Drop','HeldenCharacter.Release','HeldenCharacter.Holster','HeldenInventorySlotWidget','HeldenInventoryWidget')
results=[line for line in txt.splitlines() if any(k.lower() in line.lower() for k in keys)]
for line in results[:160]: print(line[:300])
