# Grain Rot — Quickslots 1–0 z przedmiotami fizycznymi

**v0.3.0-unified-physics** — 10 prawdziwych quickslotów broni/przedmiotów + współdzielona warstwa przechowywania obiektów podnoszonych na PPM. Osobny system **Junk Slots, M4/M5, G/H i HUD J1–J10 usunięty**.

> Wersja eksperymentalna, **host-only** dla fizycznego chowania przedmiotów. Implementacja opiera się na USMAP gry **Helden UE 5.7.4** i natywnych RPC, ale efekt chwytu musi zostać potwierdzony w samej grze. Przed testami **zrób kopię zapisu**.

## Sterowanie

1. **PPM** — normalnie chwyć dowolny obiekt fizyczny, który gra pozwala podnieść.
2. **E, trzymając obiekt na PPM** — znajdź **pierwszy naprawdę wolny quickslot 1–0** (uwzględniając zwykłą broń/ekwipunek oraz inne schowane obiekty). Jeśli miejsca nie ma, przedmiot pozostaje w rękach.
3. Mod wywołuje natywne `HeldenCharacter.ReleaseObject_Server()`. Dopiero po potwierdzeniu zwolnienia przez grę wyłącza fizykę, kolizję i widoczność obiektu. **Nie trzeba używać M4/G ani oddzielnie wybierać Junk Slotu.** Jeśli gra mimo RPC nadal trzyma obiekt, operacja oczekuje na normalne puszczenie PPM i po czasie jest anulowana.
4. **1–0** — wybranie zajętego fizycznym obiektem quickslota przenosi go przed postać i uruchamia **`HeldenCharacter.GrabObject_Server(InGrabData)`**, aby chwycił go natywny system PPM. Gdy gracz trzyma obiekt i przełącza na inny slot, mod stara się ponownie schować poprzedni do tego samego miejsca.
5. **E na aktualnie wyjętym obiekcie** — schowaj go z powrotem do przypisanego quickslota. **Zwykłe puszczenie PPM** pozostawia fizyczny obiekt w świecie i zwalnia jego slot.

Przedmioty fizyczne są oznaczone na **oryginalnym pasku 1–0** jako `1+`, `5+`, itd. Jeśli zapis wskazuje na przedmiot, którego aktora silnik jeszcze nie załadował, może być widoczny `1?`. **Nie ma nowego paska ani dziesięciu osobnych Junk Slots**.

## Wspólne miejsce dla broni i obiektów fizycznych

`HeldenPhysicsActor` (obiekt podnoszony siłą/fizyką) **nie jest** `HeldenEquipableItem` (natywna broń/przedmiot ekwipunku). Ze względów bezpieczeństwa mod **nie umieszcza obcego UClass w natywnej tablicy `ItemSlots`**. Zajmuje odpowiedni indeks w pomocniczej warstwie rezerwacji i wizualnie oznacza to samo miejsce na istniejącym HUD. Dlatego broń zawsze ma pierwszeństwo w swoim natywnym slocie. Konflikt zajętości powoduje przeniesienie schowanego fizycznego obiektu do kolejnego wolnego slotu; jeśli wszystkie miejsca są zajęte, mod próbuje oddać obiekt do świata zamiast usuwać go.

Podczas operacji nigdy nie wykonuje `PhysGrabData.Target=nil`, `GrabPhysHandle:ReleaseComponent()` ani `AttachToActor` na przedmiocie trzymanym na PPM — ryzykowne operacje z wcześniejszego wydania mogły kończyć się Fatal Error.

## Zapis / respawn

- **Natywna broń w slotach 5–0:** nadal działa mechanizm rozszerzania `InventorySettings.SlotSettings` na domyślnej klasie postaci przed wczytaniem/respawnem, z kopią w `%LOCALAPPDATA%\\Helden\\Saved\\GrainRotQuickJunk_slot<N>_host.txt`.
- **Fizyczne obiekty w 1–0:** oddzielna kopia powiązana z numerem i nazwą zapisu: `%LOCALAPPDATA%\\Helden\\Saved\\GrainRotQuickJunk_physics_slot<N>_host.txt`. Rejestruje slot, tożsamość aktora, klasę, pozycję i kompletny szablon natywnego chwytu.
- Po wczytaniu lub zmianie mapy mod próbuje **odszukać istniejący obiekt** i związać go z quickslotem, bez klonowania. Jeśli gra nie zapisała fizycznego aktora albo odtworzyła go z inną tożsamością, rekord pozostaje oczekujący (`?`). **Nie tworzymy na ślepo kopii**, bo mogłoby to zduplikować loot lub zepsuć zapis. Taka sytuacja wymaga rzeczywistego logu gry.
- Podczas respawnu w tej samej mapie przedmioty wcześniej schowane pozostają przypisane do istniejących aktorów; ich odzyskiwanie po zmianie mapy zależy od natywnego zapisu tych obiektów. **Nie ma gwarancji pełnej trwałości fizycznego lootu między mapami**, ani potwierdzenia działania dla zdalnych klientów co-op.

## Inne funkcje

- Sloty `5–0` nadal używają natywnego `InventoryAction_Server(InIdx:int)`, a sloty `1–4` obsługuje gra. Mod korzysta z post-hooka natywnego wyboru (nie rejestruje podwójnie klawiszy `1–4`).
- Schowana broń ze slotów `5–0` pozostaje niewidoczna na postaci, dopóki nie jest wyposażona.
- Przy wejściu do windy host uzupełnia trwałość broni dystansowych; wyszukiwanie kontrolerów i wind jest ograniczone do 2-sekundowych interwałów.
- Kontynuowana zgodność z `ExpeditionSaver 0.5.1` i `GrainRotQOL 0.1.2`. Nie używaj jednocześnie `GrainRotDepthKeeper` i `ExpeditionSaver`, ponieważ oba ingerują w głębokość ekspedycji.

## Instalacja i test

1. Jeśli nadal używasz **starego Junk Slots**, najpierw wyciągnij z niego wszystkie schowane fizyczne przedmioty **w starej wersji moda i przed zamknięciem gry**. W przeciwnym razie pamięć starego systemu utraci do nich referencje po restarcie.
2. Zamknij grę, zrób kopię zapisu i **usuń cały poprzedni folder** `Helden/Binaries/Win64/ue4ss/Mods/GrainRotQuickJunk` (nie kopiuj plików na stare moduły).
3. Wypakuj nowy `GrainRotQuickJunk-v0.3.0-unified-physics.zip` tak, by folder `GrainRotQuickJunk` znalazł się w `ue4ss/Mods/`.
4. Sprawdź na **hoście**, na zbędnym przedmiocie: PPM, E, pojawienie się `+` na wolnym slocie, wybór slotu, chwyt, ponowne E i celowe puszczenie PPM. Następnie osobno sprawdź zwykłą broń, zapis oraz respawn.

W logu `UE4SS.log` szukaj `[GrainRotQuickJunk] [PHYS]` i `[PHYS SAVE]` oraz komunikatów `native_grab_not_confirmed`, `native_release_timeout_release_RMB` i `saved_physics_actor_not_loaded`. Zgłoś je razem z logiem, jeśli w grze native RPC nie wywołuje oczekiwanego chwytu.

**GitHub Actions sprawdza składnię, mocki Lua i poprawność paczki ZIP, ale nie mierzy FPS i nie uruchamia Grain Rot.** Zrzut USMAP i ObjectDump jest w [Grain-Rot-Mod-Data-Base](https://github.com/SirRosa/Grain-Rot-Mod-Data-Base).
