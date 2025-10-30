# Netz-Boot & File-Server (FIN) – Anleitung

Dieses Setup macht **einen FIN‑Computer zum zentralen File‑Server**. Alle **Clients booten transparent aus dem Netzwerk** und können lokal einfach `require(...)` verwenden – fehlende Dateien werden automatisch vom Server nachgeladen. Das erledigen **CodeDispatchServer/Client** über Broadcast und In‑Memory‑`require`.

---

## Ordnerstruktur & Kopieren

- **Wichtig:** **Nur die *Inhalte unter* `development/`** auf **die Festplatte des Servers** kopieren (z. B. nach `/srv/development/...`). Eigene Dateien können dort zusätzlich abgelegt werden.
- Lege außerdem die **`config.lua`** ins **Root der Server‑Platte** (z. B. `/srv/config.lua`).

---

## Server einrichten

1. Server‑Computer mit **NetworkCard** und Festplatte starten.
2. **EEPROM des Servers** mit dem **Inhalt von `Server.lua`** beschreiben (1:1). Beim Start:
   - wird `/srv` eingehängt und `config.lua` geladen,
   - Sprach‑Platzhalter `[-LANGUAGE-].lua` in angeforderten Dateien gemäß `TTR_FIN_Config.language` ersetzt,
   - startet der **CodeDispatchServer** auf Port `8` und beantwortet Code‑Anfragen.
3. Server laufen lassen – er sendet einmal `resetAll` und wartet dann auf Anfragen.

---

## Client einrichten

1. Client‑Computer mit **NetworkCard** starten.
2. **EEPROM des Clients** mit **`bootLoader.lua`** beschreiben.  
   In der Datei **eine Startdatei** (vom Server) setzen und optional **Parameter übergeben**:

```lua
-- bootLoader.lua (Ausschnitt)
-- Startskript vom Server:
local name = "development/factoryRegistry/starter/[YOUR_STARTER].lua"

-- optionale Variablen, die das Starter-Script erwartet:
fName   = "DEIN_FABRIK_NAME"
scrName = "DEIN_SCREEN_NAME"   -- nur fürs Dashboard
-- stationMin = 2              -- optional für InfoCollector
```

Der Client lädt `name` über das Netz und führt Module mit einem lokalen In‑Memory‑`require` aus; Abhängigkeiten werden bei Bedarf nachgeladen.

---

## Die drei Starter

Die Starter liegen unter `development/factoryRegistry/starter/…` und werden **über `local name = ".../starter/<datei>.lua"`** ausgewählt.

1. **`factoryRegistry.lua`** – Zentrales Register aller Fabriken  
   Startet den Registry‑Server. Andere Rechner können dort die Adresse (NIC) einer Fabrik abfragen. **Keine Extra‑Variablen nötig.**

2. **`factoryInfoCollector.lua`** – Läuft **bei der Fabrik**  
   Sammelt Daten aller angebundenen Komponenten.  
   **Erfordert:**
```lua
fName = "DEIN_FABRIK_NAME"
-- stationMin = 2 -- optional
```
   Erwartet (aktuell rudimentär): alle **Incoming/Outgoing Trainstations & Container** im LAN, **eine Manufacturer‑Art**, und **saubere, eindeutige Namen** der Komponenten.

3. **`factoryDashboard.lua`** – Visualisierung auf einem **LargeScreen**  
   **Erfordert:**
```lua
fName   = "DEIN_FABRIK_NAME"
scrName = "DEIN_SCREEN_NAME"
```

**Beispiel‑EEPROM (Client) für Dashboard:**
```lua
local name = "development/factoryRegistry/starter/factoryDashboard.lua"
fName   = "IronHub"
scrName = "Hall_A_Screen_01"
```

**Beispiel‑EEPROM (Client) für Registry:**
```lua
local name = "development/factoryRegistry/starter/factoryRegistry.lua"
```

**Beispiel‑EEPROM (Client) für InfoCollector:**
```lua
local name   = "development/factoryRegistry/starter/factoryInfoCollector.lua"
fName        = "IronHub"
-- stationMin = 2
```

---

## Wie das Laden funktioniert (transparentes `require`)

- Der Client sendet `getEEPROM <datei>` auf Port `8`. Der Server liest die Datei von `/srv/...`, ersetzt ggf. `[-LANGUAGE-].lua` gemäß `config.lua`, und sendet den Quelltext zurück.
- Der Client führt den Code **in einer eigenen Umgebung mit lokalem `require`** aus. Module werden **gecached**; zyklische Requires werden abgefangen.

---

## `config.lua` (Server)

- Liegt auf **`/srv/config.lua`**.
- Steuert u. a. `TTR_FIN_Config.language` (ersetzt `[-LANGUAGE-].lua` → `_<lang>.lua`, z. B. `_de.lua`) und das Log‑Level.

---

## Troubleshooting

- **Keine NetworkCard gefunden?** Server/Client beenden mit Assertion → NetworkCard einsetzen.
- **Datei nicht gefunden:** Pfad relativ zu `/srv` prüfen (z. B. `development/...`).
- **Sprache greift nicht:** `TTR_FIN_Config.language` in `config.lua` prüfen – der Server ersetzt exakt die Sequenz `[-LANGUAGE-].lua`.
- **Keine Reaktion:** Beide Seiten warten ereignisgetrieben. Netzwerk‑Erreichbarkeit sicherstellen (Port 8, gleiche LAN‑Zone).

---

## Kurz‑Checkliste

- [ ] Inhalte **unter `development/`** → **Server‑Platte** (`/srv/development/...`).
- [ ] **`/srv/config.lua`** vorhanden & Sprache gesetzt.
- [ ] **Server‑EEPROM** = `Server.lua`. Gestartet.
- [ ] **Client‑EEPROM** = `bootLoader.lua`, **`local name = ".../starter/<file>.lua"`** setzen + benötigte Variablen (`fName`, `scrName`, `stationMin`).

Fertig – damit booten deine Clients ihren Code vom zentralen Server und alle `require(...)` funktionieren ohne lokale Dateien.
