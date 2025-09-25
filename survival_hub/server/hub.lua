-- FILE: survival_hub/server/hub.lua
local function dbg(...)
  if Config.Debug then
    print(('[%s] %s'):format(GetCurrentResourceName(), table.concat({...}, ' ')))
  end
end

-- Qbox framework
local function qb() return exports.qbx_core end

local Framework = {
  name = 'qbox',
  getPlayer = function(src) return qb():GetPlayer(src) end,
  getIdentifier = function(src)
    local p = qb():GetPlayer(src)
    if p and p.PlayerData and p.PlayerData.citizenid then return p.PlayerData.citizenid end
    if p and p.citizenid then return p.citizenid end
    return tostring(src)
  end,
}

-- State cache
local SNAP, RATE, DIRTY = {}, {}, {}

-- Utils
local function clamp(v, mn, mx)
  if v == nil then return nil end
  if v < mn then return mn end
  if v > mx then return mx end
  return v
end

local function clampNamespace(ns, delta)
  local rules = Config.Clamps[ns]
  if not rules then return delta end
  local out = {}
  for k,v in pairs(delta) do
    local r = rules[k]
    if type(v) == 'number' and r then
      out[k] = clamp(v, r[1], r[2])
    else
      out[k] = v
    end
  end
  return out
end

local function mergeDelta(dst, src)
  for k,v in pairs(src) do
    if type(v) == 'table' and type(dst[k]) == 'table' then
      mergeDelta(dst[k], v)
    else
      dst[k] = v
    end
  end
end

local function ensurePlayerSnapshot(src)
  if not SNAP[src] then
    SNAP[src] = {
      identifiers = Framework.getIdentifier(src),
      ts = os.time(),
      movement = {}, needs = {}, health = {}, bio = {}, env = {}
    }
  end
  return SNAP[src]
end

local function setStateBag(src, ns, data)
  local ply = Player(src)
  if not ply or not ply.state then return end
  ply.state:set(('survival:%s'):format(ns), data, true)
end

local function exceededRate(src, ns, payloadLen)
  RATE[src] = RATE[src] or {}
  local now = GetGameTimer()
  local win = Config.Rate.windowMs
  local bucket = RATE[src][ns]
  if not bucket or now - bucket.t0 > win then
    RATE[src][ns] = { t0 = now, n = 0, bytes = 0 }
    bucket = RATE[src][ns]
  end
  bucket.n = bucket.n + 1
  bucket.bytes = bucket.bytes + (payloadLen or 0)
  if bucket.n > Config.Rate.maxMsgs or bucket.bytes > Config.Rate.maxPayloadBytes then
    return true
  end
  return false
end

-- Persistence (oxmysql with citizenid key) + file fallback
local function persistOne(src)
  local snap = SNAP[src]; if not snap then return end
  if MySQL and MySQL.update then
    MySQL.update([[
      INSERT INTO ]]..Config.Persistence.table..[[ (citizenid, data, updated_at)
      VALUES (?, ?, NOW())
      ON DUPLICATE KEY UPDATE data = VALUES(data), updated_at = VALUES(updated_at)
    ]], { snap.identifiers, json.encode(snap) })
  else
    local path = ('data_%s.json'):format(tostring(snap.identifiers))
    SaveResourceFile(GetCurrentResourceName(), path, json.encode(snap), -1)
  end
end

local function flushDirty()
  for src,_ in pairs(DIRTY) do
    persistOne(src)
    DIRTY[src] = nil
  end
end

CreateThread(function()
  while true do
    Wait((Config.Persistence.flushIntervalSec or 30) * 1000)
    flushDirty()
  end
end)

-- Ingress per-namespace: client -> server
local function registerNamespace(ns)
  local evt = ('survival:%s:update'):format(ns)
  RegisterNetEvent(evt, function(delta)
    local src = source
    if type(delta) ~= 'table' then return end
    local payload = json.encode(delta)
    if #payload > Config.Rate.maxPayloadBytes then return end
    if exceededRate(src, ns, #payload) then return end

    local snap = ensurePlayerSnapshot(src)
    local clamped = clampNamespace(ns, delta)

    local before = json.encode(snap[ns] or {})
    mergeDelta(snap[ns], clamped)
    snap.ts = os.time()

    local after = json.encode(snap[ns])
    if before ~= after then
      setStateBag(src, ns, snap[ns])
      DIRTY[src] = true
      if Config.BroadcastEnabled then
        TriggerClientEvent(('survival:%s:broadcast'):format(ns), -1, src, clamped)
      end
    end
  end)
  dbg('Ingress registered ns=', ns, ' event=', evt)
end

for _,ns in ipairs(Config.Namespaces) do
  registerNamespace(ns)
end

-- Lifecycle
AddEventHandler('playerConnecting', function(_, _, _)
  local src = source
  ensurePlayerSnapshot(src)
end)

AddEventHandler('playerDropped', function(_)
  local src = source
  flushDirty()
  if SNAP[src] then
    persistOne(src)
    SNAP[src] = nil
    RATE[src] = nil
  end
end)

-- Sync on demand
RegisterNetEvent('survival:hub:requestSync', function()
  local src = source
  local snap = ensurePlayerSnapshot(src)
  for _,ns in ipairs(Config.Namespaces) do
    setStateBag(src, ns, snap[ns])
  end
end)

-- Exports
exports('getState', function(src)
  if type(src) ~= 'number' then return nil end
  return SNAP[src]
end)

exports('update', function(src, ns, delta)
  if type(src)~='number' or type(ns)~='string' or type(delta)~='table' then return false end
  ns = ns:lower()
  local allowed = false
  for _,n in ipairs(Config.Namespaces) do if n==ns then allowed=true break end end
  if not allowed then return false end
  local snap = ensurePlayerSnapshot(src)
  local clamped = clampNamespace(ns, delta)
  mergeDelta(snap[ns], clamped)
  setStateBag(src, ns, snap[ns])
  DIRTY[src] = true
  return true
end)

-- Presence log
CreateThread(function()
  if GetResourceState('qbx_core') == 'started' then dbg('qbx_core detected') end
  if GetResourceState('oxmysql') == 'started' then dbg('oxmysql detected') end
end)
