Config = {}

-- Sampling & sync
Config.ClientSampleMs = 1000
Config.DeltaEpsilon   = 2.0  -- % change to trigger sync
Config.RateLimitPerMin = 30  -- server updates per player per minute

-- Weights / normalization (0..100 outputs)
Config.Norm = {
  RainToWetness   = 60.0,    -- rain 0..1 -> +wetness per tick %
  SubmergeToWet   = 80.0,    -- submerged 0..1 -> +wetness per tick %
  WetnessDryRate  = 6.0,     -- -wetness per tick when dry and moving slow
  WindFactor      = 0.6,     -- wind m/s -> temp_env decrease scaler
  SnowFactor      = 40.0,    -- snow 0..1 -> temp_env decrease scaler
  BaseDayTemp     = 60.0,    -- day baseline (0..100)
  BaseNightTemp   = 40.0,    -- night baseline (0..100)
  BodyFromEnvK    = 0.65,    -- temp_body follows env
  BodyWetPenalty  = 0.35,    -- additional drop from wetness
  SpeedWarmGain   = 8.0      -- movement warms body
}

-- Radiation zones (designer-authored)
-- center, radius, intensity 0..100
Config.RadiationZones = {
  -- { vec3(x,y,z), radius, intensity }
  -- example: { vec3(3512.7, 3669.8, 34.0), 120.0, 45.0 },
}

-- Persistence provider: 'oxmysql' or 'memory'
Config.Persistence = 'oxmysql'

-- Logging
Config.Debug = true
Config.LogPrefix = '[survival_env] '

Config.Framework = { 'qb' }
