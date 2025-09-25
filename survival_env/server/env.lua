local rateWindow = {}
local cache = {}
local hasOx = GetResourceState('oxmysql') ~= 'missing' and GetResourceState('oxmysql') ~= 'stopped'

local function dbg(...)
  if Config.Debug then
    print(("%s[server] " .. string.rep("%s ", select('#', ...))):format(Config.LogPrefix, ...))
  end
end

-- Qbox-first identifier
local function getIdentifier(src)
  -- Qbox
  if GetResourceState('qbx_core') == 'started' then
    local ex = exports['qbx_core']
    if ex and ex.GetPlayer then
      local p = ex:GetPlayer(src)
      if p and p.PlayerData and p.PlayerData.citizenid then
        return ('qb:%s'):format(p.PlayerData.citizenid)
      end
    end
    if exports.qbx_core and exports.qbx_core.GetPlayer then
      local p2 = exports.qbx_core:GetPlayer(src)
      if p2 and p2.PlayerData and p2.PlayerData.citizenid then
        return ('qb:%s'):format(p2.PlayerData.citizenid)
      end
    end
  end

  -- QBCore fallback
  if GetResourceState('qb-core') == 'started' then
    local QBCore = exports['qb-core']:GetCoreObject()
    local Player = QBCore and QBCore.Functions and QBCore.Functions.GetPlayer(src)
    if Player and Player.PlayerData and Player.PlayerData.citizenid then
      return ('qb:%s'):format(Player.PlayerData.citizenid)
    end
  end

  -- License fallback
  local lic = GetPlayerIdentifierByType(src, 'license')
  return lic and ('lic:%s'):format(lic) or ('src:%d'):format(src)
end

-- === Persistence and runtime remain the same ===
local function dbEnsure()
  if Config.Persistence ~= 'oxmysql' or not hasOx then return end
  MySQL.query([[
    CREATE TABLE IF NOT EXISTS survival_env (
      id INT AUTO_INCREMENT PRIMARY KEY,
      identifier VARCHAR(128) NOT NULL,
      env_json TEXT NOT NULL,
      updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
      UNIQUE KEY uniq_identifier (identifier)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
  ]])
end

local function dbLoad(id)
  if Config.Persistence ~= 'oxmysql' or not hasOx then return nil end
  local row = MySQL.single.await('SELECT env_json FROM survival_env WHERE identifier = ?', { id })
  if row and row.env_json then
    local ok, data = pcall(json.decode, row.env_json)
    if ok then return data end
  end
  return nil
end

local function dbSave(id, data)
  if Config.Persistence ~= 'oxmysql' or not hasOx then return end
  MySQL.update.await(
    'INSERT INTO survival_env (identifier, env_json) VALUES (?, ?) ON DUPLICATE KEY UPDATE env_json = VALUES(env_json)',
    { id, json.encode(data) }
  )
end

AddEventHandler('onResourceStart', function(res)
  if res ~= GetCurrentResourceName() then return end
  dbEnsure()
  dbg('started, persistence=%s, oxmysql=%s', Config.Persistence, tostring(hasOx))
end)

AddEventHandler('playerJoining', function(src)
  local id = getIdentifier(src)
  local loaded = dbLoad(id)
  cache[src] = loaded or {
    temp_env = 50.0, temp_body = 50.0, wetness = 0.0, wind = 0.0, precip = 0.0, radiation = 0.0, ts = os.time()
  }
  local ply = Player(src)
  if ply and ply.state then ply.state:set('env', cache[src], true) end
  dbg('join cache init for %s', id)
end)

AddEventHandler('playerDropped', function(_, src)
  local id = getIdentifier(src)
  if cache[src] then dbSave(id, cache[src]) end
  cache[src] = nil
  rateWindow[src] = nil
end)

local function rateOK(src)
  local now = GetGameTimer()
  rateWindow[src] = rateWindow[src] or {}
  for i = #rateWindow[src], 1, -1 do
    if now - rateWindow[src][i] > 60000 then table.remove(rateWindow[src], i) end
  end
  if #rateWindow[src] >= Config.RateLimitPerMin then return false end
  table.insert(rateWindow[src], now)
  return true
end

local function clamp01(x) return math.max(0.0, math.min(100.0, x)) end

local function derive(src, raw)
  local N = Config.Norm
  local dayBlend = (raw.hour >= 6 and raw.hour < 18) and 1.0 or 0.0
  local base = N.BaseNightTemp + (N.BaseDayTemp - N.BaseNightTemp) * dayBlend

  local precip = math.max(raw.rain or 0.0, raw.snow or 0.0) * 100.0
  local wind = (raw.wind or 0.0) * N.WindFactor

  local temp_env = base
  temp_env = temp_env - (raw.snow or 0.0) * N.SnowFactor
  temp_env = temp_env - wind
  temp_env = clamp01(temp_env)

  local wetness = cache[src] and cache[src].wetness or 0.0
  wetness = wetness + (raw.rain or 0.0) * N.RainToWetness
  wetness = wetness + (raw.subm or 0.0) * N.SubmergeToWet
  if (raw.rain or 0.0) < 0.05 and (raw.subm or 0.0) < 0.05 and (raw.spd or 0.0) < 1.0 then
    wetness = wetness - N.WetnessDryRate
  end
  wetness = clamp01(wetness)

  local temp_body = temp_env * N.BodyFromEnvK - wetness * N.BodyWetPenalty + (raw.spd or 0.0) * N.SpeedWarmGain
  temp_body = clamp01(temp_body)

  local rad = 0.0
  local ped = GetPlayerPed(src)
  local px,py,pz = table.unpack(GetEntityCoords(ped))
  for _, z in ipairs(Config.RadiationZones) do
    local c, r, inten = z[1], z[2], z[3]
    local dx,dy,dz = (px - c.x), (py - c.y), (pz - c.z)
    local dist = math.sqrt(dx*dx + dy*dy + dz*dz)
    if dist <= r then
      local falloff = 1.0 - (dist / r)
      rad = math.max(rad, inten * falloff)
    end
  end
  rad = clamp01(rad)

  return {
    temp_env = temp_env,
    temp_body = temp_body,
    wetness   = wetness,
    wind      = clamp01((raw.wind or 0.0) * 10.0),
    precip    = clamp01(precip),
    radiation = rad,
    ts        = os.time()
  }
end

RegisterNetEvent('survival:env:update', function(raw)
  local src = source
  if type(raw) ~= 'table' then return end
  if not rateOK(src) then dbg('rate limit %d', src); return end

  raw.rain = math.max(0.0, math.min(1.0, tonumber(raw.rain or 0.0)))
  raw.snow = math.max(0.0, math.min(1.0, tonumber(raw.snow or 0.0)))
  raw.wind = math.max(0.0, math.min(50.0, tonumber(raw.wind or 0.0)))
  raw.subm = math.max(0.0, math.min(1.0, tonumber(raw.subm or 0.0)))
  raw.spd  = math.max(0.0, math.min(50.0, tonumber(raw.spd  or 0.0)))
  raw.hour = math.floor(tonumber(raw.hour or 0) % 24)

  local derived = derive(src, raw)
  cache[src] = derived

  local ply = Player(src)
  if ply and ply.state then ply.state:set('env', derived, true) end

  if (derived.ts % 10) == 0 then
    dbSave(getIdentifier(src), derived)
  end
end)

exports('GetEnvState', function(target)
  target = target or source
  return cache[target]
end)

RegisterCommand('env.debug', function(src)
  local st = cache[src]
  if st then
    dbg(('p%d env: te=%.1f tb=%.1f wet=%.1f wind=%.1f pr=%.1f rad=%.1f'):format(
      src, st.temp_env, st.temp_body, st.wetness, st.wind, st.precip, st.radiation))
  else
    dbg('no env cache for '..tostring(src))
  end
end, false)
