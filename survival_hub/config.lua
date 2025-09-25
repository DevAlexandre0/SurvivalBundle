-- FILE: survival_hub/config.lua
Config = {}

-- Qbox-only
Config.Debug = true
Config.LogPrefix = '[survival_hub:qbox]'
Config.BroadcastEnabled = true

-- namespace
Config.Namespaces = { 'movement', 'needs', 'health', 'bio', 'env' }

-- Clamp
Config.Clamps = {
  movement = { stamina={0,100}, oxygen={0,100} },
  needs    = { food={0,100}, water={0,100}, energy={0,100}, stress={0,100}, poop={0,100}, pee={0,100}, stamina={0,100}, oxygen={0,100} },
  health   = { hp={0,100}, blood={0,100}, bleeding={0,100}, fracture={0,1}, pain={0,100} },
  bio      = { infection={0,100}, parasite={0,100}, disease={0,100}, immunity={0,100}, metabolism={0,100}, stomach={0,100} },
  env      = { temp_body={30,43}, temp_env={-20,60}, wet={0,100}, rad={0,100} }
}

-- Rate limit / namespace
Config.Rate = {
  windowMs = 1000,
  maxMsgs = 20,
  maxPayloadBytes = 2048
}

-- Persistence (citizenid for key)
Config.Persistence = {
  table = 'survival_states',
  flushIntervalSec = 30
}
