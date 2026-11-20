#!/usr/bin/env python3
"""Read-only candidate discovery; metadata is not proof of callable native behaviour."""
import gzip, json, pathlib, re, sys
root=pathlib.Path(sys.argv[1]) if len(sys.argv)>1 else pathlib.Path("knowledge")
with gzip.open(root/"data/current-schema.json.gz","rt",encoding="utf-8") as f: db=json.load(f)
rx=re.compile(r"(HeldenCharacter|HeldenEquipableItem|HeldenItemtSlot|HeldenRangedWeapon|Inventory|Quick.?Slot|Equip|Hand|Arm|Elevator|HUD|ItemSlot)",re.I)
interesting=[]
for k,v in db["structs"].items():
    if rx.search(k) and ("Helden" in k or re.search("Quick|Inventory|HUD",k,re.I)):
        interesting.append((k,v))
print("STRUCT CANDIDATES",len(interesting))
for k,v in interesting[:110]:
    s=json.dumps(v,ensure_ascii=False)
    print("STRUCT",k,s[:2600])
print("ENUM CANDIDATES")
for k,v in db["enums"].items():
    if re.search(r"Slot|Item|Equip|Hand|Arm|Input",k,re.I):
        print("ENUM",k,json.dumps(v,ensure_ascii=False)[:1200])
print("DUMP FUNCTION CANDIDATES")
parts=sorted((root/"data").glob("UE4SS-ObjectDump.txt.gz.part*"))
with gzip.open(__import__("io").BytesIO(b"".join(p.read_bytes() for p in parts)),"rt",encoding="utf-8",errors="replace") as f:
    lines=0
    for line in f:
        if "Function " not in line: continue
        if re.search(r"(HeldenCharacter|HeldenPlayerController|HeldenEquipableItem|HeldenRangedWeapon|HeldenItemtSlot|HeldenDungeonElevator|HeldenItemSlot|HeldenInventory|HeldenHUD|QuickSlot|InventorySlot)",line,re.I):
            print(line.rstrip()[:500])
            lines+=1
            if lines>=400: break
print("DUMP functions shown",lines)
