local dbg = function(...) if Config.Debug then print(('%s [server] ' .. string.rep('%s ', select('#', ...))):format(Config.DebugPrefix, ...)) end end

local needsCache = {}      -- [license] = { food=.., water=.., energy=.., stress=.., poop=.., pee=.. }
local activityCache = {}   -- [license] = 'idle'
local lastEventAt = {}     -- rate-limit

local function clamp(v) if v < Config.ClampMin then return Config.ClampMin elseif v > Config.ClampMax then return Config.ClampMax else return v end end

local function defaultNeeds()
  return { food=100.0, water=100.0, energy=100.0, stress=10.0, poop=0.0, pee=0.0, ts=os.time() }
end

local function getLicense(src) return Adapter and Adapter.identify and Adapter.identify(src) or ('src:%s'):format(src) end

-- Rate-limit helper
local function rl(key, perMin)
  local now = GetGameTimer()
  local bucket = lastEventAt[key] or {t=0, n=0}
  if now - bucket.t > 60000 then bucket = {t=now, n=0} end
  bucket.n = bucket.n + 1
  lastEventAt[key] = bucket
  return bucket.n <= perMin
end

-- Apply one-second tick
local function applyTick(license, activity)
  local n = needsCache[license] or defaultNeeds()
  local mult = Config.Activity[activity or 'idle'] or Config.Activity.idle

  local dFood   = Config.Decay.food   * (mult.food   or 1.0)
  local dWater  = Config.Decay.water  * (mult.water  or 1.0)
  local dEnergy = (mult.energy or 0.0)
  local dStress = Config.Decay.stress * (mult.stress or 1.0)

  -- Bowel/Urine timers grow up to 100
  local dPoop = Config.Bowel.poop.base
  local dPee  = Config.Bowel.pee.base

  local new = {
    food   = clamp(n.food  - dFood*100),   -- scale to 0..100 UX; decay is small/sec
    water  = clamp(n.water - dWater*100),
    energy = clamp(n.energy - dEnergy*100),
    stress = clamp(n.stress + dStress*100),
    poop   = clamp(n.poop  + dPoop*100),
    pee    = clamp(n.pee   + dPee*100),
    ts     = os.time()
  }

  local delta = {
    food   = new.food   - n.food,
    water  = new.water  - n.water,
    energy = new.energy - n.energy,
    stress = new.stress - n.stress,
    poop   = new.poop   - n.poop,
    pee    = new.pee    - n.pee
  }

  needsCache[license] = new
  return new, delta
end

-- Push to state bag of the player source
local function pushState(src, data)
  local ply = Player(src)
  if ply and ply.state then
    ply.state:set('needs', data, true) -- replicated = true
  end
end

-- Public exports
exports('GetNeeds', function(src)
  local license = getLicense(src)
  return needsCache[license] or defaultNeeds()
end)

exports('SetNeeds', function(src, tbl)
  local license = getLicense(src)
  local n = needsCache[license] or defaultNeeds()
  for k,v in pairs(tbl or {}) do
    if n[k] ~= nil and type(v) == 'number' then
      n[k] = clamp(v)
    end
  end
  needsCache[license] = n
  pushState(src, n)
  return true
end)

exports('AddStress', function(src, amt)
  local license = getLicense(src)
  local n = needsCache[license] or defaultNeeds()
  n.stress = clamp(n.stress + (amt or 0))
  needsCache[license] = n
  pushState(src, n)
  return n.stress
end)

-- Receive activity hint from client
RegisterNetEvent('survival:needs:activity', function(activity)
  local src = source
  if not rl(('act:%s'):format(src), Config.RateLimit.clientUpdate) then
    if Config.Debug then dbg('rate-limit activity from', src) end
    return
  end
  local license = getLicense(src)
  activityCache[license] = activity
end)

-- Join/Drop hooks
Adapter.onPlayerLoaded(function(src)
  local license = getLicense(src)
  local saved = Persist.load(license)
  needsCache[license] = saved or defaultNeeds()
  activityCache[license] = 'idle'
  pushState(src, needsCache[license])
  if Config.Debug then dbg('loaded needs for', src, license) end
end)

Adapter.onPlayerDropped(function(src, reason)
  local license = getLicense(src)
  if needsCache[license] then
    Persist.save(license, needsCache[license])
  end
  needsCache[license] = nil
  activityCache[license] = nil
  if Config.Debug then dbg('dropped', src, reason or '') end
end)

-- Server tick
CreateThread(function()
  while true do
    Wait(Config.ServerTickMs)
    for _, src in ipairs(GetPlayers()) do
      local license = getLicense(src)
      local activity = activityCache[license] or 'idle'
      local before = needsCache[license] or defaultNeeds()
      local after, delta = applyTick(license, activity)

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
end)

-- Manual save timer
CreateThread(function()
  if not Config.Persistence.Enabled then return end
  while true do
    Wait(Config.Persistence.SaveIntervalSec * 1000)
    local all = {}
    for _, src in ipairs(GetPlayers()) do
      local license = getLicense(src)
      if needsCache[license] then
        all[license] = needsCache[license]
      end
    end
    Persist.saveAll(all)
  end
end)
