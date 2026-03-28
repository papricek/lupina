# Testovací scénáře

10 scénářů pro ověření generátoru EDC dat — 5 výrobních (přetoky) a 5 spotřebních.
Ke každému je vygenerován EDC soubor pro červenec 2026 v `examples/scenarios/`.

## Výrobní scénáře (production)

Vstup: kapacita (kWp) + roční přetoky (kWh) + popis charakteristiky spotřeby.
Výstup: EDC s 15-minutovými intervaly exportu do sítě.

### P1 — Supermarket (200 kWp, 40 MWh přetoků)

> "200 kWp na střeše supermarketu, přetoky 40 MWh ročně, spotřeba hlavně chlaďáky a klimatizace celý den, víkend zavírají v 13h"

- **Poměr přetoků:** 20 % (supermarket sežere skoro vše)
- **Pracovní den:** malé přetoky kolem poledne, jinak vše spotřebováno
- **Víkend:** po 13h zavřou → plné přetoky odpoledne
- **Soubor:** `examples/scenarios/P1_supermarket_07_2026.csv`
- **Červenec:** 6 360 kWh export z 27 000 kWh produkce

### P2 — Garáž s nabíječkou (30 kWp, 27 MWh přetoků)

> "30 kWp na garáži, nikdo tam nebydlí, jen nabíječka na elektroauto občas, přetoky 27 MWh"

- **Poměr přetoků:** 90 % (minimální spotřeba)
- **Celý týden:** plné přetoky po celý den — profil 1.0 všude
- **Soubor:** `examples/scenarios/P2_garaz_07_2026.csv`
- **Červenec:** 3 726 kWh export z 4 050 kWh produkce

### P3 — Pila (80 kWp, 15 MWh přetoků)

> "80 kWp na pile, přetoky 15 MWh za rok, katry a frézy jedou 6-16 pondělí až sobota dopoledne, neděle klid"

- **Poměr přetoků:** 19 % (velmi vysoká spotřeba)
- **Pracovní den:** přetoky až po 16h (stroje jedou 6-16)
- **Sobota:** přetoky od poledne (dopolední směna)
- **Neděle:** plné přetoky celý den
- **Soubor:** `examples/scenarios/P3_pila_07_2026.csv`
- **Červenec:** 2 391 kWh export z 10 800 kWh produkce

### P4 — Autoservis (45 kWp, 25 MWh přetoků)

> "45 kWp na střeše autoservisu, přetoky 25 MWh, dílna jede 7-16 Po-Pá, víkend zavřeno"

- **Poměr přetoků:** 56 % (střední spotřeba)
- **Pracovní den:** nízké přetoky 7-16 (dílna), plné po 16h
- **Víkend:** plné přetoky celý den (zavřeno)
- **Soubor:** `examples/scenarios/P4_autoservis_07_2026.csv`
- **Červenec:** 3 708 kWh export z 6 075 kWh produkce

### P5 — Škola (150 kWp, 100 MWh přetoků)

> "150 kWp na střeše školy, přetoky 100 MWh, v létě prázdniny = plné přetoky, jinak spotřeba 8-15"

- **Poměr přetoků:** 67 %
- **Pracovní den (školní rok):** přetoky až po 15h (výuka 8-15)
- **Víkend + prázdniny:** plné přetoky celý den
- **Soubor:** `examples/scenarios/P5_skola_07_2026.csv`
- **Červenec:** 14 500 kWh export z 20 250 kWh produkce

---

## Spotřební scénáře (consumption)

Vstup: roční spotřeba (kWh) + popis charakteristiky odběru.
Výstup: EDC s 15-minutovými intervaly spotřeby.

### C1 — Serverovna (120 MWh ročně)

> "serverovna, spotřeba 120 MWh ročně, konstantní odběr 24/7 celý rok"

- **Profil:** plochý 1.0 po celých 24 hodin, každý den
- **Soubor:** `examples/scenarios/C1_serverovna_07_2026.csv`
- **Červenec:** 10 192 kWh, špička 21 kW

### C2 — Restaurace (35 MWh ročně)

> "restaurace, spotřeba 35 MWh za rok, vaří od 9 do 22, neděle zavřeno, pondělí taky"

- **Pracovní den (Út-Pá):** špička 9-22 (obědy + večeře)
- **Sobota:** plný provoz
- **Neděle + pondělí:** standby (lednice, zabezpečení)
- **Soubor:** `examples/scenarios/C2_restaurace_07_2026.csv`
- **Červenec:** 2 973 kWh, špička 14 kW

### C3 — Fitness centrum (50 MWh ročně)

> "fitness centrum, 50 MWh ročně, ráno 6-9 a večer 16-22 špička, přes den míň, víkend celý den"

- **Pracovní den:** bimodální — ranní špička 6-9, večerní 16-22
- **Víkend:** rovnoměrně vysoký odběr celý den
- **Noc:** base load (HVAC, osvětlení)
- **Soubor:** `examples/scenarios/C3_fitness_07_2026.csv`
- **Červenec:** 4 247 kWh, špička 16 kW

### C4 — Noční pekárna (30 MWh ročně)

> "noční pekárna, spotřeba 30 MWh ročně, pece jedou od 22 do 6 ráno, přes den jen expedice a myčka"

- **Celý týden:** špička 22-06 (pece), nízký odběr přes den (expedice)
- **Bez víkendového rozdílu** — peče se každý den
- **Soubor:** `examples/scenarios/C4_nocni_pekarna_07_2026.csv`
- **Červenec:** 2 548 kWh, špička 13 kW

### C5 — Malý obchod (8 MWh ročně)

> "malý obchod, 8 MWh za rok, otevřeno Po-So 8-18, neděle zavřeno"

- **Po-So:** špička 8-18 (osvětlení, pokladny, lednice)
- **Neděle:** standby (lednice, alarm)
- **Soubor:** `examples/scenarios/C5_obchod_07_2026.csv`
- **Červenec:** 680 kWh, špička 4 kW

---

## Ověření

Všechny scénáře prošly automatickým testem (`examples/verify_all.rb`):
- Roční součty přetoků/spotřeby sedí přesně na zadanou hodnotu
- Profily odpovídají popisu (žádné přetoky v době provozu strojů, spotřeba ve správných hodinách)
- Žádné noční přetoky u výrobních scénářů (solární panely nevyrábí)
- Všechny hodnoty v CSV nezáporné, formát EDC korektní
