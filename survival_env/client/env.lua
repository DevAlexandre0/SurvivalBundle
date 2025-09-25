local last = { rain = -1, snow = -1, wind = -1, subm = -1, spd = -1, hour = -1 }
local lastSent = 0

local function dbg(...)
  if Config.Debug then
    print(("%s[client] " .. string.rep("%s ", select('#', ...))):format(Config.LogPrefix, ...))
  end
end

local function normalizeDelta(a,b)
  if a < 0 or b < 0 then return 100 end
  return math.abs(a - b)
end

CreateThread(function()
  Wait(1500)
  while true do
    local ped = PlayerPedId()
    local rain = GetRainLevel()                -- 0..1
    local snow = GetSnowLevel()                -- 0..1
    local wind = GetWindSpeed()                -- m/s
    local subm = GetEntitySubmergedLevel(ped)  -- 0..1
    local spd  = GetEntitySpeed(ped)           -- m/s
    local hour = GetClockHours()               -- 0..23

    -- coarse change detection
    local delta =
      normalizeDelta(rain, last.rain) +
      normalizeDelta(snow, last.snow) +
      normalizeDelta(wind, last.wind) +
      normalizeDelta(subm, last.subm) +
      normalizeDelta(spd,  last.spd)  +
      normalizeDelta(hour, last.hour)

    if delta >= Config.DeltaEpsilon then
      last = { rain = rain, snow = snow, wind = wind, subm = subm, spd = spd, hour = hour }
      local now = GetGameTimer()
      if now - lastSent >= 800 then
        lastSent = now
        TriggerServerEvent('survival:env:update', {
          rain = rain, snow = snow, wind = wind, subm = subm, spd = spd, hour = hour
        })
        dbg(('sent r%.2f s%.2f w%.2f u%.2f v%.2f h%d'):format(rain,snow,wind,subm,spd,hour))
      end
    end

    Wait(Config.ClientSampleMs)
  end
end)

-- Optional: local read access
exports('GetEnvRawSample', function()
  return last
end)
