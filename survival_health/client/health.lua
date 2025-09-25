local last = { hp = -1, bone = nil }
local rate = { sent = 0, minute = 0 }

CreateThread(function()
  while true do
    Wait(1000)
    rate.minute = 0
  end
end)

local function ped() return PlayerPedId() end
local function now() return GetGameTimer() end

CreateThread(function()
  Wait(1000)
  while true do
    Wait(Config.ClientSampleMs)

    local p = ped()
    local hp = GetEntityHealth(p) -- client (GET_ENTITY_HEALTH)
    local ok,bone = GetPedLastDamageBone(p) -- client
    local damaged = HasPedBeenDamagedByWeapon(p, 0, 2) -- any weapon

    -- normalize hp
    local hpN = math.min(100.0, math.max(0.0, (hp / Config.MaxHP) * 100.0))
    local delta = math.abs(hpN - (last.hp >= 0 and last.hp or hpN))

    local payload = nil
    if delta >= Config.DeltaThreshold or damaged or ok then
      payload = {
        hp = hpN,
        bone = ok and bone or nil,
        weap = damaged and GetSelectedPedWeapon(p) or nil,
        ragdoll = IsPedRagdoll(p) or IsPedFalling(p),
        ts = now()
      }
    end

    if payload and rate.minute < Config.RateLimitPerMin then
      TriggerServerEvent('survival:health:update', payload)
      rate.minute = rate.minute + 1
      last.hp = hpN
      -- clear local damage marker so next hit can be detected
      ClearPedLastDamageBone(p)
    end
  end
end)

-- receive server broadcasts (optional)
RegisterNetEvent('survival:health:broadcast', function(delta)
  -- headless; consumers can listen separately
  if Config.Debug then
    print(('[survival_health] delta: %s'):format(json.encode(delta)))
  end
end)
