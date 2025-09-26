local Adapter = SurvivalFramework.buildAdapter({
  priority = Config.Framework and Config.Framework.priority,
  permissions = Config.Framework and Config.Framework.permissions
})

local state, lastTs, evCount, windowStart = {}, {}, {}, {}
local saveDebounce = {}
local SAVE_MIN_INTERVAL = 10000
local hasOx = GetResourceState and GetResourceState('oxmysql') == 'started' and MySQL ~= nil

local function dbg(fmt, ...)
  if not Config.Debug then return end
  if select('#', ...) > 0 then
    print(('[movement:server] ' .. fmt):format(...))
  else
    print('[movement:server] ' .. tostring(fmt))
  end
end

local function clamp(v, a, b)
  return math.max(a, math.min(b, v))
end

local function validSource(src)
  return type(src) == 'number' and src > 0
end

local function resolveIdentifier(src)
  return Adapter.getIdentifier(src) or ('license:%s'):format(GetPlayerIdentifierByType(src, 'license') or tostring(src))
end

local function dbEnsure()
  if not hasOx then return end
  if state._schemaReady then return end
  MySQL.query.await([[CREATE TABLE IF NOT EXISTS survival_movement (
      identifier VARCHAR(128) NOT NULL PRIMARY KEY,
      stamina FLOAT NOT NULL,
      oxygen FLOAT NOT NULL,
      sprinting TINYINT(1) NOT NULL DEFAULT 0,
      underwater TINYINT(1) NOT NULL DEFAULT 0,
      updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;]])
  state._schemaReady = true
end

local function dbLoad(identifier)
  if not hasOx then return nil end
  dbEnsure()
  return MySQL.single.await('SELECT stamina, oxygen, sprinting, underwater FROM survival_movement WHERE identifier = ?', { identifier })
end

local function dbSave(identifier, rec)
  if not hasOx then return end
  dbEnsure()
  local now = GetGameTimer()
  if saveDebounce[identifier] and now - saveDebounce[identifier] < SAVE_MIN_INTERVAL then return end
  saveDebounce[identifier] = now
  MySQL.prepare.await('INSERT INTO survival_movement (identifier, stamina, oxygen, sprinting, underwater) VALUES (?, ?, ?, ?, ?) ON DUPLICATE KEY UPDATE stamina=VALUES(stamina), oxygen=VALUES(oxygen), sprinting=VALUES(sprinting), underwater=VALUES(underwater)', {
    identifier,
    rec.stamina or 100.0,
    rec.oxygen or 100.0,
    rec.sprinting and 1 or 0,
    rec.underwater and 1 or 0
  })
end

local function ensureSnapshot(src)
  if state[src] then return state[src] end
  local id = resolveIdentifier(src)
  local row = dbLoad(id)
  if row then
    state[src] = {
      stamina = clamp(tonumber(row.stamina) or 100.0, 0.0, 100.0),
      oxygen = clamp(tonumber(row.oxygen) or 100.0, 0.0, 100.0),
      sprinting = row.sprinting == 1,
      underwater = row.underwater == 1,
      ts = GetGameTimer()
    }
  else
    state[src] = { stamina = 100.0, oxygen = 100.0, sprinting = false, underwater = false, ts = GetGameTimer() }
  end
  local ply = Player(src)
  if ply and ply.state then
    ply.state:set('movement', state[src], true)
  end
  dbg('loaded movement src=%d id=%s', src, id)
  return state[src]
end

local function cleanup(src)
  if not state[src] then return end
  local id = resolveIdentifier(src)
  dbSave(id, state[src])
  state[src], lastTs[src], evCount[src], windowStart[src] = nil, nil, nil, nil
end

Adapter.onPlayerLoaded(function(src)
  if validSource(src) then
    ensureSnapshot(src)
  end
end)

AddEventHandler('playerJoining', function(src)
  if validSource(src) then
    ensureSnapshot(src)
  end
end)

Adapter.onPlayerDropped(function(src)
  if validSource(src) then
    cleanup(src)
  end
end)

AddEventHandler('playerDropped', function()
  cleanup(source)
end)

RegisterNetEvent('survival:movement:probe', function()
  local src = source
  if not validSource(src) then return end
  ensureSnapshot(src)
end)

RegisterNetEvent('survival:movement:update', function(data)
  local src = source
  if not validSource(src) then return end
  if type(data) ~= 'table' then return end

  local rec = ensureSnapshot(src)

  local now = GetGameTimer()
  windowStart[src] = windowStart[src] or now
  evCount[src] = evCount[src] or 0
  if now - windowStart[src] > 60000 then
    windowStart[src], evCount[src] = now, 0
  end
  evCount[src] = evCount[src] + 1
  if evCount[src] > (Config.MaxEventsPerMinute or 6) then
    dbg('rate limit movement src=%d', src)
    if Config.DropPacketsOnThrottle then return end
  end

  if data.ts and lastTs[src] and data.ts < lastTs[src] then
    dbg('rollback ts src=%d', src)
    return
  end
  lastTs[src] = data.ts or now

  local s = clamp(tonumber(data.stamina or rec.stamina) or rec.stamina, 0.0, 100.0)
  local o = clamp(tonumber(data.oxygen or rec.oxygen) or rec.oxygen, 0.0, 100.0)
  if s - rec.stamina > Config.MaxRisePerTick then
    s = math.min(rec.stamina + Config.MaxRisePerTick, 100.0)
  end
  if o - rec.oxygen > Config.MaxRisePerTick then
    o = math.min(rec.oxygen + Config.MaxRisePerTick, 100.0)
  end

  rec.stamina = s
  rec.oxygen = o
  rec.sprinting = data.sprinting and true or false
  rec.underwater = data.underwater and true or false
  rec.ts = lastTs[src]

  local ply = Player(src)
  if ply and ply.state then
    ply.state:set('movement', rec, true)
  end

  TriggerClientEvent('survival:movement:broadcast', -1, src, rec)
  dbSave(resolveIdentifier(src), rec)

  if Config.IdleRegenPerTick > 0 and not rec.sprinting and not rec.underwater then
    TriggerClientEvent('survival:movement:apply', src, { staminaRegen = Config.IdleRegenPerTick })
  end

  dbg('movement update src=%d stamina=%.1f oxygen=%.1f sprint=%s underwater=%s', src, rec.stamina, rec.oxygen, tostring(rec.sprinting), tostring(rec.underwater))
end)

exports('GetMovementState', function(src)
  if not validSource(src) then return nil end
  return state[src]
end)

AddEventHandler('onResourceStart', function(res)
  if res ~= GetCurrentResourceName() then return end
  if hasOx then dbEnsure() end
  dbg('movement adapter=%s oxmysql=%s', Adapter.name or 'unknown', tostring(hasOx))
end)
