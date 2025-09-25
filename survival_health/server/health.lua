local state = {}     -- by src: { hp, blood, bleedTier, fracture, lastTs }
local lastSent = {}  -- debounce for broadcasts

local function dbg(msg, ...)
  if Config.Debug then print(('[survival_health] '..msg):format(...)) end
end

local function clamp01(x) return math.min(100.0, math.max(0.0, x)) end

local function initPlayer(src)
  state[src] = state[src] or {
    hp = 100.0, blood = Config.InitBlood, bleedTier = 0,
    fracture = { arm=false, leg=false }, pain = 0.0, trauma = 0.0, ts = GetGameTimer()
  }
  local ps = Player(src).state
  ps:set('health', {
    hp = state[src].hp, blood = state[src].blood, bleed = 0,
    fracture = state[src].fracture, pain = 0.0, trauma = 0.0, ts = state[src].ts
  }, true)
end

AddEventHandler('playerJoining', function() initPlayer(source) end)
AddEventHandler('playerDropped', function()
  local src = source
  state[src] = nil
  lastSent[src] = nil
end)

local rate = {}
local function allowRate(src)
  local t = GetGameTimer()
  local bucket = math.floor(t / 60000)
  rate[src] = rate[src] or { b = bucket, c = 0 }
  if rate[src].b ~= bucket then rate[src].b, rate[src].c = bucket, 0 end
  if rate[src].c >= Config.RateLimitPerMin then return false end
  rate[src].c = rate[src].c + 1
  return true
end

RegisterNetEvent('survival:health:update', function(payload)
  local src = source
  if type(payload) ~= 'table' then return end
  if not allowRate(src) then return end

  state[src] = state[src] or initPlayer(src)
  local st = state[src]
  local oldHp = st.hp
  local hp = clamp01(payload.hp or oldHp)

  -- anomaly guard: disallow huge positive spikes
  if hp - oldHp > Config.MaxHpGainPerTick then
    dbg('blocked hp spike from %d: old=%.2f new=%.2f', src, oldHp, hp)
    hp = oldHp
  end

  -- classify damage event if hp dropped
  if hp < oldHp then
    local weapType = HealthShared.classifyWeapon(payload.weap)
    local boneGroup = HealthShared.classifyBone(payload.bone)
    local tier = math.min(Config.MaxBleedTier, Config.WeaponBleedMap[weapType] or 1)

    -- fracture check
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

  -- update statebag
  local ps = Player(src).state
  ps:set('health', {
    hp = st.hp, blood = st.blood or Config.InitBlood,
    bleed = st.bleedTier or 0, fracture = st.fracture,
    pain = st.pain or 0.0, trauma = st.trauma or 0.0, ts = st.ts
  }, true)
end)

-- bleed simulation
CreateThread(function()
  while true do
    Wait(Config.ServerTickMs)
    local dt = Config.ServerTickMs / 1000.0
    for src, st in pairs(state) do
      -- apply bleed effects
      local tier = st.bleedTier or 0
      local eff = Config.BleedTiers[tier] or Config.BleedTiers[0]
      local newHp    = clamp01(st.hp    - eff.hp    * dt)
      local newBlood = clamp01((st.blood or Config.InitBlood) - eff.blood * dt)

      st.hp, st.blood = newHp, newBlood

      -- KO/death thresholds (example): if blood <= 0 then force downed
      if st.blood <= 0.0 and st.hp > 0.0 then
        -- optional: apply damage server-side (ApplyDamageToPed via routing bucket owner)
        -- left as integration point
      end

      -- push delta to clients occasionally
      local key = lastSent[src] or { hp=-1, blood=-1, bleed=-1 }
      if math.abs(newHp - key.hp) >= 1.0 or math.abs(newBlood - key.blood) >= 2.0 or (tier ~= key.bleed) then
        lastSent[src] = { hp=newHp, blood=newBlood, bleed=tier }
        TriggerClientEvent('survival:health:broadcast', -1, {
          src = src,
          health = { hp = newHp, blood = newBlood, bleed = tier, fracture = st.fracture }
        })
        -- update statebag
        local ps = Player(src).state
        ps:set('health', {
          hp = st.hp, blood = st.blood, bleed = st.bleedTier,
          fracture = st.fracture, pain = st.pain or 0.0, trauma = st.trauma or 0.0, ts = GetGameTimer()
        }, true)
      end
    end
  end
end)

-- public exports
exports('GetHealthState', function(src)
  local st = state[src]
  if not st then return nil end
  return {
    hp = st.hp, blood = st.blood, bleed = st.bleedTier,
    fracture = st.fracture, pain = st.pain or 0.0, trauma = st.trauma or 0.0
  }
end)

exports('StopBleeding', function(src)
  if not Adapter.canDamageModify(src) then return false end
  if not state[src] then return false end
  state[src].bleedTier = 0
  return true
end)

exports('SetBleedTier', function(src, tier)
  if not Adapter.canDamageModify(src) then return false end
  if not state[src] then return false end
  state[src].bleedTier = math.min(Config.MaxBleedTier, math.max(0, tonumber(tier) or 0))
  return true
end)
