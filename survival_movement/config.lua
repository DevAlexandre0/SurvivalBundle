Config = {}

-- Ticks and thresholds
Config.TickMs = 750                 -- client poll period
Config.ReportThreshold = 2.5        -- % change to report
Config.MaxEventsPerMinute = 6

-- Oxygen model
Config.MaxUnderwaterSeconds = 10.0  -- baseline vanilla (approx)
Config.OxygenWarnPercent = 20.0

-- Stamina model
Config.IdleRegenPerTick = 0.0       -- server may push regen; keep 0 for headless base
Config.SprintDrainHint = 0.0        -- informational only; drain is handled by game

-- Security/anti-cheat
Config.MaxRisePerTick = 12.0        -- % per tick
Config.DropPacketsOnThrottle = true

-- Logging
Config.Debug = true

-- Adapter selection is automatic; you can force one:
-- Config.Adapter = 'auto' | 'standalone' | 'esx' | 'qb' | 'ox'
Config.Adapter = 'auto'
