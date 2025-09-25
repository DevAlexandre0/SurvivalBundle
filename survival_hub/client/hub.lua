-- FILE: survival_hub/client/hub.lua
local function dbg(...)
  if Config.Debug then print(('[%s][cli] %s'):format(GetCurrentResourceName(), table.concat({...}, ' '))) end
end

-- Request initial sync after spawn
CreateThread(function()
  while not NetworkIsPlayerActive(PlayerId()) do Wait(250) end
  TriggerServerEvent('survival:hub:requestSync')
  dbg('requested initial sync')
end)

-- Optional debug command: show current state bags
RegisterCommand('surv_state', function()
  local st = {
    movement = LocalPlayer.state['survival:movement'],
    needs    = LocalPlayer.state['survival:needs'],
    health   = LocalPlayer.state['survival:health'],
    bio      = LocalPlayer.state['survival:bio'],
    env      = LocalPlayer.state['survival:env'],
  }
  print(('[%s] state=%s'):format(GetCurrentResourceName(), json.encode(st or {})))
end, false)
