local dbg = function(...) if Config.Debug then print(('%s [client] ' .. string.rep('%s ', select('#', ...))):format(Config.DebugPrefix, ...)) end end

local activity = 'idle' -- idle/walk/run/sprint/swim/dive, ตั้งค่าโดยระบบอื่น หรือ fallback ด้านล่าง
local lastPush = 0

-- อ่าน activity จาก state/movement หากมี (ระบบ movement จะตั้งค่าไว้)
local function detectActivityFallback()
  local ped = PlayerPedId()
  if IsPedSwimmingUnderWater(ped) then return 'dive' end
  if IsPedSwimming(ped) then return 'swim' end
  if IsPedSprinting(ped) then return 'sprint' end
  if IsPedRunning(ped) then return 'run' end
  if IsPedWalking(ped) then return 'walk' end
  return 'idle'
end

CreateThread(function()
  while true do
    Wait(1000)
    -- หากมี state จาก survival_movement ให้ใช้แทน
    local st = LocalPlayer and LocalPlayer.state or nil
    if st and st.movement and st.movement.activity then
      activity = st.movement.activity
    else
      activity = detectActivityFallback()
    end

    -- แจ้ง server เฉพาะเมื่อ activity เปลี่ยนหรือตามช่วงเวลา
    local now = GetGameTimer()
    if now - lastPush > 3000 then
      lastPush = now
      TriggerServerEvent('survival:needs:activity', activity)
      if Config.Debug then dbg('activity=', activity) end
    end
  end
end)

-- อ่านค่า needs แบบสะดวกให้ทรัพยากรอื่นใช้ (client)
exports('ReadNeeds', function()
  local st = LocalPlayer and LocalPlayer.state or nil
  return st and st.needs or nil
end)
