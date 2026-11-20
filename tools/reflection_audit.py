#!/usr/bin/env python3
"""Produce concise evidence from the actual Helden 5.7 reflection archive."""
import gzip, io, json, pathlib, re, sys
root=pathlib.Path(sys.argv[1]) if len(sys.argv)>1 else pathlib.Path("knowledge")
with gzip.open(root/"data/current-schema.json.gz","rt",encoding="utf-8") as f: db=json.load(f)
prefixes=("HeldenCharacter","HeldenEquipableItem","HeldenItemtSlot","HeldenRangedWeapon",
"HeldenPlayerController","HeldenInventoryWidget","HeldenInventorySlotWidget",
"HeldenPlayerHUDWidget","HeldenHUD","HeldenElevator","HeldenDungeonElevator",
"HeldenInventroySlotSetting","HeldenInventorySlotComponent","HeldenPhysicsActor",
"HeldenInteractableObject","HeldenPhysicsGrabData")
print("SCHEMA TARGET CLASSES")
for k,v in db["structs"].items():
    if k in prefixes:
        print(k,"parent",v.get("parent"),"props",
              [(p.get("name"),p.get("type"),p.get("inner"),p.get("struct")) for p in v.get("properties",[])])
print("RELATED CLASS NAMES")
print([k for k in db["structs"] if re.search(r"(Grab|Holding|Quick|Inventory|ItemSlot|Hand|InputAction)",k,re.I) and ("Helden" in k or k.startswith("BP_"))][:160])
print("ENUM")
for k,v in db["enums"].items():
    if k.startswith("EHelden") and re.search(r"Inventory|Item|Hand|Grab|Equip|Input|Weapon|Holster",k,re.I):
        print(k,v)
print("DUMP METHODS")
parts=sorted((root/"data").glob("UE4SS-ObjectDump.txt.gz.part*"))
with gzip.open(io.BytesIO(b"".join(p.read_bytes() for p in parts)),"rt",encoding="utf-8",errors="replace") as f:
    for line in f:
        if "Function " not in line: continue
        m=re.search(r"Function /Script/Helden\.(\w+):(\w+)",line)
        if not m: continue
        owner,method=m.groups()
        if owner in prefixes and re.search(r"(Inventory|Item|Grab|Holster|Equip|Select|Slot|Place|Drop|Hold|Phys|Durab|Weapon|Input|Move)",method,re.I):
            print(owner+":"+method)
