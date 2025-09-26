local Adapter = SurvivalFramework.buildAdapter({
  priority = Config.Framework and Config.Framework.priority,
  permissions = Config.Framework and Config.Framework.permissions
})

local state = {}
local lastSent = {}
local rate = {}

local function dbg(fmt, ...)
  if not Config.Debug then return end
  if select('#', ...) > 0 then
    print(('[survival_health] ' .. fmt):format(...))
  else
    print('[survival_health] ' .. tostring(fmt))
  end
end

local function clamp01(x)
  return math.min(100.0, math.max(0.0, x))
end

local function validSource(src)
  return type(src) == 'number' and src > 0
end

local function allowRate(src)
  local t = GetGameTimer()
  local bucket = math.floor(t / 60000)
  rate[src] = rate[src] or { b = bucket, c = 0 }
  local r = rate[src]
  if r.b ~= bucket then r.b, r.c = bucket, 0 end
  if r.c >= (Config.RateLimitPerMin or 60) then return false end
  r.c = r.c + 1
  return true
end

local function pushState(src)
  local ply = Player(src)
  if not ply or not ply.state then return end
  local st = state[src]
  ply.state:set('health', {
    hp = st.hp,
    blood = st.blood,
    bleed = st.bleedTier,
    fracture = st.fracture,
    pain = st.pain or 0.0,
    trauma = st.trauma or 0.0,
    ts = st.ts
  }, true)
end

local function initPlayer(src)
  if not validSource(src) then return end
  if state[src] then return end
  state[src] = {
    hp = 100.0,
    blood = Config.InitBlood,
    bleedTier = 0,
    fracture = { arm=false, leg=false },
    pain = 0.0,
    trauma = 0.0,
    ts = GetGameTimer()
  }
  pushState(src)
  dbg('initialised health src=%d adapter=%s', src, Adapter.name or 'unknown')
end

local function cleanup(src)
  state[src] = nil
  lastSent[src] = nil
  rate[src] = nil
end

Adapter.onPlayerLoaded(initPlayer)
AddEventHandler('playerJoining', function(src)
  initPlayer(src)
end)

Adapter.onPlayerDropped(cleanup)
AddEventHandler('playerDropped', function()
  cleanup(source)
end)

RegisterNetEvent('survival:health:update', function(payload)
  local src = source
  if not validSource(src) then return end
  if type(payload) ~= 'table' then return end
  if not allowRate(src) then return end

  initPlayer(src)
  local st = state[src]
  local oldHp = st.hp
  local hp = clamp01(tonumber(payload.hp) or oldHp)

  if hp - oldHp > Config.MaxHpGainPerTick then
    dbg('blocked hp spike src=%d old=%.2f new=%.2f', src, oldHp, hp)
    hp = oldHp
  end

  if hp < oldHp then
    local weapType = HealthShared.classifyWeapon(payload.weap)
    local boneGroup = HealthShared.classifyBone(payload.bone)
    local tier = math.min(Config.MaxBleedTier, Config.WeaponBleedMap[weapType] or 1)
    if boneGroup == 'leg' or boneGroup == 'arm' then
      local chance = Config.FractureChance[boneGroup] or 0.0
      if math.random() < chance then
        st.fracture[boneGroup] = true
      end
    end
    st.bleedTier = math.max(st.bleedTier or 0, tier)
  end

  st.hp = hp
  st.ts = payload.ts or GetGameTimer()
  pushState(src)
end)

CreateThread(function()
  while true do
    Wait(Config.ServerTickMs)
    local dt = Config.ServerTickMs / 1000.0
    for src, st in pairs(state) do
      local tier = st.bleedTier or 0
      local eff = Config.BleedTiers[tier] or Config.BleedTiers[0]
      local newHp = clamp01(st.hp - eff.hp * dt)
      local newBlood = clamp01((st.blood or Config.InitBlood) - eff.blood * dt)
      st.hp, st.blood = newHp, newBlood

      local key = lastSent[src] or { hp=-1, blood=-1, bleed=-1 }
      if math.abs(newHp - key.hp) >= Config.DeltaThreshold or math.abs(newBlood - key.blood) >= Config.DeltaThreshold or tier ~= key.bleed then
        lastSent[src] = { hp=newHp, blood=newBlood, bleed=tier }
        TriggerClientEvent('survival:health:broadcast', -1, {
          src = src,
          health = { hp = newHp, blood = newBlood, bleed = tier, fracture = st.fracture }
        })
        pushState(src)
      end
    end
  end
end)

exports('GetHealthState', function(src)
  if not validSource(src) then return nil end
  return state[src]
end)

exports('StopBleeding', function(src)
  if not validSource(src) or not state[src] then return false end
  if not Adapter.hasPermission(src, 'medical') then return false end
  state[src].bleedTier = 0
  pushState(src)
  return true
end)

exports('SetBleedTier', function(src, tier)
  if not validSource(src) or not state[src] then return false end
  if not Adapter.hasPermission(src, 'medical') then return false end
  state[src].bleedTier = math.min(Config.MaxBleedTier, math.max(0, tonumber(tier) or 0))
  pushState(src)
  return true
end)

exports('SetPain', function(src, value)
  if not validSource(src) or not state[src] then return false end
  if not Adapter.hasPermission(src, 'medical') then return false end
  state[src].pain = clamp01(tonumber(value) or 0.0)
  pushState(src)
  return true
end)

exports('ResetFractures', function(src)
  if not validSource(src) or not state[src] then return false end
  if not Adapter.hasPermission(src, 'medical') then return false end
  state[src].fracture = { arm=false, leg=false }
  pushState(src)
  return true
end)

AddEventHandler('onResourceStart', function(res)
  if res ~= GetCurrentResourceName() then return end
  dbg('health adapter=%s ready', Adapter.name or 'unknown')
end)
