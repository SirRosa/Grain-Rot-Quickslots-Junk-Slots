# Grain Rot — Quickslots / Junk Slots

**v0.2.3-inputfix** — poprawka oparta na prawdziwym logu UE4SS(5): odnajdywanie BP postaci / LastPlayerChar, weryfikacja natywnych tablic dokładnie w UE4SS 3.0.1 (`1c1a1497`), ponawianie rozszerzenia rzeczywistych slotów oraz budowa paska UI z oryginalnych widgetów gry. **Wciąż wymaga testu w grze — zielony CI nie oznacza, że sloty rzeczywiście się pojawiają.**

[Szczegółowe ustalenia z logu](docs/UE4SS5-REAL-LOG-ROOT-CAUSE.md).

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
| 10 Quickslotów (`1–0`) | Próba rozszerzenia `InventorySettings.SlotSettings` z 4 do 10 i stworzenia brakujących `HeldenInventorySlotComponent` / `ItemSlots`. Gra musi zaakceptować nowe obiekty oraz ich replikację; UI próbuje dobudować 6 oryginalnych slotów dopiero po potwierdzeniu 10 rzeczywistych miejsc. W grze nadal niezweryfikowane. |
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
