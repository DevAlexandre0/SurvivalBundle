Config = {}

Config.Debug = true
Config.LogPrefix = '[survival_hub]'
Config.BroadcastEnabled = true

Config.FrameworkPriority = { 'qbox', 'qb', 'esx', 'standalone' }
Config.AdapterPermissions = {
    admin = { 'ace:survival.hub' }
}
Config.Namespaces = { 'movement', 'needs', 'health', 'bio', 'env' }

Config.Clamps = {
    movement = { stamina = {0, 100}, oxygen = {0, 100}, speed = {0, 150} },
    needs = {
        food = {0, 100}, water = {0, 100}, energy = {0, 100}, stress = {0, 100},
        poop = {0, 100}, pee = {0, 100}
    },
    health = {
        hp = {0, 100}, blood = {0, 100}, bleed = {0, 3}, fracture = {0, 1},
        pain = {0, 100}, trauma = {0, 100}
    },
    bio = {
        infection = {0, 100}, parasite = {0, 100}, disease = {0, 100},
        immunity = {0, 100}, metabolism = {0, 100}, stomach = {0, 100}
    },
    env = {
        temp_env = {-20, 60}, temp_body = {30, 43}, wetness = {0, 100},
        wind = {0, 100}, precip = {0, 100}, radiation = {0, 100}
    }
}

Config.Rate = {
    windowMs = 1000,
    maxMsgs = 20,
    maxPayloadBytes = 2048
}

Config.Persistence = {
    enabled = true,
    table = 'survival_states',
    flushIntervalSec = 30,
    fileFallbackPrefix = 'survival_state_'
}
