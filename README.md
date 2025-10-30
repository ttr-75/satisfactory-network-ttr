# FIN Code Dispatch – Zentrales Client–Server‑Setup

> **Ziel:** Ein Computer im FIN‑Netzwerk fungiert als zentraler **File‑Server**. Alle **Client‑Computer** laden ihre Start‑ und Modul‑Skripte transparent über das Netzwerk nach (inkl. `require(...)`).

---

## Features

* **Transparente Modul‑Ladung:** `require()` lädt fehlende Module automatisch vom Server nach (inkl. Cache & Zyklus‑Schutz).
* **Zentraler Code‑Storage:** Alle Skripte liegen auf einer Server‑Festplatte (z. B. unter `/srv`).
* **Broadcast‑Reset:** Server kann beim Start optional alle Clients neu starten lassen.
* **Sprachvarianten:** Platzhalter `[-LANGUAGE-].lua` wird serverseitig automatisch durch `_<sprache>.lua` ersetzt (z. B. `de`).
* **Konfigurierbares Logging.**

---

## Komponenten & Dateien

* **Server‑EEPROM:** `Server.lua`
* **Client‑EEPROM (Bootloader):** `bootLoader.lua`
* **Laufzeit‑Bibliotheken & Programme:** beliebige `.lua`‑Dateien auf der Server‑Festplatte (z. B. alles unter `development/`).

> **Empfehlung:** Kopiere **alle** Skripte, die Clients nutzen sollen, auf die Server‑Festplatte unter `/srv` (z. B. den Inhalt deines `development/`‑Ordners).

---

## Architektur (High‑Level)

```
[ Clients ] --(FIN Port 8)--> [ Server ] --(FileIO)--> [/srv/<deine Dateien>]
       ^                            |
       |                            +-- ersetzt "[-LANGUAGE-].lua" → "_<lang>.lua"
       +-- require() ↔ Netz → Cache pro Client
```

* **Client** sendet `GET_EEPROM` für Modulnamen → wartet.
* **Server** liest Datei aus `/srv/<name>` → ersetzt Sprach‑Chunk → antwortet `setEEPROM` mit Code.
* **Client** lädt Code in eigener `require`‑fähiger Umgebung, cached Rückgaben wie gewohnt.

---

## Voraussetzungen

* FIN‑Computer mit **Network Card** auf Server **und** Client.
* Server‑Computer mit **Festplatte**; Mount‑Punkt: `/srv`.

---

## Installation & Setup

### 1) Server einrichten

1. **EEPROM** des Server‑PCs mit **`development/net/codeDispatch/EEPROM/Server.lua`** flashen (Inhalt 1:1 übernehmen).
2. **Festplatte** vorbereiten und verwenden (Wurzelpfad `/`).
3. **Code kopieren:** Den **kompletten** Ordner `development/` deiner Projektstruktur auf die Server‑Festplatte in die **Wurzel** kopieren → liegt dann unter **`/development`**.
4. **Konfiguration:** Lege optional `/config.lua` an, z. B.:

   ```lua
   TTR_FIN_Config = {
     LOG_LEVEL = 0,     -- 0=Info .. 4=Fatal
     language  = "de", -- steuert Platzhalter [-LANGUAGE-].lua → _de.lua
   }
   ```
5. Server starten. Beim Start:

   * `/config.lua` wird geladen (falls vorhanden).
   * Server öffnet Port **8**, reagiert auf `getEEPROM` und kann **Reset‑Broadcast** senden.

### 2) Clients einrichten

1. **EEPROM** des Client‑PCs mit **`development/net/codeDispatch/EEPROM/bootLoader.lua`** flashen.

2. In dieser Datei **Start‑Datei** setzen (Pfad relativ zur **Platten‑Wurzel** auf dem Server). Typische Beispiele aus deiner Struktur:

   ```lua
   -- bootLoader.lua
   local name = "development/factoryRegistry/starter/basics.lua"
   -- oder
   -- local name = "development/factoryRegistry/starter/factoryRegistry.lua"
   -- local name = "development/factoryRegistry/starter/factoryDashboard.lua"
   -- local name = "development/factoryRegistry/starter/factoryInfoCollector.lua"

   -- Optional: zusätzliche Eingaben/Variablen für dein Startskript
   yourInput = { profile = "prod", station = "Hub-01" }
   ```

3. Client starten. Der Bootloader initialisiert Netzwerk & Client‑Loader, fordert `name` beim Server an und führt es aus. Nachfolgende `require()`‑Aufrufe in deinen Modulen laden automatisch nach.

4. **EEPROM** des Client‑PCs mit **`development/net/codeDispatch/EEPROM/bootLoader.lua`** flashen.

5. In dieser Datei **Start‑Datei** setzen (Pfad relativ zu `/srv` auf dem Server). Typische Beispiele aus deiner Struktur:

   ```lua
   -- bootLoader.lua
   local name = "development/factoryRegistry/starter/basics.lua"
   -- oder
   -- local name = "development/factoryRegistry/FactoryRegistryServer_Main.lua"
   -- local name = "development/factoryRegistry/FactoryDashboard_Main.lua"

   -- Optional: zusätzliche Eingaben/Variablen für dein Startskript
   yourInput = { profile = "prod", station = "Hub-01" }
   ```

6. Client starten. Der Bootloader initialisiert Netzwerk & Client‑Loader, fordert `name` beim Server an und führt es aus. Nachfolgende `require()`‑Aufrufe in deinen Modulen laden automatisch nach.

7. **EEPROM** des Client‑PCs mit **`bootLoader.lua`** flashen.

8. In `bootLoader.lua` **Start‑Datei** setzen (Pfad relativ zu `/srv` auf dem Server):

   ```lua
   -- bootLoader.lua
   local name = "main.lua"        -- Beispiel: oder "apps/start.lua"

   -- Optional: zusätzliche Eingaben/Variablen für dein Startskript
   yourInput = { profile = "prod", station = "Hub-01" }
   ```

9. Client starten. Der Bootloader initialisiert Netzwerk & Client‑Loader, fordert `name` beim Server an und führt es aus. Nachfolgende `require()`‑Aufrufe in deinen Modulen laden automatisch nach.

> **Hinweis:** Pfadangaben der Clients müssen mit den Server‑Dateinamen unter `/srv` übereinstimmen.

---

## Projektstruktur (konkret)

So legst du die Dateien **auf der Server‑Festplatte** ab (links = dein Repo, rechts = Ziel auf Platte):

```
Repo                             →   Server‑Platte (Wurzel)
# Wichtig: den **INHALT** von `development/` in die Wurzel kopieren –
# der Ordner `development` selbst wird **nicht** mitkopiert.

development/factoryRegistry/      →   /factoryRegistry/
│  ├─ starter/                    →   /factoryRegistry/starter/
│  │  ├─ factoryDashboard.lua
│  │  ├─ factoryInfoCollector.lua
│  │  └─ factoryRegistry.lua
│  ├─ FactoryDashboard_Main.lua   →   /factoryRegistry/FactoryDashboard_Main.lua
│  ├─ FactoryDashboard_UI.lua     →   /factoryRegistry/FactoryDashboard_UI.lua
│  ├─ FactoryDataCollertor_Main.lua → /factoryRegistry/FactoryDataCollertor_Main.lua
│  ├─ FactoryInfo.lua             →   /factoryRegistry/FactoryInfo.lua
│  ├─ FactoryRegistry.lua         →   /factoryRegistry/FactoryRegistry.lua
│  └─ FactoryRegistryServer_Main.lua → /factoryRegistry/FactoryRegistryServer_Main.lua

development/file/FileIO.lua       →   /file/FileIO.lua

development/net/codeDispatch/EEPROM/bootLoader.lua → **EEPROM für Clients**
development/net/codeDispatch/EEPROM/Server.lua     → **EEPROM für Server**

development/net/codeDispatch/basics.lua            → /net/codeDispatch/basics.lua
development/net/codeDispatch/CodeDispatchClient.lua→ /net/codeDispatch/CodeDispatchClient.lua
development/net/codeDispatch/CodeDispatchServer.lua→ /net/codeDispatch/CodeDispatchServer.lua

development/net/media/            →   /net/media/
development/net/net_types.lua     →   /net/net_types.lua
development/net/NetHub.lua        →   /net/NetHub.lua
development/net/NetworkAdapter.lua→   /net/NetworkAdapter.lua

development/shared/items/items_de.lua → /shared/items/items_de.lua

development/shared/*.lua          →   /shared/*.lua
```

**Hinweise:**

* Auf dem Server liegen die **Dateien direkt in der Wurzel** (z. B. `/factoryRegistry/...`, `/shared/...`). Nutze in `require()` genau diese Pfade (z. B. `require("shared/helper.lua")`).
* Der Server ersetzt `[-LANGUAGE-].lua` → `_<lang>.lua` anhand der Einstellung in `/config.lua`.

---

## Transparente Modul‑Ladung (`require`)

* **Beispiel:** `require("development/shared/helper.lua")`

  1. Client prüft lokalen Modul‑Cache.
  2. Falls nicht vorhanden: sendet `getEEPROM` (Port 8; Name = `development/shared/helper.lua`).
  3. Server liest **`/development/shared/helper.lua`**, ersetzt ggf. Sprach‑Chunk und sendet Code mit `setEEPROM`.
  4. Client lädt das Modul in eigener Umgebung mit lokalem `require`, bewertet den Rückgabewert und cached ihn.
* **Rückgabewerte:** wie gewohnt Table/`exports`/`true`.
* **Zyklus‑Schutz:** rekursive Abhängigkeiten werden erkannt und sauber gemeldet.

---

## Sprachdateien

* In Dateien darf der Platzhalter **`[-LANGUAGE-].lua`** vorkommen, z. B. `strings[-LANGUAGE-].lua`.
* Der Server ersetzt dies beim Ausliefern automatisch durch **`_<sprache>.lua`** (aus `TTR_FIN_Config.language`).
* Praxisbeispiel: `strings[-LANGUAGE-].lua` → `strings_de.lua` bei `language = "de"`.

---

## Logging

* Globale Variable `LOG_LEVEL` (oder `TTR_FIN_Config.LOG_LEVEL`) steuert die Verbosität (0..4).
* Logs werden per `computer.log(level, ...)` geschrieben.

---

## Beispiel‑Startdatei `factoryRegistry/starter/[YOUR_STARTER].lua`

```lua
-- Minimal: Utilities + i18n via Platzhalter (Sprache aus /config.lua)
local helper  = require("shared/helper.lua")
local strings = require("shared/strings[-LANGUAGE-].lua")

print("Client gestartet auf ", computer.getName())
helper.init()
```

> **i18n:** Die Sprache wird zentral in `/config.lua` gesetzt. Dateien, die den Platzhalter `[-LANGUAGE-].lua` im Namen tragen, werden beim Ausliefern automatisch auf `_<lang>.lua` gemappt (z. B. `strings_de.lua`). `shared/items/items_de.lua` ist lediglich ein **Beispiel** für eine lokalisierte Ressource.

---

## Fehlersuche (Troubleshooting)

* **"Keine NIC" / Netzwerkfehler:** Stelle sicher, dass sowohl Server‑ als auch Client‑PC eine **Network Card** verbaut haben und miteinander verbunden sind.
* **`require('...'): no code after fetch`:** Datei existiert nicht auf dem Server unter `/srv/<pfad>`. Pfad prüfen.
* **`FileIO.ensureMounted: could not mount any /dev/*`:** Server findet/ mounted die Festplatte nicht. Verkabelung/Slot prüfen; `/srv` muss erreichbar sein.
* **Sprachdatei nicht gefunden:** Wenn du `strings[-LANGUAGE-].lua` nutzt, muss die Variante `strings_<lang>.lua` auch tatsächlich auf der Platte liegen.
* **Endlosschleifen bei Abhängigkeiten:** Prüfe auf zyklische `require()`‑Ketten.

---

## Best Practices

* Klare Ordnerstruktur (z. B. `lib/`, `apps/`, `assets/`).
* Modulnamen immer als **relativen Pfad** konsistent verwenden (wie sie auf dem Server abgelegt sind).
* Gemeinsame Utilities in `lib/` auslagern und überall via `require` nutzen.
* Für Lokalisierung ausschließlich über den `[-LANGUAGE-]`‑Platzhalter arbeiten.

---

## Starter-Programme (factoryRegistry/starter)

Im Ordner `factoryRegistry/starter/` liegen **Start-Skripte**, die die jeweiligen Hauptprogramme booten. Rollen & Inputs:

| Starter-Skript             | Zweck                                                                                                                                                                         | Pflicht‑Inputs (im Client‑Bootloader zu setzen)                       | Startet                                                   |
| -------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------- | --------------------------------------------------------- |
| `factoryRegistry.lua`      | Zentrales Register aller Fabriken. Fabriken melden sich an, andere Clients fragen Adressen/NCIDs ab.                                                                          | –                                                                     | `FactoryRegistryServer_Main.lua`                          |
| `factoryInfoCollector.lua` | Läuft **in der Fabrik**; sammelt Daten aller angebundenen Komponenten (eingehende/ausgehende Train Stations & Container, eine Manufacturer‑Art; korrekte Namen erforderlich). | `fName = "DEIN_FABRIK_NAME"` (Pflicht), optional `stationMin = <num>` | `FactoryDataCollertor_Main.lua`                           |
| `factoryDashboard.lua`     | Visualisiert **eine Fabrik** auf einem Large Screen.                                                                                                                          | `fName = "DEIN_FABRIK_NAME"`, `scrName = "DEIN_SCREEN_NAME"`          | `FactoryDashboard_Main.lua` (+ `FactoryDashboard_UI.lua`) |

### Boot-Sequenzen (vereinfacht)

* **factoryRegistry.lua** → `require("factoryRegistry/FactoryRegistryServer_Main.lua")` → Instanz anlegen → Endlosschleife mit `future.run()` hält Events/Tasks am Leben. fileciteturn2file0
* **factoryInfoCollector.lua** → lädt `config.lua` → `require("factoryRegistry/FactoryDataCollertor_Main.lua")` → prüft `fName` (und optional `stationMin`) → `new{...}:run()`. fileciteturn2file2
* **factoryDashboard.lua** → `require("factoryRegistry/FactoryDashboard_Main.lua")` → prüft `fName` & `scrName` → `new{...}:run()`; UI in `FactoryDashboard_UI.lua`. fileciteturn2file1

---|---|---|
| `factoryRegistry.lua` | Registry/Directory-Service starten (zentral) | `development/factoryRegistry/FactoryRegistryServer_Main.lua` |
| `factoryDashboard.lua` | Dashboard/Anzeige-UI | `development/factoryRegistry/FactoryDashboard_Main.lua` + `FactoryDashboard_UI.lua` |
| `factoryInfoCollector.lua` | Sensor-/Daten-Collector | `development/factoryRegistry/FactoryDataCollertor_Main.lua` |

### So wählst du den Starter am Client

In **`net/codeDispatch/EEPROM/bootLoader.lua`** die `name`‑Variable auf einen Starter setzen (Pfad relativ zur Platten‑Wurzel):

```lua
-- bootLoader.lua (Client EEPROM)
local name = "factoryRegistry/starter/[YOUR_STARTER].lua"

-- Pflicht-/Optionale Übergaben je nach Starter (Beispiele):
-- fName   = "DEIN_FABRIK_NAME"
-- scrName = "DEIN_SCREEN_NAME"
-- stationMin = 1
```

Der Bootloader fordert die Datei via Netz an und führt sie aus; darin verwendete `require(...)`‑Aufrufe werden **on‑demand** vom Server nachgeladen. fileciteturn0file3

---

## Quickstart (TL;DR)

1. `development/net/codeDispatch/EEPROM/Server.lua` ins **Server‑EEPROM**.
2. Deinen **`development/`‑Ordner** auf die **Wurzel** der Server‑Festplatte kopieren → **`/development`**.
3. Optional `/config.lua` mit `LOG_LEVEL` & `language` anlegen.
4. Auf Clients `development/net/codeDispatch/EEPROM/bootLoader.lua` flashen und `name` auf einen **Starter** setzen.
5. Starten → Clients laden Startskript & alle Abhängigkeiten automatisch nach (`getEEPROM`/`setEEPROM` über Port **8**).

---

## Lizenz

Dein Projekt‑Lizenztext hier.
