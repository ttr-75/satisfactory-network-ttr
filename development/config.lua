local TTR_FIN_Config = {}

TTR_FIN_Config.language = "de"
TTR_FIN_Config.LOG_LEVEL = 1

TTR_FIN_Config.EVENT_LOOP_TIMEOUT = 0.5           -- in seconds
TTR_FIN_Config.FACTORY_SCREEN_UPDATE_INTERVAL = 2 -- in seconds

TTR_FIN_Config.RESTART_COMPUTERS_MIN = 30 -- in minutes must be >= 10
TTR_FIN_Config.RESTART_COMPUTERS_MAX = 60 -- in minutes must be >= RESTART_COMPUTERS_MIN + 5


_G.TTR_FIN_Config = TTR_FIN_Config



--return TTR_FIN_Config
