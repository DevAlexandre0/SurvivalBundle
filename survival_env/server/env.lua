local Adapter = SurvivalFramework.buildAdapter({
  priority = Config.Framework and Config.Framework.priority,
  permissions = Config.Framework and Config.Framework.permissions
})

local rateWindow = {}
local cache = {}
local hasOx = GetResourceState and GetResourceState('oxmysql') == 'started' and MySQL ~= nil

local function dbg(fmt, ...)
  if not Config.Debug then return end
  if select('#', ...) > 0 then
    print((Config.LogPrefix or '[survival_env]') .. (fmt:format(...)))
  else
    print((Config.LogPrefix or '[survival_env]') .. tostring(fmt))
  end
end

local function rateOK(src)
  local now = GetGameTimer()
  rateWindow[src] = rateWindow[src] or {}
  local bucket = rateWindow[src]
  bucket[#bucket+1] = now
  local limit = Config.RateLimitPerMin or 30
  for i = #bucket, 1, -1 do
    if now - bucket[i] > 60000 then table.remove(bucket, i) end
  end
  if #bucket > limit then return false end
  return true
end

local function clampRange(v, min, max)
  v = tonumber(v) or 0.0
  if v < min then return min end
  if v > max then return max end
  return v
end

local function ensureSchema()
  if Config.Persistence ~= 'oxmysql' or not hasOx then return end
  MySQL.query.await([[CREATE TABLE IF NOT EXISTS survival_env (
      identifier VARCHAR(128) NOT NULL PRIMARY KEY,
      env_json JSON NOT NULL,
      updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;]])
end

local function dbLoad(identifier)
  if Config.Persistence ~= 'oxmysql' or not hasOx then return nil end
  local row = MySQL.single.await('SELECT env_json FROM survival_env WHERE identifier = ?', { identifier })
  if row and row.env_json then
    local ok, payload = pcall(json.decode, row.env_json)
    if ok then return payload end
  end
  return nil
end

local function dbSave(identifier, data)
  if Config.Persistence ~= 'oxmysql' or not hasOx then return end
  MySQL.prepare.await('INSERT INTO survival_env (identifier, env_json) VALUES (?, ?) ON DUPLICATE KEY UPDATE env_json = VALUES(env_json)', {
    identifier,
    json.encode(data)
  })
end

local function derive(src, raw)
  local N = Config.Norm
  local dayBlend = (raw.hour >= 6 and raw.hour < 18) and 1.0 or 0.0
  local base = N.BaseNightTemp + (N.BaseDayTemp - N.BaseNightTemp) * dayBlend
  local precip = math.max(raw.rain, raw.snow)
  local wind = raw.wind * N.WindFactor

  local temp_env = base - raw.snow * N.SnowFactor - wind
  local wetness = cache[src] and cache[src].wetness or 0.0
  wetness = wetness + raw.rain * N.RainToWetness
  wetness = wetness + raw.subm * N.SubmergeToWet
  if raw.rain < 0.05 and raw.subm < 0.05 and raw.spd < 1.0 then
    wetness = wetness - N.WetnessDryRate
  end
  wetness = math.max(0.0, math.min(100.0, wetness))

  local temp_body = temp_env * N.BodyFromEnvK - wetness * N.BodyWetPenalty + raw.spd * N.SpeedWarmGain

  local rad = 0.0
  local ped = GetPlayerPed(src)
  if ped ~= 0 then
    local px, py, pz = table.unpack(GetEntityCoords(ped))
    for _, zone in ipairs(Config.RadiationZones or {}) do
      local center, radius, intensity = zone[1], zone[2], zone[3]
      local dx, dy, dz = px - center.x, py - center.y, pz - center.z
      local dist = math.sqrt(dx*dx + dy*dy + dz*dz)
      if dist <= radius then
        local falloff = 1.0 - (dist / radius)
        rad = math.max(rad, intensity * falloff)
      end
    end
  end

  return {
    temp_env = clampRange(temp_env, -20.0, 100.0),
    temp_body = clampRange(temp_body, -20.0, 100.0),
    wetness = clampRange(wetness, 0.0, 100.0),
    wind = clampRange(raw.wind * 10.0, 0.0, 100.0),
    precip = clampRange(precip * 100.0, 0.0, 100.0),
    radiation = clampRange(rad, 0.0, 100.0),
    ts = os.time()
  }
end

local function pushState(src, data)
  cache[src] = data
  local ply = Player(src)
  if ply and ply.state then
    ply.state:set('env', data, true)
  end
end

local function handleJoin(src)
  if type(src) ~= 'number' or src <= 0 then return end
  local identifier = Adapter.getIdentifier(src)
  local snapshot = identifier and dbLoad(identifier) or nil
  if snapshot then
    cache[src] = snapshot
    pushState(src, snapshot)
  else
    cache[src] = {
      temp_env = 50.0,
      temp_body = 50.0,
      wetness = 0.0,
      wind = 0.0,
      precip = 0.0,
      radiation = 0.0,
      ts = os.time()
    }
    pushState(src, cache[src])
  end
  dbg('initialised env state src=%d id=%s', src, tostring(identifier))
end

Adapter.onPlayerLoaded(handleJoin)
AddEventHandler('playerJoining', function(src)
  handleJoin(src)
end)

local function handleDrop(src)
  if type(src) ~= 'number' or src <= 0 then return end
  local identifier = Adapter.getIdentifier(src)
  if identifier and cache[src] then
    dbSave(identifier, cache[src])
  end
  cache[src] = nil
  rateWindow[src] = nil
end

Adapter.onPlayerDropped(handleDrop)
AddEventHandler('playerDropped', function(reason)
  handleDrop(source)
end)

local function validSource(src)
  return type(src) == 'number' and src > 0
end

RegisterNetEvent('survival:env:update', function(raw)
  local src = source
  if not validSource(src) then return end
  if type(raw) ~= 'table' then return end
  if not rateOK(src) then
    dbg('rate limit drop src=%d', src)
    return
  end

  raw.rain = clampRange(raw.rain, 0.0, 1.0)
  raw.snow = clampRange(raw.snow, 0.0, 1.0)
  raw.wind = clampRange(raw.wind, 0.0, 60.0)
  raw.subm = clampRange(raw.subm, 0.0, 1.0)
  raw.spd  = clampRange(raw.spd, 0.0, 50.0)
  raw.hour = math.floor(clampRange(raw.hour or 0.0, 0.0, 23.0))

  local derived = derive(src, raw)
  pushState(src, derived)
  local identifier = Adapter.getIdentifier(src)
  if identifier then
    dbSave(identifier, derived)
  end
end)

exports('GetEnvState', function(target)
  if not validSource(target) then return nil end
  return cache[target]
end)

AddEventHandler('onResourceStart', function(res)
  if res ~= GetCurrentResourceName() then return end
  ensureSchema()
  dbg('started env adapter=%s hasOx=%s', Adapter.name or 'unknown', tostring(hasOx))
end)
