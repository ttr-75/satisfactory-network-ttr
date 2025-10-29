---@diagnostic disable: lowercase-global

--------------------------------------------------------------------------------
-- Netzwerk-Konstanten / Kommandos
-- (Nur Doku/Typisierung – keine Laufzeitänderung)
--------------------------------------------------------------------------------


---@type NetPort
NET_PORT_FACTORY_REGISTRY                   = 11

---@type NetName
NET_NAME_FACTORY_REGISTRY_CLIENT            = "FactoryRegistryClient"
---@type NetName
NET_NAME_FACTORY_REGISTRY_SERVER            = "FactoryRegistryServer"

---@type NetCommand
NET_CMD_FACTORY_REGISTER                    = "FactoryRegistry.registerFactory"
---@type NetCommand
NET_CMD_FACTORY_REGISTER_ACK                = "FactoryRegistry.registerFactoryAck"
---@type NetCommand
NET_CMD_CALL_FACTORYS_FOR_UPDATES           = "FactoryRegistry.callFactorysForUpdates"
---@type NetCommand
NET_CMD_UPDATE_FACTORY_IN_REGISTRY          = "FactoryRegistry.updateFactoryInRegistry"
---@type NetCommand
NET_CMD_RESET_FACTORYREGISTRY               = "FactoryRegistry.resetFactoryRegistry"
---@type NetCommand
NET_CMD_GET_FACTORY_FROM_REGISTRY           = "FactoryRegistry.getFactoryFromRegistry"
---@type NetCommand
NET_CMD_SET_FACTORY_FROM_REGISTRY           = "FactoryRegistry.setFactoryFromRegistry"
---@type NetCommand
NET_CMD_SHUT_DOWN_DUBLICATE_FACTORYREGISTRY = "FactoryRegistry.shutDownDublicate"
