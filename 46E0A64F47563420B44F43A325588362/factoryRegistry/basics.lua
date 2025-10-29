---@diagnostic disable: lowercase-global

--------------------------------------------------------------------------------
-- Netzwerk-Konstanten / Kommandos
-- (Nur Doku/Typisierung – keine Laufzeitänderung)
--------------------------------------------------------------------------------


---@type NetPort
NET_PORT_FACTORY_REGISTRY                                    = 11

---@type NetName
NET_NAME_FACTORY_REGISTRY_CLIENT                             = "FactoryRegistryClient"
---@type NetName
NET_NAME_FACTORY_REGISTRY_SERVER                             = "FactoryRegistryServer"

---@type NetCommand
NET_CMD_FACTORY_REGISTRY_REGISTER_FACTORY                    = "FactoryRegistry.registerFactory"
---@type NetCommand
NET_CMD_FACTORY_REGISTRY_REGISTER_FACTORY_ACK                = "FactoryRegistry.registerFactoryAck"
---@type NetCommand
NET_CMD_FACTORY_REGISTRY_REQUEST_FACTORY_UPDATE              = "FactoryRegistry.requestFactoryUpdate"
---@type NetCommand
NET_CMD_FACTORY_REGISTRY_RESPONSE_FACTORY_UPDATE             = "FactoryRegistry.responseFactoryUpdate"
---@type NetCommand
NET_CMD_FACTORY_REGISTRY_RESET_FACTORYREGISTRY               = "FactoryRegistry.resetFactoryRegistry"
---@type NetCommand
NET_CMD_FACTORY_REGISTRY_SHUT_DOWN_DUBLICATE_FACTORYREGISTRY = "FactoryRegistry.shutDownDublicate"
---@type NetCommand
NET_CMD_FACTORY_REGISTRY_REQUEST_FACTORY_ADDRESS             = "FactoryRegistry.requestFactoryAddress"
---@type NetCommand
NET_CMD_FACTORY_REGISTRY_RESPONSE_FACTORY_ADDRESS            = "FactoryRegistry.responseFactoryAddress"
---@type NetCommand
NET_CMD_FACTORY_REGISTRY_RESPONSE_FACTORY_ADDRESS_NO_FACTORY = "FactoryRegistry.responseFactoryAddressNoFactory"
