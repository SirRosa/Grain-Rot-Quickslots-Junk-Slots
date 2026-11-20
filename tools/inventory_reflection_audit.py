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

print("\nNATIVE ACTION METHODS / EXACT UFUNCTION PROPERTIES")
import re
patterns=("inventory","slot","equip","holster","grab","drop","throw","pickup","switch","select","release")
prefixes=("/Script/Helden.HeldenCharacter:", "/Script/Helden.HeldenPlayerController:",
          "/Script/Helden.HeldenInventorySlotWidget:", "/Script/Helden.HeldenInputIconWidget:")
for line in txt.splitlines():
    if line.startswith("[") and "Function " in line and any(p in line for p in prefixes):
        target=line.lower()
        if any(p in target for p in patterns): print(line[:300])
    elif line.startswith("[") and "Property " in line and any(p in line for p in prefixes):
        target=line.lower()
        if any(p in target for p in patterns): print(line[:300])

print("\nEXTRA INVENTORY MODEL RENDERING DETAILS")
for key in ("HeldenEquipableItem", "HeldenCharacter","HeldenPlayerController","HeldenInventroySlotSetting",
            "HeldenInventorySlotComponent","HeldenRangedWeapon","HeldenMeleeWeapon",
            "HeldenItemtSlot","HeldenEquipedItem","HeldenItemSlot"):
    v=data["structs"].get(key)
    if v:
        props=v.get("properties",[])
        keep=("item","slot","equip","mesh","render","attach","visible","current","active","select","inventory","socket","hand","weapon","holster")
        if key in ("HeldenEquipableItem","HeldenInventroySlotSetting","HeldenInventorySlotComponent"):
            selected=props
        else:
            selected=[q for q in props if any(w in q["name"].lower() for w in keep)]
        print(key, "parent=",v.get("parent"), "selected=",json.dumps(selected,ensure_ascii=False)[:22000])
print("\nEQUIP ITEM METHODS")
keys2=("/Script/Helden.HeldenEquipableItem:", "/Script/Helden.HeldenInventorySlotComponent:",
       "/Script/Helden.HeldenRangedWeapon:", "/Script/Helden.HeldenCharacter:")
for line in txt.splitlines():
    if "Function " in line and any(k in line for k in keys2):
        if any(term in line.lower() for term in ("equip","slot","attach","detach","hide","visible","item","holster","activate","select","inventory","bind")):
            print(line[:300])

print("\nHOLSTER ENUM")
for key in ("EHeldenItemHolsterState","EHeldenInputIconType"):
    print(key, json.dumps(data["enums"].get(key),ensure_ascii=False)[:6000])

print("\nPERSISTENCE AND EQUIP REFLECTION")
for name in ("HeldenSaveGame","HeldenItemSaveData","HeldenCharacterSaveData","HeldenPlayerSaveData",
             "HeldenSaveGameMetaData","HeldenEquipableItem","HeldenCharacter","HeldenGameInstance",
             "HeldenItemtSlot","HeldenInventroySlot","HeldenInventroySlotSetting"):
    obj=data["structs"].get(name)
    if obj:
        print(name,json.dumps(obj,ensure_ascii=False)[:22000])
print("\nSAVE AND EQUIP GAME FUNCTIONS")
for line in txt.splitlines():
    if "Function " in line and any(x in line for x in (
            "/Script/Helden.HeldenSaveGame:", "/Script/Helden.HeldenGameInstance:",
            "/Script/Helden.HeldenCharacter:", "/Script/Helden.HeldenPlayerController:",
            "/Script/Helden.HeldenEquipableItem:")) and any(k in line.lower() for k in (
                 "save","load","equip","inventory","item","pickup","slot","spawn","respawn","interact","serialize")):
        print(line[:280])

print("\nPLAYER BP CDO / CLASS DUMP")
for line in txt.splitlines():
    if any(k in line for k in ("Default__BP_HeldenPlayerCharacter", "BP_HeldenPlayerCharacter_01_C",
                               "Default__HeldenCharacter", "Default__BP_HeldenCharacter")):
        if any(word in line for word in ("Default__", "Class ", "InventorySettings", "ItemSlots")):
            print(line[:350])

print("\nPHYSICS GRAB UFUNCTION SIGNATURES AND NATIVE STATE")
lines=txt.splitlines()
for idx,line in enumerate(lines):
    if "Function /Script/Helden." in line and any(k in line for k in (
        "GrabObject_Server", "GrabObject_Auth", "ReleaseObject_Server",
        "ReleaseObject_Auth", "DropItem_Server", "InventoryAction_Server",
        "Interact_Server", "StartPhys", "EndPhys", "SetPhysGrab",
        "SetGrab", "GrabObject", "ReleaseObject")):
        print("FUNCTION",line[:330])
        for follow in lines[idx+1:idx+16]:
            if "Function " in follow or "Class " in follow: break
            if any(x in follow for x in ("Property ", "Param", "InObject", "InTarget", "Target", "HitResult", "Object", "Phys")):
                print("  ",follow[:310])
for key in ("HeldenPhysGrabData","HeldenPhysicsActor","EHeldenPhysGrabState","EHeldenCharacterControllerState"):
    item=data["structs"].get(key) or data["enums"].get(key)
    print("TYPE",key,json.dumps(item,ensure_ascii=False)[:17000])

print("\nGRAB STRUCT EXACT MATERIALIZATION AND HUD WIDGET FIELDS")
for key in ("HeldenNetworkTimer","Vector_NetQuantize","Vector_NetQuantizeNormal",
            "HeldenInventorySlotWidget","HeldenInventoryWidget","HeldenInputIconWidget",
            "HeldenPhysicsActor","HeldenActorSaveData"):
    v=data["structs"].get(key)
    if v: print("STRUCT",key,json.dumps(v,ensure_ascii=False)[:11000])

print("\nUI INSPECTION (phys quickbar icon candidates)")
for key,v in data["structs"].items():
    lower=key.lower()
    if any(k in lower for k in ("inventoryslot", "inventorywidget", "physgrab", "itemasset",
                                  "constructasset", "physicsasset", "moneywidget", "itemicon",
                                  "iconwidget", "inventoryelement", "itemdisplay",
                                  "quickslot")):
        if any(q in lower for q in ("slot","widget","asset","icon")):
            print("FIELD",key,json.dumps(v,ensure_ascii=False)[:9000])
for idx,line in enumerate(txt.splitlines()):
    low=line.lower()
    if "function " in low and any(p in low for p in ("wbp_inventoryslot",
            "heldeninventoryslotwidget","heldeninventorywidget","heldenphysicsactor:",
            "heldenconstructassetdata", "heldeninspectwidget")):
        if any(k in low for k in ("icon", "item", "set", "brush", "image","texture","render",
                                   "update","grab","inspect","asset","construct","widget")):
            print("UFUNCTION",line[:250])
print("\nUMG IMAGE AND BRUSH FUNCTIONS")
for line in txt.splitlines():
    low=line.lower()
    if "function /script/umg.image:" in low and any(k in low for k in ("setbrushfrom","setbrush","setopacity")):
        print("UFUNCTION",line[:260])
