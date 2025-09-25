local state, lastTs, evCount, windowStart = {}, {}, {}, {}
local saveDebounce = {}
local SAVE_MIN_INTERVAL = 10000

local function dbg(...) if Config.Debug then print('[movement:server]', ...) end end
local function clamp(v, a, b) return math.max(a, math.min(b, v)) end

-- Identifier resolver: Qbox -> QBCore -> license
local function resolveIdentifier(src)
  -- Qbox
  if GetResourceState('qbx_core') == 'started' then
    local ply = exports.qbx_core and exports.qbx_core:GetPlayer(src)
    if ply and ply.PlayerData and ply.PlayerData.citizenid then
      return ('qb:%s'):format(ply.PlayerData.citizenid)
    end
    -- บางรุ่นของ qbx_core ให้ใช้ exports['qbx_core']:GetPlayer
    if exports['qbx_core'] and exports['qbx_core'].GetPlayer then
      local p2 = exports['qbx_core']:GetPlayer(src)
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
  local lic = GetPlayerIdentifierByType(src, 'license') or ('temp:%d'):format(src)
  return ('cfx:%s'):format(lic)
end

-- DB helpers
local function dbLoad(identifier)
  local row = MySQL.single.await('SELECT stamina,oxygen,sprinting,underwater FROM survival_movement WHERE identifier = ?', { identifier })
  return row
end

local function dbSave(identifier, rec)
  local now = GetGameTimer()
  if saveDebounce[identifier] and now - saveDebounce[identifier] < SAVE_MIN_INTERVAL then return end
  saveDebounce[identifier] = now
  MySQL.prepare('INSERT INTO survival_movement (identifier, stamina, oxygen, sprinting, underwater) VALUES (?, ?, ?, ?, ?) ON DUPLICATE KEY UPDATE stamina=?, oxygen=?, sprinting=?, underwater=?', {
    identifier, rec.stamina or 100.0, rec.oxygen or 100.0, rec.sprinting and 1 or 0, rec.underwater and 1 or 0,
    rec.stamina or 100.0, rec.oxygen or 100.0, rec.sprinting and 1 or 0, rec.underwater and 1 or 0
  })
end

-- Export: read server-authoritative state
exports('GetMovementState', function(src) return state[src] end)

-- Regen policy hook
local regenPolicy = 'none'
exports('SetRegenRule', function(name) regenPolicy = name or 'none'; dbg('regen policy', regenPolicy) end)

-- Load snapshot on first contact
local function ensureSnapshot(src)
  if state[src] then return end
  local id = resolveIdentifier(src)
  local row = dbLoad(id)
  if row then
    state[src] = {
      stamina = clamp(tonumber(row.stamina) or 100.0, 0.0, 100.0),
      oxygen = clamp(tonumber(row.oxygen) or 100.0, 0.0, 100.0),
      sprinting = (row.sprinting == 1),
      underwater = (row.underwater == 1),
      ts = GetGameTimer()
    }
    local ply = Player(src)
    if ply and ply.state then ply.state:set('movement', state[src], true) end
    dbg(('loaded snapshot src=%d id=%s s=%.1f o=%.1f'):format(src, id, state[src].stamina, state[src].oxygen))
  else
    state[src] = { stamina = 100.0, oxygen = 100.0, sprinting = false, underwater = false, ts = GetGameTimer() }
  end
end

-- Cleanup + final save
AddEventHandler('playerDropped', function()
  local src = source
  local rec = state[src]
  if rec then
    local id = resolveIdentifier(src)
    dbSave(id, rec)
  end
  state[src], lastTs[src], evCount[src], windowStart[src] = nil, nil, nil, nil
end)

-- Probe on player load
RegisterNetEvent('survival:movement:probe', function()
  ensureSnapshot(source)
end)

-- Main update
RegisterNetEvent('survival:movement:update', function(data)
  local src = source
  ensureSnapshot(src)
  if type(data) ~= 'table' then return end

  local now = GetGameTimer()
  windowStart[src] = windowStart[src] or now
  evCount[src] = evCount[src] or 0
  if now - windowStart[src] > 60000 then windowStart[src], evCount[src] = now, 0 end
  evCount[src] = evCount[src] + 1
  if evCount[src] > Config.MaxEventsPerMinute then
    if Config.Debug then dbg(('drop: rate limit src=%d'):format(src)) end
    if Config.DropPacketsOnThrottle then return end
  end

  local prev = state[src]
  if prev and data.ts and lastTs[src] and data.ts < lastTs[src] then
    if Config.Debug then dbg(('drop: ts rollback src=%d'):format(src)) end
    return
  end
  lastTs[src] = data.ts or now

  local s = clamp(tonumber(data.stamina or 0.0) or 0.0, 0.0, 100.0)
  local o = clamp(tonumber(data.oxygen  or 0.0) or 0.0, 0.0, 100.0)
  if prev then
    if (s - prev.stamina) > Config.MaxRisePerTick or (o - prev.oxygen) > Config.MaxRisePerTick then
      if Config.Debug then dbg(('cap: delta too high src=%d'):format(src)) end
      s = math.min(prev.stamina + Config.MaxRisePerTick, 100.0)
      o = math.min(prev.oxygen + Config.MaxRisePerTick, 100.0)
    end
  end

  local rec = {
    stamina = s, oxygen = o,
    sprinting = data.sprinting and true or false,
    underwater = data.underwater and true or false,
    ts = lastTs[src]
  }
  state[src] = rec

  local ply = Player(src)
  if ply and ply.state then ply.state:set('movement', rec, true) end
  TriggerClientEvent('survival:movement:broadcast', -1, src, rec)

  local id = resolveIdentifier(src)
  dbSave(id, rec)

  if regenPolicy == 'idle' and not rec.sprinting and not rec.underwater then
    TriggerClientEvent('survival:movement:apply', src, { staminaRegen = 0.05 })
  end

  if Config.Debug then dbg(('ok src=%d s=%.1f o=%.1f sprint=%s under=%s'):format(src, rec.stamina, rec.oxygen, rec.sprinting, rec.underwater)) end
end)
