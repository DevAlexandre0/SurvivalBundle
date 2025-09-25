Config = {}

-- Debug
Config.Debug = true
Config.DebugPrefix = '[BIO]'

-- Ticks
Config.ServerTickMs = 1000
Config.Broadcast = false
Config.DeltaEpsilon = 0.01

-- Normalization
Config.Scale = { min = 0.0, max = 100.0 }

-- Coefficients
Config.Coeff = {
    infectionBase = 0.02,
    parasiteBase  = 0.015,
    diseaseProg   = 0.01,
    immunityGain  = 0.005,
    immunityLoss  = 0.006,
    metabolismBase= 1.0,
    stomachEmpty  = 2.0
}

-- Thresholds
Config.Threshold = {
    InfectionStart = 5.0,
    Symptomatic    = 35.0,
    Critical       = 80.0,
    VomitStomach   = 90.0
}

-- Persistence (optional)
Config.Persistence = {
    enabled = true,             -- set true to enable ox_mysql persistence
    table   = 'survival_bio',
    saveIntervalSec = 60
}

Config.Adapter = 'qb'
