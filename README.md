# Grain Rot — Quickslots / Junk Slots

**v0.2.5-compat-persistence** — poprawka oparta na prawdziwym logu UE4SS(5): odnajdywanie BP postaci / LastPlayerChar, weryfikacja natywnych tablic dokładnie w UE4SS 3.0.1 (`1c1a1497`), ponawianie rozszerzenia rzeczywistych slotów oraz budowa paska UI z oryginalnych widgetów gry. **Wciąż wymaga testu w grze — zielony CI nie oznacza, że sloty rzeczywiście się pojawiają.**

[Szczegółowe ustalenia z logu](docs/UE4SS5-REAL-LOG-ROOT-CAUSE.md).

## Poprawka 0.2.5 — zapisywanie slotów 5–0 i zgodność z respawnem

**Wyniki analizy rzeczywistych danych gry:**

- `HeldenSaveGame.ItemSaveData` jest mapą rekordów `HeldenItemSaveData`, z polami `OwningPlayer` i **`OwningSlot` (FName)**. Silnik odtwarza przedmioty przez nazwy slotów, a nie wyłącznie numery ekwipunku.
- Poprzedni mod rozszerzał `InventorySettings.SlotSettings` dopiero na żywej postaci po starcie gry; nowa postać po respawnie / restarcie mogła podczas natywnego ładowania nadal posiadać 4 sloty.
- Teraz mod w pierwszej kolejności ładuje klasę `/Game/Gameplay/Character/BP_HeldenPlayerCharacter_01` i rozszerza jej **Blueprint Class Default Object**, z dokładnymi nazwami `GrainRotQuick5` – `GrainRotQuick10`. Ponawia to przed natywnym `LoadGame` oraz `RespawnCharacter_Server`. Pozostawia cudze układy 10-slotowe bez zmian.
- Dodano plik kopii informacji o dodatkowych przedmiotach, powiązany z numerem zapisu i `MetaData.SaveSlotName`: `%LOCALAPPDATA%\\Helden\\Saved\\GrainRotQuickJunk_slot<N>_host.txt`. Przechowuje unikalne `DynamicSaveName`, slot, klasę, asset przedmiotu, trwałość i zaklęcie. Uzupełnia go podczas gry i przy natywnym zakończeniu zapisu.
- Podczas respawnu najpierw próbuje odzyskać **oryginalne istniejące aktory** przez `Interact`, a następnie przywrócić dokładny slot `5–0`. Podczas ładowania zapisu szuka najpierw aktorów o zgodnym `DynamicSaveName`, a dopiero po kilku odczytach próbuje pojedynczego awaryjnego utworzenia brakującego obiektu. Jeśli operacja się nie powiedzie, pozostawia zapisaną kopię danych i loguje przyczynę.
- `ExpeditionSaver 0.5.1` nie uznaje już przydziału do błędnego slotu za pełne odzyskanie. Czeka na 10 komponentów i weryfikuje `CurrentSlot` + `CurrentInventorySlot`.
- `GrainRotQOL 0.1.2` wykrywa włączony `ExpeditionSaver` i nie wykonuje drugiego ubezpieczenia przedmiotów, dzięki czemu ogranicza ryzyko duplikacji.

**Instalacja:** zalecany zestaw z aktualizacjami `GrainRotQuickJunk 0.2.5`, `ExpeditionSaver 0.5.1` i `GrainRotQOL 0.1.2`. Nie instaluj dwóch kopii tych samych modów. `DepthKeeper` nie powinien działać równocześnie z `ExpeditionSaver`, ponieważ oba mody kontrolują głębokość.

**Ograniczenia:** testy GitHub Actions obejmują mocki odrodzenia, odczytu pliku, niepowtarzania aktorów i odtworzenia pierwotnego indeksu; nie obejmują realnej kolejności zapisu/ładowania UE5.7. Kompletna trwałość zapisu i brak duplikacji wymaga osobnego testu w grze, na kopii zapisu. Obecna kopia pomocnicza dotyczy ekwipunku **lokalnego hosta**; odtwarzanie ekwipunku innych graczy w coop nie jest jeszcze potwierdzone.

## Poprawka 0.2.4 — niewidoczne schowane przedmioty i ograniczenie laga

- **Modele przy postaci:** po wykryciu `HeldenEquipableItem.CurrentInventorySlot` w dodatkowych slotach `5–10` mod odczytuje `HolsterState` (gra: `Equipped=1`, `Holsterd=2`). Przedmioty **schowane** w tych slotach są ukrywane wyłącznie wizualnie (`SetActorHiddenInGame(true)`). Po wybraniu slotu przedmiot odzyskuje widoczność w rękach. Zwykłe sloty `1–4` nie są modyfikowane.
- **Bez zmian w ekwipunku:** nie usuwamy aktorów, nie zmieniamy ich pozycji, mocowań, kolizji ani danych zapisu. Po wyrzuceniu / przełożeniu przedmiotu lub zmianie poziomu mod przywraca widoczność, jeśli to on go wcześniej ukrył.
- **Mniej operacji na wątku gry:** skanowanie kontrolerów, autorytetu hosta oraz wind wykonuje się co **2 s** zamiast co **0,5 s**. Odświeżanie już działającego interfejsu 5–0 odbywa się co **10 s** (pierwsze próby inicjalizacji maks. co 2 s). Diagnostyczne `FindAllOf` UI i niepotrzebne hooki `InventoryAction_Server` / `GrabObject_Server` są wyłączone w wydaniu. Nadal istnieje lekka pętla 500 ms dla oczekującego Junk Slotu.
- **Kompromis:** wykrycie wejścia do windy i uzupełnianie amunicji może być opóźnione do około 2 s. Jeśli w grze nadal są spadki FPS, potrzebny jest test na tych samych ustawieniach z modem włączonym/wyłączonym oraz nowy `UE4SS.log`. GitHub Actions nie mierzy prawdziwego FPS.

## Poprawka 0.2.3 — wybieranie slotów 5–0

W poprzednim wydaniu same sloty i widżety działały, ale obsługa klawiszy nie odszukiwała prawidłowego kontrolera: `HeldenPlayerController:GetPawn()` zwraca `nil`, podczas gdy `LastPlayerChar` zawiera aktualną postać (potwierdzone w UE4SS(6).log). Poprawiono obsługę `5–0`: pobiera lokalny `HeldenPlayerController` bezpośrednio z `player_context.pickLocal()`, odczytuje `LastPlayerChar` i wywołuje natywne `InventoryAction_Server(InIdx:int)`, z indeksami `4–9`. Dodano log `QUICK 5 ... dispatched=true/false reason=...` oraz regresyjny test z `GetPawn=nil`.

**Potwierdzone w testach Lua:** callbacki dla 5, 6, 7, 8, 9, 0 wywołują na poprawnym kontrolerze `InventoryAction_Server(4, 5, 6, 7, 8, 9)`. **Niepotwierdzone w uruchomionej grze:** natywna funkcja musi rzeczywiście przełączyć przedmiot i synchronizować wybór w kooperacji; wynik `dispatched=true` potwierdza wywołanie, nie wynik zmiany ekwipunku.

## Poprawki 0.2.2 z rzeczywistego UE4SS(6).log

- **Klawiatura 5–0:** w źródłowym ObjectDump potwierdzono `HeldenPlayerController.InventoryAction_Server(InIdx: int)`. Poprawiono wysyłanie dokładnego indeksu 0-based zamiast oczekiwania na zgadywaną sygnaturę i przechwytywania klawiszy 1–4.
- **Widoczność:** nowe sloty mają teraz swoje `InputIcon.InputKeyText` ustawiane jawnie przez `FText("5")`, ..., `FText("0")` oraz `InputKey` zamiast domyślnego niezrozumiałego skrótu (np. Ctrl). Prawy dolny HUD pokazuje `J1–J10`.
- **Fatal Error przy M4/M5/G/H:** zrezygnowano z wykonywania surowych operacji `GrabPhysHandle.ReleaseComponent`, zapisu `PhysGrabData.Target=nil` oraz `K2_AttachToActor` / `K2_DetachFromActor` na przedmiocie nadal trzymanym ramionami. To były ryzykowne operacje w v0.2.1; log kończy się bez stosu natywnej awarii, więc nie ma pewności, która konkretnie ją wywołała.
- **Nowa procedura Junk Slot:** podczas trzymania PPM naciśnij **M4 lub G**, a następnie **puść PPM**. Gra sama zwolni przedmiot. Po dwóch odczytach stanu (ok. 1 sekunda) mod bezpieczniej ukryje **oryginalny aktor**. **M5 lub H** przywraca go przed postacią, pod warunkiem że nie trzymasz ramionami kolejnego obiektu. To kompromis w testowej wersji, by nie ingerować w natywny uchwyt fizyki.
- **Ograniczenie:** przedmioty są przechowywane tylko podczas bieżącej sesji i mogą zostać utracone po zmianie mapy lub wyjściu z gry. Najpierw testuj na bezwartościowym przedmiocie i kopii save'a.

**GitHub Actions sprawdza składnię i mocki, nie potwierdza braku Fatal Error w samej grze.**

## Funkcje

| Funkcja | Obecny stan |
|---|---|
| 10 Quickslotów (`1–0`) | Użytkownik potwierdził pojawienie się prawdziwych slotów i wkładanie przedmiotów. Zostawiamy natywne 10 slotów. Przedmioty w dodatkowych slotach są ukrywane na postaci, kiedy `HolsterState=Holsterd`, ale widoczne podczas aktywnego używania. |
| Klawisze `5–0` | Natywny `InventoryAction_Server(InIdx:int)` na lokalnym kontrolerze, pozyskanym przez `LastPlayerChar` (prawdziwy `GetPawn` jest pusty). Indeksy 4–9; graficzny HUD z poprzedniego wydania pozostaje bez zmian. |
| Junk Slots, 10 aktorów | Nowa logika host-only chowa rzeczywisty, podniesiony fizyką `HeldenPhysicsActor` do niewidocznego stanu przyczepionego do postaci. Nie usuwa ani nie tworzy kopii aktora. |
| Mouse4/G | Kolejkuje bezpieczniejsze schowanie aktualnie trzymanego ramionami obiektu po puszczeniu PPM `PhysGrabData.Target`. Bez potwierdzenia odczepienia/ukrycia operacja jest odrzucana. |
| Mouse5/H | Przywraca kolizję, fizykę, widoczność, pojawia się przed postacią. Wyciągnięcie **nie chwyta automatycznie** obiektu ramionami. |
| `<`, `>` | Zmiana wybranego Junk Slotu (Shift+, / Shift+.). |
| Jeden slot HUD | Tworzony jest przez `WidgetBlueprintLibrary` z oryginalnej klasy `SlotWidgetClass` i umieszczany w prawym dolnym rogu. Nie ma jeszcze potwierdzonego powiązania grafiki przedmiotu z fizycznym lootem. |
| Winda i broń palna | Na hostcie przy wejściu do `InteriorCollisionBox` uzupełnia `HeldenRangedWeapon.ItemDurability` do `ItemDurabilityMax`. |

## Instalacja

1. Pobierz ZIP z najnowszego udanego [GitHub Actions](https://github.com/SirRosa/Grain-Rot-Quickslots-Junk-Slots/actions/workflows/ci.yml).
2. Wypakuj ZIP z paczki Actions, a następnie folder `GrainRotQuickJunk` do `Helden/Binaries/Win64/ue4ss/Mods/`.
3. Zachowaj istniejącą instalację UE4SS używaną z pozostałymi modami Grain Rot.
4. Przed uruchomieniem **zrób kopię zapisu** i wyłącz na test mody modyfikujące sloty gracza.

## Ważne ryzyka — testuj tylko na kopii save'a

**Junk Slots są na tym etapie pamięcią sesji, a NIE trwałym ekwipunkiem.** Schowane aktory mogą zniknąć podczas przejścia do innej mapy, wyjścia z gry lub śmierci, mimo awaryjnej próby odzyskania przy wykryciu zgonu. **Wyciągnij wszystko przed opuszczeniem poziomu**. Przeznaczone do testów z bezwartościowymi obiektami.

**Dodatkowe sloty nie mają potwierdzonej replikacji sieciowej, serializacji ani odświeżania UI.** Jeżeli silnik odrzuca rozszerzenie tablic lub wywołanie natywnego RPC, mod zapisuje komunikat w logu, a nie symuluje sukcesu.

Wersja powstała na podstawie prawdziwych struktur projektu Helden z [bazy modderskiej](https://github.com/SirRosa/Grain-Rot-Mod-Data-Base). Testy w GitHub Actions to składnia i mocki Lua, **nie test w uruchomionym Grain Rot**.

## Jak przekazać wynik testów

Po testach odczytaj `UE4SS.log` i znajdź wpisy `[GrainRotQuickJunk]`, zwłaszcza:
- `[QUICK] APPENDED`, `native ItemSlots`, `InventoryAction_Server parameters`
- `[INPUT] observed native slot`, `CALIBRATED`
- `[JUNK] STORED`, `RETRIEVED` lub konkretny kod odrzucenia
- `[JUNK HUD]`, `elevator ENTRY`, `REFILL`

Przetestuj osobno hosta i klienta. Przy niepowodzeniu podeślij zanonimizowany `UE4SS.log`; pozwoli ustalić dokładną sygnaturę funkcji gry zamiast zgadywać.
