Config = {}

-- tick + networking
Config.ClientSampleMs = 350         -- client read hp/bone
Config.ServerTickMs   = 1000        -- bleed simulation tick
Config.DeltaThreshold = 1.5         -- % change before sending
Config.RateLimitPerMin = 60         -- max client->server updates

-- normalization
Config.MaxHP = 200                  -- GTA V default ped max (adjust per framework if changed)
Config.InitBlood = 100.0            -- normalized blood pool 0..100

-- bleed tiers (hp/sec and blood/sec in normalized units)
Config.BleedTiers = {
  [0] = { hp = 0.0,  blood = 0.0 },
  [1] = { hp = 0.05, blood = 0.25 },
  [2] = { hp = 0.12, blood = 0.60 },
  [3] = { hp = 0.25, blood = 1.20 }
}

-- fracture chance by bone group (0..1)
Config.FractureChance = { head=0.00, torso=0.02, arm=0.18, leg=0.35 }

-- classification weights by weapon type
Config.WeaponBleedMap = {
  melee   = 1,      -- tier 1 baseline
  bullet  = 2,      -- tier 2
  shotgun = 3,      -- tier 3
  blade   = 2,
  fall    = 1,
  blast   = 3
}

-- safety bounds
Config.MaxHpGainPerTick = 5.0       -- prevent illegal healing bursts
Config.MaxBleedTier     = 3

-- logging
Config.Debug = false
