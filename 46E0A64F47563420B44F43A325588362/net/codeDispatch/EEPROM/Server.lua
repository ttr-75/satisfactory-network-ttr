local function _to_strings(tbl)
    local out = {}
    for i = 1, #tbl do out[i] = tostring(tbl[i]) end
    return out
end

function log(level, ...)
    if level >= (LOG_MIN or TTR_FIN_Config and TTR_FIN_Config.LOG_LEVEL or 0) then
        local parts = _to_strings({ ... }) -- robust bei Zahlen, Booleans, Tabellen (tostring)
        computer.log(level, table.concat(parts, " "))
    end
end

-- Beispiel:
-- log(0, "Hello", 123, true)  -> "Hello 123 true"


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

local FileIO = {}
FileIO.__index = FileIO


-- ==== Konstruktor ============================================================

--- Erzeugt eine neue FileIO-Instanz.
---@param opts {root?:string, chunk?:integer, autoMount?:boolean, searchFile?:string}|nil
---@return FileIO
function FileIO.new(opts)
    local self       = setmetatable({}, FileIO)
    self.root        = (opts and opts.root) or "/srv"
    self.readChunk   = (opts and opts.chunk) or (64 * 1024)
    self.autoMount   = (opts and opts.autoMount ~= false) -- Default: true
    self.searchFile  = (opts and opts.searchFile) or nil

    self._mounted    = false
    self._mountedDev = nil -- z. B. "/dev/XYZ"
    self._mountedId  = nil -- z. B. "XYZ"
    return self
end

--- Safe open: ok, file|nil, err
---@param path string
---@param mode string
---@return boolean, any|nil, string|nil
local function _safe_open(path, mode)
    local ok, f = pcall(function() return filesystem.open(path, mode) end)
    if not ok or not f then
        local msg = (ok and "open returned nil") or tostring(f)
        return false, nil, _err("open(" .. tostring(mode) .. ")", path, msg)
    end
    return true, f, nil
end

--- Safe call Wrapper: ok, result|nil, err
---@param where string
---@param path string
---@param fn fun():any
---@return boolean, any|nil, string|nil
local function _pcall(where, path, fn)
    local ok, res = pcall(fn)
    if not ok then
        return false, nil, _err(where, path, res)
    end
    return true, res, nil
end


--- Absoluten Pfad unterhalb von root bilden.
---@param rel string
---@return string
function FileIO:abs(rel) return _join(self.root, rel) end

--- Stellt sicher, dass root bereit/montiert ist (führt ggf. Auto-Mount aus).
---@return boolean, nil|nil, string|nil
function FileIO:ensureMounted()
    if self._mounted then return true end
    if self:_rootLooksReady() then
        self._mounted = true
        log(1, "FileIO: root ready:", self.root)
        return true
    end
    if not self.autoMount then
        return false, nil, _err("ensureMounted", self.root, "root not ready and autoMount=false")
    end
    local ok = self:_tryMount()
    self._mounted = ok and self:_rootLooksReady() or false
    if not self._mounted then
        return false, nil, _err("ensureMounted", self.root, "could not mount any /dev/*")
    end
    log(1, "FileIO: mounted on", self.root, "device:", self._mountedDev or "?")
    return true
end

--- Prüft heuristisch, ob root bereits „benutzbar“ ist (existiert + children abrufbar).
---@return boolean
function FileIO:_rootLooksReady()
    if not filesystem.exists(self.root) then return false end
    local ok = pcall(function() return filesystem.children(self.root) end)
    return ok
end

--- Versucht, irgendein /dev/* auf root zu mounten (optional verifiziert via searchFile).
---@return boolean
function FileIO:_tryMount()
    -- /dev initialisieren (FIN)
    pcall(function() filesystem.initFileSystem("/dev") end)

    local devs = filesystem.children("/dev") or {}
    for _, dev in pairs(devs) do
        local drive = filesystem.path("/dev", dev)
        local okMnt = pcall(function() filesystem.mount(drive, self.root) end)
        if okMnt then
            -- gemountetes Device merken
            self._mountedDev = drive
            self._mountedId  = tostring(drive):match("^/dev/(.+)$")

            if not self.searchFile then
                return true
            else
                local testPath = _join(self.root, self.searchFile)
                if filesystem.exists(testPath) then
                    return true
                else
                    -- nicht der richtige Datenträger → wieder auswerfen
                    pcall(function() filesystem.unmount(drive) end)
                    self._mountedDev, self._mountedId = nil, nil
                end
            end
        end
    end
    return false
end

--- Liest Textdatei komplett (UTF-8/ASCII).
---@param rel string
---@return boolean, string|nil, string|nil
function FileIO:readAllText(rel)
    local ok = self:ensureMounted(); if not ok then return false, nil, "not mounted" end
    local p = self:abs(rel)

    local okOpen, f, e = _safe_open(p, "r")
    if not okOpen then return false, nil, e end

    local buf = ""
    while true do
        local okRead, chunk, er = _pcall("readAllText/read", p, function() return f:read(self.readChunk) end)
        if not okRead then
            f:close(); return false, nil, er
        end
        if not chunk then break end
        buf = buf .. chunk
    end

    f:close()
    return true, buf, nil
end

-- Warum xpcall? Viele Event-Dispatcher „schlucken“ Errors.
-- Mit xpcall + traceback loggen wir jeden Fehler *sichtbar* (Level 4).
local function _traceback(tag)
    return function(err)
        local tb = debug.traceback(("%s: %s"):format(tag or "ListenerError", tostring(err)), 2)
        log(4, tb)
        return tb
    end
end

CodeDispatchClient = {}
function CodeDispatchClient:registerForLoading(n) end

function CodeDispatchClient:finished() end

local fsio = FileIO.new { root = "/srv" }

local loadFiles = {
    "config.lua",
    "shared/helper_log.lua",
    "shared/helper.lua",
    "shared/serializer.lua",
    "shared/helper_comments.lua",
    "net/NetworkAdapter.lua",
    "net/NetHub.lua",
    "file/FileIO.lua",
    "net/codeDispatch/basics.lua",
    "net/codeDispatch/CodeDispatchServer.lua",
}

for _, filename in pairs(loadFiles) do
    local ok, data, err = fsio:readAllText(filename)
    if not ok then
        log(4, "Failed to read " .. filename, err)
        return
    end
    local contentFn = load(data)
    xpcall(contentFn, _traceback("ServerStart"), "Failed to excecute " .. filename)
end

log(2, "Log-Level set to " .. TTR_FIN_Config.LOG_LEVEL)
log(0, "Laguage set to " .. TTR_FIN_Config.language)

local nic = computer.getPCIDevices(classes.NetworkCard)[1]
assert(nic, "Keine NIC")
NetHub:init(nic)

CodeDispatchServer = CodeDispatchServer.new()
CodeDispatchServer:run()
