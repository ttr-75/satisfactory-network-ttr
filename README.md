# Network Boot & File Server (FIN) – Guide

This setup turns **one FIN computer into a central file server**. All **clients boot transparently from the network** and can keep using local `require(...)` — missing files are fetched automatically from the server. This is handled by **CodeDispatchServer/Client** via broadcast and an in‑memory `require` implementation.

---

## Folder layout & copying

- **Important:** Copy **only the *contents of* `development/`** to the **server’s disk** (e.g. `/srv/...`) (`/srv/` is the root of your Mounted HardDrive). You can add your own files there as well.
- Put **`config.lua`** in the **root of the server disk** (e.g. `/srv/config.lua`).

---
## Prerequisites

* FIN computer with a **Network Card** on both **server** and **client**.
* Server computer with a **hard drive**; mount point: `/srv`.

---

## Installation & Setup

### 1) Set up the server

1. Flash the server PC’s **EEPROM** with **`development/net/codeDispatch/EEPROM/Server.lua`** (copy the contents 1:1).
2. Prepare and use the **hard drive** (root path `/`).
3. **Copy code:** Copy the content of the **entire** `development/` folder from your project to the **root** of the server disk → it will end up at **`srv/`**.
4. **Configuration:** Optionally create `/config.lua`, e.g.:
   ```lua
   TTR_FIN_Config = {
     LOG_LEVEL = 0,    -- 0=Info .. 4=Fatal
     language  = "de", -- controls placeholder [-LANGUAGE-].lua → _de.lua
   }
   ```
5. Boot the server. On startup:
   * `/config.lua` is loaded (if present).
   * The server opens port **8**, responds to `getEEPROM`, and may send a **reset broadcast**.

### 2) Set up the clients

1. Flash the client PC’s **EEPROM** with **`development/net/codeDispatch/EEPROM/bootLoader.lua`**.
2. In that file, set the **start file** (path is relative to the **hard drive root** on the server). Typical examples from your structure:
   ```lua
   -- bootLoader.lua
   local name = "[YOUR_PATH]/[YOUR_STARTER].lua"
   -- or
   -- local name = "factoryRegistry/starter/factoryRegistry.lua"
   -- local name = "factoryRegistry/starter/factoryDashboard.lua"
   -- local name = "factoryRegistry/starter/factoryInfoCollector.lua"

   -- Optional: extra inputs/variables for your start script
   yourInput = { profile = "prod", station = "Hub-01" }
   ```
3. Start the client. The bootloader initializes networking and the client loader, requests `name` from the server, and executes it. Subsequent `require()` calls in your modules will be fetched automatically as needed.

> **Note:** Client path values must match the server’s filenames under `/srv`.

---

## Transparent Module Loading (`require`)

* **Example:** `require("shared/helper.lua")`

  1. Client checks the local module cache.
  2. If missing: it sends `getEEPROM` (port 8; name = `shared/helper.lua`).
  3. Server reads **`/development/shared/helper.lua`**, optionally performs language replacement, and replies with `setEEPROM` containing the code.
  4. Client loads the module in its own environment with a local `require`, evaluates the return value, and caches it.
* **Return values:** as usual — table/`exports`/`true`.
* **Cycle protection:** recursive dependencies are detected and reported cleanly.

---

## Logging

* Global variable `LOG_LEVEL` (or `TTR_FIN_Config.LOG_LEVEL`) controls verbosity (0..4).
* Inject log-helper 
```lua
local Helper_log = require("shared/helper_log.lua")
local log = Helper_log.log
```
* Logs are written via `log(level, ...)`.

---

## Factory Monitoring - The three starters (optional and work in progress)

The starters live in `factoryRegistry/starter/…` and are **selected via `local name = "factoryRegistry/starter/<file>.lua"`**.

1. **`factoryRegistry.lua`** – Central registry of all factories  
   Launches the registry server. Other machines can query a factory’s NIC address there. **No extra variables required.**

2. **`factoryInfoCollector.lua`** – Runs **at the factory**  
   Collects data from connected components.  
   **Requires:**
```lua
fName = "YOUR_FACTORY_NAME"
-- stationMin = 2 -- optional
```
   Current assumption: all **incoming/outgoing train stations & containers** are on the LAN, **one manufacturer type** is present, and **all components have clear, unique names**.

3. **`factoryDashboard.lua`** – Visualization on a **LargeScreen**  
   **Requires:**
```lua
fName   = "YOUR_FACTORY_NAME"
scrName = "YOUR_SCREEN_NAME"
```

![Factory Monitor](https://github.com/ttr-75/satisfactory-network-ttr/blob/main/media/FactoryScreen.png?raw=true "Factory Monitor")

**Client EEPROM example – Dashboard:**
```lua
local name = "development/factoryRegistry/starter/factoryDashboard.lua"
fName   = "IronHub"
scrName = "Hall_A_Screen_01"
```

**Client EEPROM example – Registry:**
```lua
local name = "development/factoryRegistry/starter/factoryRegistry.lua"
```

**Client EEPROM example – InfoCollector:**
```lua
local name   = "development/factoryRegistry/starter/factoryInfoCollector.lua"
fName        = "IronHub"
-- stationMin = 2
```

![FactoryRegister Workflow](https://github.com/ttr-75/satisfactory-network-ttr/blob/main/medi/FactoryRegistryWorkflow.png?raw=true "FactoryRegister Workflow")


## `config.lua` (server)

- Stored at **`/srv/config.lua`**.
- Controls e.g. `TTR_FIN_Config.language` (replacing `[-LANGUAGE-].lua` with `_<lang>.lua`, e.g. `_de.lua`) and the log level.

---

## Troubleshooting

- **No NetworkCard found?** Server/client will assert — install a NetworkCard.
- **File not found:** Check the path relative to `/srv` (e.g. `development/...`).
- **Language not applied:** Verify `TTR_FIN_Config.language` in `config.lua` — the server replaces the exact string `[-LANGUAGE-].lua`.
- **No reaction:** Both sides are event driven. Ensure network reachability (port 8, same LAN zone).

---

## Quick checklist

- [ ] Copy **contents of `development/`** → **server disk** (`/srv/...`).  (`/srv/` is the root of your Mounted HardDrive)
- [ ] **`/srv/config.lua`** exists & language set.
- [ ] **Server EEPROM** = `Server.lua`. Running.
- [ ] **Client EEPROM** = `bootLoader.lua`, set **`local name = "[YOUR_PATH]/[YOUR_STARTER].lua"`** + needed vars (e.g. `fName`, `scrName`, `stationMin`).

You’re done — clients now boot their code from the central server and `require(...)` works without local files.
