# Network Boot & File Server (FIN) – Guide

This setup turns **one FIN computer into a central file server**. All **clients boot transparently from the network** and can keep using local `require(...)` — missing files are fetched automatically from the server. This is handled by **CodeDispatchServer/Client** via broadcast and an in‑memory `require` implementation.

---

## Folder layout & copying

- **Important:** Copy **only the *contents of* `development/`** to the **server’s disk** (e.g. `/srv/...`) (`/srv/` is the root of your Mounted HardDrive). You can add your own files there as well.
- Put **`config.lua`** in the **root of the server disk** (e.g. `/srv/config.lua`).

---

## Architecture (High-Level)

```
[ Clients ] --(FIN Port 8)--> [ Server ] --(FileIO)--> [/srv/<your files>]
       ^                            |
       |                            +-- replaces "[-LANGUAGE-].lua" → "_<lang>.lua"
       +-- require() ↔ network → per-client cache
```

- **Client** sends `GET_EEPROM` with the module name, then waits.
- **Server** reads the file from `/srv/<name>`, performs the language replacement, and replies with `setEEPROM` containing the source code.
- **Client** loads the code in its own `require`-enabled environment and caches return values as usual.

---

## Set up the server

1. Boot the server computer with a **NetworkCard** and a disk.
2. Flash the **server’s EEPROM** with **`Server.lua`** (1:1). On boot it will:
   - mount `/srv` and load `config.lua`,
   - replace `[-LANGUAGE-].lua` in requested files according to `TTR_FIN_Config.language`,
   - start **CodeDispatchServer** on port `8` to serve code.
3. Let it run — it sends a single `resetAll` and then waits for requests.

---

## Set up a client

1. Boot the client with a **NetworkCard**.
2. Flash the **client’s EEPROM** with **`bootLoader.lua`**.  
   In that file **set the start script** (on the server) and optionally **provide parameters**:

```lua
-- bootLoader.lua (excerpt)
-- start script on the server:
local name = "[YOUR_PATH]/[YOUR_STARTER].lua"

-- optional variables expected by the starter:
fName   = "YOUR_FACTORY_NAME"
scrName = "YOUR_SCREEN_NAME"  -- dashboard only
-- stationMin = 2              -- optional for InfoCollector
```

The client fetches `name` from the network and runs modules using a local in‑memory `require`; dependencies are loaded on demand.

---

## The three starters (optional and work in progress)

The starters live in `development/factoryRegistry/starter/…` and are **selected via `local name = ".../starter/<file>.lua"`**.

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

---

## How loading works (transparent `require`)

- The client sends `getEEPROM <file>` on port `8`. The server reads from `/srv/...`, optionally replaces `[-LANGUAGE-].lua` according to `config.lua`, and returns the source.
- The client executes the code **in its own environment with a local `require`**. Modules are **cached**; cyclic requires are handled.

---

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
- [ ] **Client EEPROM** = `bootLoader.lua`, set **`local name = ".../starter/<file>.lua"`** + needed vars (`fName`, `scrName`, `stationMin`).

You’re done — clients now boot their code from the central server and `require(...)` works without local files.
