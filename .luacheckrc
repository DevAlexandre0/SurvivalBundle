std = 'lua54'

globals = {
  'Config', 'Player', 'TriggerClientEvent', 'RegisterNetEvent', 'AddEventHandler',
  'GetGameTimer', 'GetPlayers', 'MySQL', 'GetResourceState', 'GetCurrentResourceName',
  'LoadResourceFile', 'SaveResourceFile', 'json', 'GetPlayerIdentifierByType',
  'GetPlayerPed', 'GetEntityCoords', 'SurvivalFramework', 'HealthShared',
  'IsPlayerAceAllowed', 'exports', 'CreateThread', 'Wait', 'TriggerServerEvent',
  'PlayerPedId', 'GetRainLevel', 'GetSnowLevel', 'GetWindSpeed', 'GetEntitySubmergedLevel',
  'GetEntitySpeed', 'GetClockHours', 'GetEntityHealth', 'GetPedLastDamageBone',
  'HasPedBeenDamagedByWeapon', 'GetSelectedPedWeapon', 'IsPedRagdoll', 'IsPedFalling',
  'ClearPedLastDamageBone', 'Locales', 'Persist', 'source', 'TriggerEvent',
  'fx_version', 'game', 'lua54', 'name', 'author', 'description', 'version',
  'shared_scripts', 'client_scripts', 'server_scripts', 'dependencies', 'provide', 'provides',
  'shared_script', 'vec3', 'GetHashKey'
}

ignore = {
  '111', -- allow global access (FiveM environment)
}

files['tests/adapter_spec.lua'] = {
  globals = { 'package', 'SurvivalFramework', 'exports', 'GetResourceState', 'IsPlayerAceAllowed', 'AddEventHandler' },
  ignore = { '111', '412', '213', '631' }
}
