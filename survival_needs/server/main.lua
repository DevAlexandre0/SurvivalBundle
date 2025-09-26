local Adapter = SurvivalFramework.buildAdapter({
  priority = Config.Framework and Config.Framework.priority,
  permissions = Config.Framework and Config.Framework.permissions
})

local dbg = function(...)
  if Config.Debug then
    print(('%s [server] ' .. string.rep('%s ', select('#', ...))):format(Config.DebugPrefix, ...))
  end
end

local needsCache = {}
local activityCache = {}
local lastEventAt = {}

local function validSource(src)
  return type(src) == 'number' and src > 0
end

local function clamp(v)
  if v < Config.ClampMin then return Config.ClampMin end
  if v > Config.ClampMax then return Config.ClampMax end
  return v
end

local function defaultNeeds()
  return { food=100.0, water=100.0, energy=100.0, stress=10.0, poop=0.0, pee=0.0, ts=os.time() }
end

local function getIdentifier(src)
  return Adapter.getIdentifier(src) or ('src:%s'):format(src)
end

local function rl(key, perMin)
  local now = GetGameTimer()
  local bucket = lastEventAt[key] or {t=0, n=0}
  if now - bucket.t > 60000 then bucket = {t=now, n=0} end
  bucket.n = bucket.n + 1
  lastEventAt[key] = bucket
  return bucket.n <= perMin
end

local function applyTick(license, activity)
  local n = needsCache[license] or defaultNeeds()
  local mult = Config.Activity[activity or 'idle'] or Config.Activity.idle

  local dFood   = Config.Decay.food   * (mult.food   or 1.0)
  local dWater  = Config.Decay.water  * (mult.water  or 1.0)
  local dEnergy = (mult.energy or 0.0)
  local dStress = Config.Decay.stress * (mult.stress or 1.0)

  local dPoop = Config.Bowel.poop.base
  local dPee  = Config.Bowel.pee.base

  local new = {
    food   = clamp(n.food  - dFood*100),
    water  = clamp(n.water - dWater*100),
    energy = clamp(n.energy - dEnergy*100),
    stress = clamp(n.stress + dStress*100),
    poop   = clamp(n.poop  + dPoop*100),
    pee    = clamp(n.pee   + dPee*100),
    ts     = os.time()
  }

  needsCache[license] = new
  return new
end

local function pushState(src, data)
  local ply = Player(src)
  if ply and ply.state then
    ply.state:set('needs', data, true)
  end
end

exports('GetNeeds', function(src)
  if not validSource(src) then return defaultNeeds() end
  local license = getIdentifier(src)
  return needsCache[license] or defaultNeeds()
end)

exports('SetNeeds', function(src, tbl)
  if not validSource(src) then return false end
  local license = getIdentifier(src)
  local n = needsCache[license] or defaultNeeds()
  for k,v in pairs(tbl or {}) do
    if n[k] ~= nil and type(v) == 'number' then
      n[k] = clamp(v)
    end
  end
  needsCache[license] = n
  pushState(src, n)
  Persist.save(license, n)
  return true
end)

exports('AddStress', function(src, amt)
  if not validSource(src) then return false end
  local license = getIdentifier(src)
  local n = needsCache[license] or defaultNeeds()
  n.stress = clamp(n.stress + (amt or 0))
  needsCache[license] = n
  pushState(src, n)
  Persist.save(license, n)
  return n.stress
end)

RegisterNetEvent('survival:needs:activity', function(activity)
  local src = source
  if not validSource(src) then return end
  if not rl(('act:%s'):format(src), Config.RateLimit.clientUpdate) then
    if Config.Debug then dbg('rate-limit activity from', src) end
    return
  end
  local license = getIdentifier(src)
  activityCache[license] = tostring(activity or 'idle')
end)

local function onPlayerLoaded(src)
  if not validSource(src) then return end
  local license = getIdentifier(src)
  local saved = Persist.load(license)
  needsCache[license] = saved or defaultNeeds()
  activityCache[license] = 'idle'
  pushState(src, needsCache[license])
  if Config.Debug then dbg('loaded needs for', src, license) end
end

local function onPlayerDropped(src, reason)
  if not validSource(src) then return end
  local license = getIdentifier(src)
  if needsCache[license] then
    Persist.save(license, needsCache[license])
  end
  needsCache[license] = nil
  activityCache[license] = nil
  if Config.Debug then dbg('dropped', src, reason or '') end
end

Adapter.onPlayerLoaded(onPlayerLoaded)
AddEventHandler('playerJoining', function(src)
  onPlayerLoaded(src)
end)

Adapter.onPlayerDropped(onPlayerDropped)
AddEventHandler('playerDropped', function(reason)
  onPlayerDropped(source, reason)
end)

CreateThread(function()
  while true do
    Wait(Config.ServerTickMs)
    for _, src in ipairs(GetPlayers()) do
      src = tonumber(src)
      if validSource(src) then
        local license = getIdentifier(src)
        local activity = activityCache[license] or 'idle'
        local before = needsCache[license] or defaultNeeds()
        local after = applyTick(license, activity)

        local delta = {
          food   = after.food   - before.food,
          water  = after.water  - before.water,
          energy = after.energy - before.energy,
          stress = after.stress - before.stress,
          poop   = after.poop   - before.poop,
          pee    = after.pee    - before.pee
        }

        local bigDelta =
          math.abs(delta.food)   > Config.DeltaEpsilon or
          math.abs(delta.water)  > Config.DeltaEpsilon or
          math.abs(delta.energy) > Config.DeltaEpsilon or
          math.abs(delta.stress) > Config.DeltaEpsilon or
          math.abs(delta.poop)   > Config.DeltaEpsilon or
          math.abs(delta.pee)    > Config.DeltaEpsilon

        if bigDelta then
          pushState(src, after)
          if Config.BroadcastOnDelta then
            TriggerClientEvent('survival:needs:broadcast', src, delta, after)
          end
        end
      end
    end
  end
end)

CreateThread(function()
  if not Config.Persistence.Enabled then return end
  while true do
    Wait(Config.Persistence.SaveIntervalSec * 1000)
    local all = {}
    for _, src in ipairs(GetPlayers()) do
      src = tonumber(src)
      if validSource(src) then
        local license = getIdentifier(src)
        if needsCache[license] then
          all[license] = needsCache[license]
        end
      end
    end
    Persist.saveAll(all)
  end
end)
