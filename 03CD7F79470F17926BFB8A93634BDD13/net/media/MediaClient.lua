local names = {
    "helper.lua",
    "file/FileIO.lua",
    "net/media/basics.lua",
    "net/NetworkAdapter.lua",
    "net/NetHub.lua",
}
CodeDispatchClient:registerForLoading(names)
CodeDispatchClient:finished()


assert(type(FileIO) == "table" and type(FileIO.new) == "function", "MediaClient: FileIO benötigt")

MediaClient = setmetatable({}, { __index = NetworkAdapter })
MediaClient.__index = MediaClient

local function _ensure_dir(path)
    local dir = filesystem.path(path)
    if dir and not filesystem.exists(dir) then filesystem.makeDirectory(dir) end
end
local function _req_id() return tostring(now_ms()) .. "-" .. math.random(100000, 999999) end

-- interner Fallback-Lader, falls keine globale load_png(path) existiert
local function _fallback_load_png(path)
    -- 1) FINMediaSubsystem
    local msRef = component.findComponent("FINMediaSubsystem")[1]
    if msRef then
        local ms = component.proxy(msRef)
        if ms and ms.loadImage then
            local ok, img = pcall(ms.loadImage, ms, path)
            if ok and img then
                return {
                    ref    = img.ref or img.getRef and img:getRef() or img,
                    width  = img.width or img.getWidth and img:getWidth() or 512,
                    height = img.height or img.getHeight and img:getHeight() or 512,
                }
            end
        end
    end
    -- 2) GPU direkt
    local gpuRef = component.findComponent("GPUT2")[1]
    if gpuRef then
        local gpu = component.proxy(gpuRef)
        if gpu and gpu.loadImage then
            local ok, img = pcall(gpu.loadImage, gpu, path)
            if ok and img then
                return {
                    ref    = img.ref or img,
                    width  = img.width or 512,
                    height = img.height or 512,
                }
            end
        end
    end
    return nil, "no image loader available"
end

function MediaClient.new(opts)
    local self     = NetworkAdapter:new(opts)
    self           = setmetatable(self, MediaClient)
    self.name      = (opts and opts.name) or NET_NAME_MEDIA_SERVER
    self.port      = (opts and opts.port) or NET_PORT_MEDIA
    self.ver       = (opts and opts.ver) or 1
    self.cacheRoot = (opts and opts.cacheRoot) or "/tmp"
    self.fsio      = FileIO.new { root = self.cacheRoot, autoMount = true }
    self.pending   = {} -- reqId -> { rel, parts={}, done=false, err=nil, result=nil }


    log(0, ("MediaClient:init name=%s port=%d cache=%s")
        :format(self.name, self.port, self.cacheRoot))

    self:registerWith(function(from, port, cmd, reqId, relPath, payload)
        if port ~= self.port then return end
        local tr = self.pending[reqId]
        if not tr or tr.rel ~= relPath then return end

        if cmd == NET_CMD_MEDIA_CMD_CHUNK then
            tr.parts[#tr.parts + 1] = payload
        elseif cmd == NET_CMD_MEDIA_CMD_END then
            self.fsio:ensureMounted()

            log(0, "Mounted dev = " .. tostring(self.fsio:getMountedDevice()))
            log(0, "Mounted id  = " .. tostring(self.fsio:getMountedId()))

            local dst = self.fsio:abs(relPath)
            self.fsio:mkdir(relPath)
            --_ensure_dir(dst)
            local f = filesystem.open(dst, "wb")
            for i = 1, #tr.parts do f:write(tr.parts[i]) end
            f:close()
            tr.result, tr.done = dst, true
        elseif cmd == NET_CMD_MEDIA_CMD_ERR then
            tr.err, tr.done = (payload or "unknown"), true
            log(3, ("MediaClient:ERROR rel=%s err=%s"):format(relPath, tostring(tr.err)))
        end
    end)

    return self
end

function MediaClient:isCached(relPath)
    self.fsio:ensureMounted()
    local p = self.fsio:abs(relPath)
    local ok = filesystem.exists(p) and filesystem.isFile(p)
    log(1, ("MediaClient:isCached rel=%s -> %s"):format(relPath, tostring(ok)))
end

-- holt Datei → gibt lokalen Pfad
function MediaClient:fetch(relPath, timeout_ms)
    relPath    = tostring(relPath or "")
    timeout_ms = timeout_ms or 5000
    self.fsio:ensureMounted()

    if self:isCached(relPath) then
        local path = self.fsio:abs(relPath)
        log(0, ("MediaClient:CACHE_HIT rel=%s path=%s"):format(relPath, path))
        return path
    end

    local req = _req_id()
    self.pending[req] = { rel = relPath, parts = {}, done = false, err = nil, result = nil }

    local t0 = now_ms()
    log(0, ("MediaClient:FETCH rel=%s req=%s timeout=%dms"):format(relPath, req, timeout_ms))

    self:broadcast(NET_CMD_MEDIA_CMD_GET, req, relPath)

    local deadline = now_ms() + timeout_ms
    while true do
        if now_ms() >= deadline then
            self.pending[req] = nil
            log(3, ("MediaClient:TIMEOUT rel=%s req=%s"):format(relPath, req))
            return nil, "timeout"
        end
        local tr = self.pending[req]
        if tr.done then
            self.pending[req] = nil
            local dt = now_ms() - t0
            if tr.err then
                log(3, ("MediaClient:FAIL rel=%s req=%s ms=%d err=%s"):format(relPath, req, dt, tostring(tr.err)))
                return nil, tr.err
            else
                log(0, ("MediaClient:OK rel=%s req=%s ms=%d path=%s"):format(relPath, req, dt, tr.result))
                return tr.result, nil
            end
        end
        future.run()
    end
end

-- Komfort: holt Datei *und* lädt direkt als Bildobjekt (nutzt globale load_png, sonst Fallback)
function MediaClient:load_png_via_media(relPath, timeout_ms)
    local path, err = self:fetch(relPath, timeout_ms)
    if not path then return nil, err end
    if type(load_png) == "function" then
        local ok, img = pcall(load_png, path)
        if ok and img then
            log(1, ("MediaClient:IMG_LOADED via load_png rel=%s"):format(relPath))
            return img
        end
        log(2, ("MediaClient:IMG_FALLBACK rel=%s"):format(relPath))
    end
    local img, ferr = _fallback_load_png(path)
    if not img then
        log(3, ("MediaClient:IMG_FAIL rel=%s err=%s"):format(relPath, tostring(ferr)))
        return nil, ferr
    end
    log(1, ("MediaClient:IMG_LOADED via fallback rel=%s"):format(relPath))
    return img
end

local nic = computer.getPCIDevices(classes.NetworkCard)[1]
NetHub:init(nic)


--[[
-- Hub & NIC wie gewohnt
local nic = computer.getPCIDevices(classes.NetworkCard)[1]
NetHub:init(nic)

-- Client
local mediaCli = MediaClient.new{ nic = nic, cacheRoot="/tmp/media" }

-- Bild direkt laden
local img, err = mediaCli:load_png_via_media("icons/logo.png", 8000)
if not img then
  computer.log(3, "load_png_via_media failed: "..tostring(err))
else
  -- z.B. mit deiner graphics.lua zeichnen:
  -- root:drawLocalBox(img, Vector2d.new(100,100), Vector2d.new(img.width, img.height))
  -- gpu:flush()
end

]]
