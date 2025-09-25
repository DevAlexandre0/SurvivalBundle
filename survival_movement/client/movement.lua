local last = { stamina = -1, oxygen = -1, sprinting = false, underwater = false }
local evCounter = 0
local evWindowStart = 0

local function dbg(...) if Config.Debug then print(('[movement:client] '):gsub('\n','') , ...) end end

-- Normalize helpers
local function normPercent(v)
  if v == nil then return 0.0 end
  if v <= 1.01 then return math.min(100.0, math.max(0.0, v * 100.0)) end
  return math.min(100.0, math.max(0.0, v))
end

local function calcOxygenPct()
  local t = GetPlayerUnderwaterTimeRemaining(PlayerId()) -- seconds
  -- If native returns <0 when not underwater, treat as full oxygen
  if t == nil then return 100.0 end
  local pct = (t / Config.MaxUnderwaterSeconds) * 100.0
  return math.max(0.0, math.min(100.0, pct))
end

-- Apply server-authorized effects
RegisterNetEvent('survival:movement:apply', function(data)
  if type(data) ~= 'table' then return end
  if data.staminaRegen and data.staminaRegen > 0 then
    RestorePlayerStamina(PlayerId(), math.min(1.0, data.staminaRegen))
  end
  -- Optional: lock underwater timer or adjust max underwater using server policies
  -- if data.underwaterPct then SetPlayerUnderwaterTimeRemaining(PlayerId(), data.underwaterPct) end
end)

-- Utility: bounded event rate
local function canSendNow()
  local now = GetGameTimer()
  if now - evWindowStart > 60000 then
    evWindowStart = now
    evCounter = 0
  end
  if evCounter < Config.MaxEventsPerMinute then
    evCounter = evCounter + 1
    return true
  end
  return false
end

-- Main loop
CreateThread(function()
  Wait(1000)
  while true do
    local ped = PlayerPedId()
    local stamina = normPercent(GetPlayerSprintStaminaRemaining(PlayerId()))
    local underwaterTime = GetPlayerUnderwaterTimeRemaining(PlayerId())
    local underwater = underwaterTime and underwaterTime > 0.0 and IsPedSwimmingUnderWater(ped) or false
    local oxygen = underwater and calcOxygenPct() or 100.0
    local sprinting = IsPedSprinting(ped)

    local delta = math.max(
      math.abs(stamina - (last.stamina >= 0 and last.stamina or stamina)),
      math.abs(oxygen  - (last.oxygen  >= 0 and last.oxygen  or oxygen))
    )

    if delta >= Config.ReportThreshold or (underwater ~= last.underwater) or (sprinting ~= last.sprinting) then
      if canSendNow() then
        TriggerServerEvent('survival:movement:update', {
          stamina   = math.floor(stamina * 10) / 10.0,
          oxygen    = math.floor(oxygen * 10) / 10.0,
          sprinting = sprinting,
          underwater= underwater,
          ts        = GetGameTimer()
        })
        if LocalPlayer and LocalPlayer.state then
          LocalPlayer.state:set('movement', {
            stamina=stamina, oxygen=oxygen, sprinting=sprinting, underwater=underwater, ts=GetGameTimer()
          }, true)
        end
        if Config.Debug then dbg(('report Δ=%.1f s=%.1f o=%.1f sprint=%s under=%s'):format(delta, stamina, oxygen, sprinting, underwater)) end
      else
        if Config.Debug then dbg('throttled report') end
      end
      last.stamina, last.oxygen, last.sprinting, last.underwater = stamina, oxygen, sprinting, underwater
    end
    Wait(Config.TickMs)
  end
end)
