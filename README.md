# Grain Rot — Quickslots / Junk Slots

**v0.2.1-contextfix** — poprawka oparta na prawdziwym logu UE4SS(5): odnajdywanie BP postaci / LastPlayerChar, weryfikacja natywnych tablic dokładnie w UE4SS 3.0.1 (`1c1a1497`), ponawianie rozszerzenia rzeczywistych slotów oraz budowa paska UI z oryginalnych widgetów gry. **Wciąż wymaga testu w grze — zielony CI nie oznacza, że sloty rzeczywiście się pojawiają.**

[Szczegółowe ustalenia z logu](docs/UE4SS5-REAL-LOG-ROOT-CAUSE.md).

## Funkcje

| Funkcja | Obecny stan |
|---|---|
| 10 Quickslotów (`1–0`) | Próba rozszerzenia `InventorySettings.SlotSettings` z 4 do 10 i stworzenia brakujących `HeldenInventorySlotComponent` / `ItemSlots`. Gra musi zaakceptować nowe obiekty oraz ich replikację; UI próbuje dobudować 6 oryginalnych slotów dopiero po potwierdzeniu 10 rzeczywistych miejsc. W grze nadal niezweryfikowane. |
| Klawisze `5–0` | Najpierw korzystają z natywnego `InventoryAction_Server` tylko jeśli rozpoznano bezpieczną sygnaturę. Alternatywnie mod uczy się jej po kolejnych naciśnięciach `1`, `2`, `3` (te trzy klawisze nie zmieniają natywnego działania). |
| Junk Slots, 10 aktorów | Nowa logika host-only chowa rzeczywisty, podniesiony fizyką `HeldenPhysicsActor` do niewidocznego stanu przyczepionego do postaci. Nie usuwa ani nie tworzy kopii aktora. |
| Mouse4/G | Próba schowania aktualnie trzymanego ramionami obiektu `PhysGrabData.Target`. Bez potwierdzenia odczepienia/ukrycia operacja jest odrzucana. |
| Mouse5/H | Odłącza wybrany aktor, przywraca kolizję, fizykę, widoczność, pojawia się przed postacią. Wyciągnięcie **nie chwyta automatycznie** obiektu ramionami. |
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
