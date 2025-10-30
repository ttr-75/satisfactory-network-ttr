---@meta
--------------------------------------------------------------------------------
-- FIN Core Stubs (verdichtet für IntelliSense)
-- Quelle/Signaturen: FINLuaDocumentation.lua (deine hochgeladene API)
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- Klassen-Basis
--------------------------------------------------------------------------------
---@class FINClass
---@field name string

---@class FINObjectProxy
---@field hash integer
---@field internalName string
---@field internalPath string
---@field nick string
---@field ID string
---@field isNetworkComponent boolean
local FINObjectProxy = {}

---@return integer
function FINObjectProxy:getHash() return 0 end

---@return FINClass
function FINObjectProxy:getType() return { name = "Object" } end

---@param parent FINClass|FINObjectProxy
---@return boolean
function FINObjectProxy:isA(parent) return false end

-- Klassenfunktionen lt. Doku
---@param obj FINObjectProxy
---@return integer
function FINObjectProxy.getHash(obj) return obj and obj.hash or 0 end

---@param obj FINObjectProxy
---@return FINClass
function FINObjectProxy.getType(obj) return obj and obj:getType() or { name = "" } end

---@param parent FINClass|FINObjectProxy
---@param child  FINClass|FINObjectProxy
---@return boolean
function FINObjectProxy.isChildOf(parent, child) return false end

--------------------------------------------------------------------------------
-- Structs
--------------------------------------------------------------------------------
---@class FINVector
---@field x number
---@field y number
---@field z number
local FINVector = {}
FINVector.__index = FINVector
function FINVector.new(x, y, z) return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, FINVector) end

---@param other FINVector @Operator Add
---@return FINVector
function FINVector:FIR_Operator_Add(other) return FINVector.new() end

---@param other FINVector @Operator Sub
---@return FINVector
function FINVector:FIR_Operator_Sub(other) return FINVector.new() end

---@return FINVector @Operator Neg
function FINVector:FIR_Operator_Neg() return FINVector.new() end

---@param other FINVector @Operator Mul (vector)
---@return FINVector
function FINVector:FIR_Operator_Mul(other) return FINVector.new() end

---@param factor number @Vector Factor Scaling
---@return FINVector
function FINVector:FIR_Operator_Mul_1(factor) return FINVector.new() end

---@class FINRotator
---@field pitch number
---@field yaw number
---@field roll number
local FINRotator = {}
FINRotator.__index = FINRotator
function FINRotator.new(p, y, r) return setmetatable({ pitch = p or 0, yaw = y or 0, roll = r or 0 }, FINRotator) end

--------------------------------------------------------------------------------
-- Actor (erbt von Object)
--------------------------------------------------------------------------------
---@class PowerConnection: FINObjectProxy end
---@class FactoryConnection: FINObjectProxy end
---@class PipeConnectionBase: FINObjectProxy end
---@class ActorComponent: FINObjectProxy end

---@class Inventory: FINObjectProxy

local Inventory = {}
---@param index integer
---@return { item: { type: { name: string, max: integer } }, count: integer }
function Inventory:getStack(index) return { item = { type = { name = "", max = 0 } }, count = 0 } end

---@return integer
function Inventory:getSize() return self.size or 0 end

---@class FINActorProxy: FINObjectProxy
---@field location FINVector
---@field scale FINVector
---@field rotation FINRotator
local FINActorProxy = {}
setmetatable(FINActorProxy, { __index = FINObjectProxy })

---@return PowerConnection[]
function FINActorProxy:getPowerConnectors() return {} end

---@return FactoryConnection[]
function FINActorProxy:getFactoryConnectors() return {} end

---@return PipeConnectionBase[]
function FINActorProxy:getPipeConnectors() return {} end

---@return Inventory[]
function FINActorProxy:getInventories() return {} end

---@overload fun():ActorComponent[]
---@param componentType FINClass|nil
---@return ActorComponent[]
function FINActorProxy:getComponents(componentType) return {} end

---@return ActorComponent[]
function FINActorProxy:getNetworkConnectors() return {} end

-- Klassenfunktionen
---@param obj FINActorProxy
---@return integer
function FINActorProxy.getHash(obj) return obj and obj.hash or 0 end

---@param obj FINActorProxy
---@return FINClass
function FINActorProxy.getType(obj) return obj and obj:getType() or { name = "Actor" } end

---@param parent FINClass|FINObjectProxy
---@param child  FINClass|FINObjectProxy
---@return boolean
function FINActorProxy.isChildOf(parent, child) return false end

--------------------------------------------------------------------------------
-- component (proxy & findComponent)
--------------------------------------------------------------------------------
---@class Object: FINObjectProxy end  -- Notation aus der API
---@class ObjectClass end             -- “Object-Class” Platzhalter

---@class ComponentLib
local component = {}

--- Erzeugt Instanzen (oder Arrays davon) aus UUID(s)
---@param ... string|string[]
---@return Object|Object[]|nil ...
function component.proxy(...) end

--- Sucht Komponenten per Nick-Query oder Klassentyp
---@param ... string|ObjectClass
---@return string[] ...
function component.findComponent(...) end

_G.component = component

--------------------------------------------------------------------------------
-- event / Future / future / sleep / async
--------------------------------------------------------------------------------
---@class EventFilter
local EventFilter = {}

---@class EventQueue
local EventQueue = {}
---@param timeout number
---@return string|nil, Object, any
function EventQueue.pull(timeout) end

---@param filter EventFilter|{event?:string|string[],sender?:Object|Object[],values?:table<string,any>}
---@return string|nil, Object, any
function EventQueue.waitFor(filter) end

local event = {}
---@param ... Object
function event.listen(...) end

---@return Object[]
function event.listening() return {} end

---@param timeout number
---@return string|nil, Object, any
function event.pull(timeout) end

---@param ... Object
function event.ignore(...) end

function event.ignoreAll() end

function event.clear() end

---@param params {event?:string|string[],sender?:Object|Object[],values?:table<string,any>}
---@return EventFilter
function event.filter(params) return {} end

---@param filter EventFilter|{event?:string|string[],sender?:Object|Object[],values?:table<string,any>}
---@param cb fun(event:string,sender:Object,...)
function event.registerListener(filter, cb) end

---@param filter EventFilter|{event?:string|string[],sender?:Object|Object[],values?:table<string,any>}
---@return EventQueue
function event.queue(filter) return setmetatable({}, { __index = EventQueue }) end

---@param filter EventFilter|{event?:string|string[],sender?:Object|Object[],values?:table<string,any>}
---@return string|nil, Object, any
function event.waitFor(filter) end

_G.event = event

---@class Future
local Future = {}
---@return any
function Future.get() end

---@return boolean, Future|nil
function Future.poll() end

---@return any
function Future.await() end

---@return boolean
function Future.canGet() end

_G.Future = Future

local future = {}
---@param thread thread
---@return Future
function future.async(thread) return Future end

---@param ... Future
---@return Future
function future.join(...) return Future end

---@param ... Future
---@return Future
function future.any(...) return Future end

---@param seconds number
---@return Future
function future.sleep(seconds) return Future end

function future.addTask(...) end

function future.run() return false end

function future.loop() end

_G.future = future

---@type fun(fn:fun(...), ...):Future
async = function() return Future end
---@type fun(seconds:number)
sleep = function() end

--------------------------------------------------------------------------------
-- computer (nur die häufig genutzten Signaturen)
--------------------------------------------------------------------------------
local computer = {}
---@return integer usage, integer capacity
function computer.getMemory() end

---@return integer
function computer.millis() end

function computer.reset() end

function computer.stop() end

---@param code string
function computer.setEEPROM(code) end

---@return string
function computer.getEEPROM() end

---@param pitch number
function computer.beep(pitch) end

---@param error string
function computer.panic(error) end

---@param type ObjectClass|nil
---@return Object[]
function computer.getPCIDevices(type) return {} end

---@param text string
---@param username string|nil
function computer.textNotification(text, username) end

---@param position FINVector
---@param username string|nil
function computer.attentionPing(position, username) end

---@return number
function computer.time() end

---@param verbosity integer
---@param message string
function computer.log(verbosity, message) end

_G.computer = computer



--------------------------------------------------------------------------------
-- FINBuildable (generic buildable actor)
--------------------------------------------------------------------------------
---@class FINBuildable : FINActorProxy
local FINBuildable = {}
setmetatable(FINBuildable, { __index = (FINActorProxy or {}) })

---Buildables besitzen in FIN i. d. R. die gleichen Connector-/Inventory-APIs
---wie Actor; wir spiegeln die Signaturen hier erneut für klare Hints.

---@return PowerConnection[]
function FINBuildable:getPowerConnectors() return {} end

---@return FactoryConnection[]
function FINBuildable:getFactoryConnectors() return {} end

---@return PipeConnectionBase[]
function FINBuildable:getPipeConnectors() return {} end

---@return Inventory[]
function FINBuildable:getInventories() return {} end

---@overload fun():ActorComponent[]
---@param componentType FINClass|nil
---@return ActorComponent[]
function FINBuildable:getComponents(componentType) return {} end

---@return ActorComponent[]
function FINBuildable:getNetworkConnectors() return {} end

--------------------------------------------------------------------------------
-- FGBuildableStorage (Satisfactory storage container / industrial storage)
--------------------------------------------------------------------------------
---@class FGBuildableStorage : FINBuildable
local FGBuildableStorage = {}
setmetatable(FGBuildableStorage, { __index = FINBuildable })

--- Convenience: viele FIN-Implementierungen bieten eine direkte Inventar-
--- Abfrage an. Falls bei dir nur getInventories() existiert, nutze das.
---@return Inventory|nil
function FGBuildableStorage:getInventory() return nil end

---@return Inventory[]
function FGBuildableStorage:getInventories() return {} end

-- (Optional) Wenn dein Storage Ein-/Ausgangs-Connectoren besitzt:
---@return FactoryConnection[]
function FGBuildableStorage:getFactoryConnectors() return {} end

---@return PowerConnection[]
function FGBuildableStorage:getPowerConnectors() return {} end

---@return PipeConnectionBase[]
function FGBuildableStorage:getPipeConnectors() return {} end

return {
  FINBuildable       = FINBuildable,
  FGBuildableStorage = FGBuildableStorage,
  FINObjectProxy     = FINObjectProxy,
  FINActorProxy      = FINActorProxy,
  FINVector          = FINVector,
  FINRotator         = FINRotator,
  Inventory          = Inventory,
}
