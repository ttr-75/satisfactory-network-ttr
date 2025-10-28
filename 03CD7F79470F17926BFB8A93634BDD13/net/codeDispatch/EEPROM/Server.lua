LOG_MIN = 1

---@diagnostic disable: duplicate-doc-field, duplicate-set-field, redefined-local, lowercase-global


----------------------------------------------------------------
-- helper.lua – Kleine Helferlein für Logging
-- Optimiert & ausführlich kommentiert
----------------------------------------------------------------

-------------------------------
-- Logging
-------------------------------
-- Hinweis: LOG_MIN sollte global gesetzt sein (z. B. 0=Info, 1=Info+, 2=Warn, 3=Error, 4=Fatal)
-- Alte Version nutzte table.concat({ ... }, " "), was crasht, wenn ... Nicht-Strings enthält. (fix)
local function _to_strings(tbl)
    local out = {}
    for i = 1, #tbl do out[i] = tostring(tbl[i]) end
    return out
end

function log(level, ...)
    if level >= (LOG_MIN or 0) then
        local parts = _to_strings({ ... })     -- robust bei Zahlen, Booleans, Tabellen (tostring)
        computer.log(level, table.concat(parts, " "))
    end
end

--------------------------------------------------------------------------------
-- Konstanten (wie in deiner Originaldatei)
--------------------------------------------------------------------------------
NET_PORT_CODE_DISPATCH           = 8
NET_NAME_CODE_DISPATCH_CLIENT    = "CodeDispatchClient"
NET_NAME_CODE_DISPATCH_SERVER    = "CodeDispatchServer"

--NET_CMD_CODE_DISPATCH_SET_EEPROM = "CodeDispatchClient.setEEPROM"
--NET_CMD_CODE_DISPATCH_GET_EEPROM = "CodeDispatchClient.getEEPROM"
--NET_CMD_CODE_DISPATCH_RESET_ALL      = "CodeDispatchClient.resetAll"

NET_CMD_CODE_DISPATCH_SET_EEPROM = "setEEPROM"
NET_CMD_CODE_DISPATCH_GET_EEPROM = "getEEPROM"
NET_CMD_CODE_DISPATCH_RESET_ALL  = "resetAll"




----------------------------------------------------------------
-- FileIO (FicsIt Network kompatibel)
-- - Auto-Mount von /dev/* auf self.root (Default: "/srv")
-- - exists / isFile / isDir / list / mkdir / rm
-- - readAllText / readAllBinary / writeText / appendText / writeBinary
-- - copy / move / tryRead*
----------------------------------------------------------------

FileIO = {}
FileIO.__index = FileIO

-- ==== interne Helfer ====

local function _sanitize(rel)
    rel = tostring(rel or "")
    rel = rel:gsub("^/*", "")
    assert(not rel:find("%.%.", 1, true), "FileIO: Pfad darf kein '..' enthalten")
    return rel
end

local function _join(root, rel)
    rel = _sanitize(rel)
    if root == "/" then return "/" .. rel end
    if root:sub(-1) == "/" then return root .. rel end
    return root .. "/" .. rel
end

-- NEU: echtes dirname
local function _dirname(p)
    p = tostring(p or "")
    -- trailing slashes weg
    p = p:gsub("/+$", "")
    -- alles bis vor dem letzten / behalten
    local dir = p:match("^(.*)/[^/]*$") or ""
    if dir == "" then return "/" end
    return dir
end

-- Elternordner des ZIEL-Dateipfads sicherstellen
local function _ensure_parent_dir(filePath)
    local dir = _dirname(filePath)
    if dir and not filesystem.exists(dir) then
        filesystem.createDir(dir)     -- FN: createDir
    end
end


-- isDir kann unterschiedlich heißen; wir nehmen isDir, fallback isDirectory
local _isDirFn = filesystem.isDir or filesystem.isDirectory

-- ==== Konstruktor ====

-- opts.root       : Mountpunkt (Default "/srv")
-- opts.chunk      : Lesepuffer (Default 64*1024)
-- opts.autoMount  : true/false (Default true)
-- opts.searchFile : optionaler Dateiname zur Verifikation nach Mount
function FileIO.new(opts)
    local self       = setmetatable({}, FileIO)
    self.root        = (opts and opts.root) or "/srv"
    self.readChunk   = (opts and opts.chunk) or (64 * 1024)
    self.autoMount   = (opts and opts.autoMount ~= false)
    self.searchFile  = (opts and opts.searchFile) or nil

    self._mounted    = false
    self._mountedDev = nil     -- z.B. "/dev/XYZ"
    self._mountedId  = nil     -- z.B. "XYZ"
    return self
end

-- ==== Mount-Logik ====

function FileIO:_rootLooksReady()
    if not filesystem.exists(self.root) then return false end
    local ok = pcall(function() return filesystem.children(self.root) end)
    return ok
end

function FileIO:_tryMount()
    -- /dev initialisieren (FN)
    pcall(function() filesystem.initFileSystem("/dev") end)

    local devs = filesystem.children("/dev") or {}
    for _, dev in pairs(devs) do
        local drive = filesystem.path("/dev", dev)
        local ok = pcall(function() filesystem.mount(drive, self.root) end)
        if ok then
            -- Merken, welches Device wir gemountet haben
            self._mountedDev = drive
            self._mountedId  = tostring(drive):match("^/dev/(.+)$")

            if not self.searchFile then
                return true
            else
                local testPath = _join(self.root, self.searchFile)
                if filesystem.exists(testPath) then
                    return true
                else
                    pcall(function() filesystem.unmount(drive) end)
                    self._mountedDev, self._mountedId = nil, nil
                end
            end
        end
    end
    return false
end

function FileIO:ensureMounted()
    if self._mounted then return true end
    if self:_rootLooksReady() then
        self._mounted = true
        return true
    end
    if not self.autoMount then return false end
    local ok = self:_tryMount()
    self._mounted = ok and self:_rootLooksReady() or false
    return self._mounted
end

-- ==== public helpers ====

function FileIO:abs(rel) return _join(self.root, rel) end

function FileIO:getMountedDevice() return self._mountedDev end     -- "/dev/XYZ" oder nil

function FileIO:getMountedId() return self._mountedId end          -- "XYZ" oder nil

-- ==== Abfragen ====

function FileIO:exists(rel)
    self:ensureMounted()
    return filesystem.exists(self:abs(rel))
end

function FileIO:isFile(rel)
    self:ensureMounted()
    local p = self:abs(rel)
    return filesystem.exists(p) and filesystem.isFile(p)
end

function FileIO:isDir(rel)
    self:ensureMounted()
    local p = self:abs(rel)
    if not filesystem.exists(p) then return false end
    if _isDirFn then
        return _isDirFn(p)
    end
    -- Fallback (falls weder isDir noch isDirectory existiert):
    -- Heuristik: ein Pfad ist "Dir", wenn children nicht fehlschlägt.
    local ok = pcall(function() return filesystem.children(p) end)
    return ok
end

function FileIO:list(rel)
    self:ensureMounted()
    local p = self:abs(rel or "")
    if not filesystem.exists(p) then return {} end
    return filesystem.children(p) or {}
end

-- ==== Erstellen / Löschen ====

function FileIO:mkdir(rel)
    self:ensureMounted()
    filesystem.createDir(self:abs(rel))
end

function FileIO:rm(rel, rekursiv)
    self:ensureMounted()
    local p = self:abs(rel)
    if rekursiv and ((_isDirFn and _isDirFn(p)) or (not _isDirFn and filesystem.exists(p))) then
        for _, name in ipairs(filesystem.children(p) or {}) do
            self:rm(_sanitize(rel) .. "/" .. name, true)
        end
    end
    filesystem.remove(p)
end

-- ==== Lesen/Schreiben ====

function FileIO:readAllText(rel)
    self:ensureMounted()
    local p = self:abs(rel)
    local f = filesystem.open(p, "r")
    assert(f, "FileIO: kann Datei nicht öffnen (r): " .. p)
    local buf, chunk = "", nil
    repeat
        chunk = f:read(self.readChunk)
        if chunk then buf = buf .. chunk end
    until not chunk
    f:close()
    return buf
end

function FileIO:readAllBinary(rel)
    self:ensureMounted()
    local p = self:abs(rel)
    local f = filesystem.open(p, "rb")
    assert(f, "FileIO: kann Datei nicht öffnen (rb): " .. p)
    local buf, chunk = "", nil
    repeat
        chunk = f:read(self.readChunk)
        if chunk then buf = buf .. chunk end
    until not chunk
    f:close()
    return buf
end

function FileIO:writeText(rel, text)
    self:ensureMounted()
    local p = self:abs(rel)
    _ensure_parent_dir(p)
    local f = filesystem.open(p, "w")
    assert(f, "FileIO: kann Datei nicht öffnen (w): " .. p)
    f:write(tostring(text or ""))
    f:close()
end

function FileIO:appendText(rel, text)
    self:ensureMounted()
    local p = self:abs(rel)
    _ensure_parent_dir(p)
    local f = filesystem.open(p, "a")
    assert(f, "FileIO: kann Datei nicht öffnen (a): " .. p)
    f:write(tostring(text or ""))
    f:close()
end

function FileIO:writeBinary(rel, bytes)
    self:ensureMounted()
    local p = self:abs(rel)
    _ensure_parent_dir(p)
    local f = filesystem.open(p, "wb")
    assert(f, "FileIO: kann Datei nicht öffnen (wb): " .. p)
    f:write(bytes or "")
    f:close()
end

function FileIO:writeBinaryArray(rel, bytes)
    self:ensureMounted()
    local p = self:abs(rel)
    _ensure_parent_dir(p)
    local f = filesystem.open(p, "wb")
    assert(f, "FileIO: kann Datei nicht öffnen (wb): " .. p)
    for i = 1, #bytes do
        f:write(bytes[i] or "")
    end
    f:close()
end

-- ==== Utilities ====

function FileIO:copy(srcRel, dstRel)
    local src = self:readAllBinary(srcRel)
    self:writeBinary(dstRel, src)
end

function FileIO:move(srcRel, dstRel)
    self:copy(srcRel, dstRel)
    self:rm(srcRel)
end

function FileIO:tryReadText(rel)
    local ok, res = pcall(function() return self:readAllText(rel) end)
    if ok then return res end
    return nil, res
end

function FileIO:tryReadBinary(rel)
    local ok, res = pcall(function() return self:readAllBinary(rel) end)
    if ok then return res end
    return nil, res
end

-------------------------------------------------------
--- NetHub
-------------------------------------------------------

--- Ein Dienst-Eintrag in NetHub.services
---@class NetServiceEntry
---@field handler  NetHandler
---@field _wrapped NetHandler
---@field name     NetName|nil
---@field ver      NetVersion

--- NetHub-Singleton
---@class NetHubClass
---@field nic NIC|nil
---@field listenerId any|nil
---@field services table<NetPort, NetServiceEntry>
NetHub = {
    nic = nil,
    listenerId = nil,
    services = {},     -- [port] = { handler=fn, name="MEDIA", ver=1 }
}

-- fallback wrapper if safe_listener isn't loaded
---@param tag string
---@return fun(err:any):string
local function _traceback(tag)
    return function(err)
        local tb = debug.traceback(("%s: %s"):format(tag or "ListenerError", tostring(err)), 2)
        computer.log(4, tb)
        return tb
    end
end

---@param tag string
---@param fn  NetHandler
---@return NetHandler
local function _wrap(tag, fn)
    if type(safe_listener) == "function" then
        return safe_listener(tag, fn)
    end
    return function(...)
        local ok, res = xpcall(fn, _traceback(tag), ...)
        return res
    end
end

--- Initialisiert den Hub (einmalig), hört auf NetworkMessage und verteilt pro Port.
---@param nic NIC|nil  -- optional explizite NIC; sonst erste gefundene
function NetHub:init(nic)
    if self.listenerId then return end
    self.nic = nic or computer.getPCIDevices(classes.NetworkCard)[1]
    assert(self.nic, "NetHub: keine NIC gefunden")
    event.listen(self.nic)

    local f = event.filter { event = "NetworkMessage" }
    self.listenerId = event.registerListener(f, _wrap("NetHub.Dispatch",
        ---@param _ev string
        ---@param _nic any
        ---@param fromId string
        ---@param port NetPort
        ---@param cmd NetCommand
        ---@param a any
        ---@param b any
        ---@param c any
        ---@param d any
        function(_, _, fromId, port, cmd, a, b, c, d)
            local svc = self.services[port]
            if not svc then return end
            -- delegate to per-port wrapped handler (already safe-wrapped in :register)
            return svc._wrapped(fromId, port, cmd, a, b, c, d)
        end))

    computer.log(0, "NetHub: ready")
end

--- Registriert einen Handler für Port/Name/Version; öffnet den Port auf der NIC.
---@param port NetPort
---@param name NetName|nil
---@param ver  NetVersion|nil
---@param handler NetHandler
function NetHub:register(port, name, ver, handler)
    assert(type(port) == "number" and handler, "NetHub.register: ungültig")
    local wrapped = _wrap("NetHub." .. tostring(name or port), handler)
    self.services[port] = { handler = handler, _wrapped = wrapped, name = name, ver = ver or 1 }
    self.nic:open(port)     -- Port EINMAL hier öffnen
end

--- Beendet den Listener und leert die Service-Tabelle.
function NetHub:close()
    if self.listenerId and event.removeListener then event.removeListener(self.listenerId) end
    self.listenerId = nil
    self.services = {}
end

-- Standardport (aus deiner Originaldatei)
---@type integer
NET_PORT_DEFAULT       = 8

--------------------------------------------------------------------------------
-- NetworkAdapter – Typ-Annotationen (EmmyLua/LuaLS)
-- Hinweis: Diese Datei verändert KEIN Laufzeitverhalten – nur Kommentare.
-- Erwartet, dass NetHub global verfügbar ist (mit NetHub:register/init).
--------------------------------------------------------------------------------

---@class NetworkAdapter
---@field port NetPort
---@field name NetName
---@field ver  NetVersion
---@field net  NIC
NetworkAdapter         = {}
NetworkAdapter.__index = NetworkAdapter

---@class NetworkAdapterOpts
---@field port NetPort|nil
---@field name NetName|nil
---@field ver  NetVersion|nil
---@field nic  NIC|nil

---@generic T: NetworkAdapter
---@param self T
---@param opts NetworkAdapterOpts|nil
---@return T
function NetworkAdapter:new(opts)
    local o = setmetatable({}, self)
    o.port  = (opts and opts.port) or NET_PORT_DEFAULT
    o.name  = (opts and opts.name) or "NetworkAdapter"
    o.ver   = (opts and opts.ver) or 1
    o.net   = (opts and opts.nic) or computer.getPCIDevices(classes.NetworkCard)[1]
    return o
end

--- Registriert einen Paket-Handler beim NetHub auf self.port/self.name/self.ver.
--- Der Handler wird bei eingehenden NetworkMessage-Paketen auf diesem Port aufgerufen.
---@param fn NetHandler
function NetworkAdapter:registerWith(fn)
    NetHub:register(self.port, self.name, self.ver, fn)
end

--- Sendet eine Direktnachricht an eine Ziel-NIC.
---@param toId string
---@param cmd NetCommand
---@param ... any
function NetworkAdapter:send(toId, cmd, ...)
    self.net:send(toId, self.port, cmd, ...)
end

--- Broadcastet eine Nachricht auf diesem Adapter-Port.
---@param cmd NetCommand
---@param ... any
function NetworkAdapter:broadcast(cmd, ...)
    self.net:broadcast(self.port, cmd, ...)
end

-- Erwartete globale Konstante (nur Typ-Hinweis; keine Zuweisung hier):
---@type NetPort
NET_PORT_DEFAULT = NET_PORT_DEFAULT


----------------------------------------------------------------
-- helper_comments.lua – Kleine Helferlein
----------------------------------------------------------------


function drop_line_comments_stripws(text)
    local out = {}
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do
        local trimmed = line:match("^%s*(.*)$") or ""
        if trimmed:sub(1, 2) == "--" and trimmed:sub(1, 4) ~= "--[[" then
            -- Kommentarzeile -> weg
        else
            out[#out + 1] = line
        end
    end
    return table.concat(out, "\n")
end

-- Entfernt Kommentare aus Lua-Quelltext und wirft Leerzeilen raus.
-- Respektiert Strings ('...' / "..." / [[...]] / [=[...]=]).
function strip_lua_comments_and_blank(content)
    assert(type(content) == "string", "string expected")

    local i, n = 1, #content
    local out = {}            -- Puffer für Ausgabe
    local mode = "normal"     -- "normal" | "line_comment" | "block_comment" | "str" | "lstr"
    local str_quote = nil     -- ' oder "
    local lsep = ""           -- ==== bei long string/comment

    -- Matches:  --[=*[   bzw.   ]=*]
    local function long_open_at(pos)
        local eqs = content:match("^%[(=*)%[", pos)
        if eqs then return eqs end
        return nil
    end
    local function long_close_at(pos)
        local eqs = content:match("^%](=*)%]", pos)
        if eqs then return eqs end
        return nil
    end

    while i <= n do
        if mode == "normal" then
            local c = content:sub(i, i)
            local c2 = content:sub(i, i + 1)

            -- Start einer Kommentar-Sequenz?
            if c2 == "--" then
                -- Zeilen- oder Block-Kommentar?
                local eqs = long_open_at(i + 2)
                if eqs ~= nil then
                    mode = "block_comment"; lsep = eqs; i = i + 2 + 1 + #eqs     -- steht auf erstem '[' der Öffnung
                else
                    mode = "line_comment"; i = i + 2
                end

                -- Long String?
            elseif c == "[" then
                local eqs = long_open_at(i)
                if eqs ~= nil then
                    mode = "lstr"; lsep = eqs
                    -- gesamten Delimiter rausgeben
                    table.insert(out, "[" .. eqs .. "[")
                    i = i + 2 + #eqs
                else
                    table.insert(out, c); i = i + 1
                end

                -- Normaler String?
            elseif c == "'" or c == '"' then
                mode = "str"; str_quote = c
                table.insert(out, c); i = i + 1
            else
                table.insert(out, c); i = i + 1
            end
        elseif mode == "line_comment" then
            -- bis Zeilenende überspringen, Newline aber behalten
            local nl1 = content:find("\n", i, true)
            if nl1 then
                table.insert(out, "\n")
                i = nl1 + 1
            else
                break     -- Ende der Datei: Kommentar ignorieren, keine NL mehr
            end
        elseif mode == "block_comment" then
            -- bis passendes ]=*=] überspringen
            local eqs = long_close_at(i)
            if eqs ~= nil and eqs == lsep then
                i = i + 2 + #eqs     -- nach dem schließenden ]
                mode = "normal"
            else
                i = i + 1
            end
        elseif mode == "str" then
            -- normaler String, mit Escape-Handling
            local c = content:sub(i, i)
            table.insert(out, c)
            if c == "\\" then
                -- escapen: nächstes Zeichen blind übernehmen
                local nextc = content:sub(i + 1, i + 1)
                if nextc ~= "" then
                    table.insert(out, nextc); i = i + 2
                else
                    i = i + 1
                end
            elseif c == str_quote then
                mode = "normal"; i = i + 1
            else
                i = i + 1
            end
        elseif mode == "lstr" then
            -- long string: bis passenden ]=*=]
            local eqs = long_close_at(i)
            if eqs ~= nil and eqs == lsep then
                table.insert(out, "]" .. eqs .. "]")
                i = i + 2 + #eqs
                mode = "normal"
            else
                table.insert(out, content:sub(i, i))
                i = i + 1
            end
        end
    end

    -- String zusammenbauen und Leerzeilen rauswerfen
    local text = table.concat(out)
    local cleaned = {}
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do
        local trimmed = line:match("^%s*(.-)%s*$") or ""
        if trimmed ~= "" then
            table.insert(cleaned, trimmed)
        end
    end
    return table.concat(cleaned, "\n")
end

-------------------------------------------------------------------------------
--- CodeDispatchServer
-------------------------------------------------------------------------------

---@class CodeDispatchServer : NetworkAdapter
---@field fsio FileIO
local CodeDispatchServer = setmetatable({}, { __index = NetworkAdapter })
CodeDispatchServer.__index = CodeDispatchServer

---@param opts table|nil
---@return CodeDispatchServer
function CodeDispatchServer.new(opts)
    -- generischer Basiskonstruktor → sofort ein CodeDispatchServer-Objekt
    local self = NetworkAdapter.new(CodeDispatchServer, opts)
    self.name  = NET_NAME_CODE_DISPATCH_SERVER
    self.port  = NET_PORT_CODE_DISPATCH
    self.ver   = 1

    self.fsio  = FileIO.new { root = "/srv" }
    -- Listener registrieren (reiner Dispatch)
    self:registerWith(function(from, port, cmd, programName, code)
        if port ~= self.port then return end
        if cmd == NET_CMD_CODE_DISPATCH_GET_EEPROM then
            self:onGetEEPROM(from, tostring(programName or ""))
        end
    end)

    return self
end

--=== Prototyp-Methoden =======================================================

--- Antwortet auf GET_EEPROM mit dem angeforderten Code.
---@param fromId string
---@param programName string
function CodeDispatchServer:onGetEEPROM(fromId, programName)
    local fallback = [[
            print("Invalid Net-Boot-Program: Program not found!")
            event.pull(5)
            computer.reset()
        ]]

    local ok, code = pcall(function()
        return strip_lua_comments_and_blank(self.fsio:readAllText(programName))
    end)

    local payload = (ok and code) or fallback
    log(1, ('CodeDispatchServer: request "%s" from "%s"'):format(programName, tostring(fromId)))
    self:send(fromId, NET_CMD_CODE_DISPATCH_SET_EEPROM, programName, payload)
end

--- Optionale Lauf-Schleife.
function CodeDispatchServer:run()
    self:broadcast(NET_CMD_CODE_DISPATCH_RESET_ALL)
    log(1, "CodeDispatchServer: broadcast resetAll")
    while true do
        future.run()
    end
end

local nic = computer.getPCIDevices(classes.NetworkCard)[1]
assert(nic, "Keine NIC")
NetHub:init(nic)

CodeDispatchServer = CodeDispatchServer.new()

CodeDispatchServer:run()
