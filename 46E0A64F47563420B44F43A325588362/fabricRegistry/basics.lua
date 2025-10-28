---@diagnostic disable: lowercase-global

--------------------------------------------------------------------------------
-- Netzwerk-Konstanten / Kommandos
-- (Nur Doku/Typisierung – keine Laufzeitänderung)
--------------------------------------------------------------------------------


---@type NetPort
NET_PORT_FABRIC_REGISTRY          = 11

---@type NetName
NET_NAME_FABRIC_REGISTRY_CLIENT   = "FabricRegistryClient"
---@type NetName
NET_NAME_FABRIC_REGISTRY_SERVER   = "FabricRegistryServer"

---@type NetCommand
NET_CMD_FABRIC_REGISTER           = "FabricRegistry.registerFabric"
---@type NetCommand
NET_CMD_FABRIC_REGISTER_ACK       = "FabricRegistry.registerFabricAck"
---@type NetCommand
NET_CMD_CALL_FABRICS_FOR_UPDATES  = "FabricRegistry.callFabricsForUpdates"
---@type NetCommand
NET_CMD_UPDATE_FABRIC_IN_REGISTRY = "FabricRegistry.updateFabricInRegistry"
---@type NetCommand
NET_CMD_RESET_FABRICREGISTRY      = "FabricRegistry.resetFabricRegistry"
---@type NetCommand
NET_CMD_GET_FABRIC_FROM_REGISTRY  = "FabricRegistry.getFabricFromRegistry"
---@type NetCommand
NET_CMD_SET_FABRIC_FROM_REGISTRY  = "FabricRegistry.setFabricFromRegistry"
