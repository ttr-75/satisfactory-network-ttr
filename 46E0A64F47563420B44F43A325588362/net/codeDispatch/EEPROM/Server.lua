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
    self._mountedDev = nil -- z.B. "/dev/XYZ"
    self._mountedId  = nil -- z.B. "XYZ"
    return self
end

function FileIO:abs(rel) return _join(self.root, rel) end

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

-- Warum xpcall? Viele Event-Dispatcher „schlucken“ Errors.
-- Mit xpcall + traceback loggen wir jeden Fehler *sichtbar* (Level 4).
local function _traceback(tag)
    return function(err)
        local tb = debug.traceback(("%s: %s"):format(tag or "ListenerError", tostring(err)), 2)
        computer.log(4, tb)
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
    local content = fsio:readAllText(filename)
    local contentFn = load(content)
    xpcall(contentFn, _traceback("ServerStart"), "Failed to excecute " .. filename)
end

log(3, "Log-Level set to " .. TTR_FIN_Config.LOG_LEVEL)
log(0, "Laguage set to " .. TTR_FIN_Config.language)

local nic = computer.getPCIDevices(classes.NetworkCard)[1]
assert(nic, "Keine NIC")
NetHub:init(nic)

CodeDispatchServer = CodeDispatchServer.new()
CodeDispatchServer:run()
