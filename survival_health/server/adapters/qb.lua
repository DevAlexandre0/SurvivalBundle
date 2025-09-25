-- Qbox-first identifier + permission adapter
Adapter = Adapter or {}

local function getCitizenIdFromQbox(src)
  if GetResourceState('qbx_core') ~= 'started' then return nil end
  local ex = exports['qbx_core']
  if ex and ex.GetPlayer then
    local p = ex:GetPlayer(src)
    if p and p.PlayerData and p.PlayerData.citizenid then
      return p.PlayerData.citizenid
    end
  end
  if exports.qbx_core and exports.qbx_core.GetPlayer then
    local p2 = exports.qbx_core:GetPlayer(src)
    if p2 and p2.PlayerData and p2.PlayerData.citizenid then
      return p2.PlayerData.citizenid
    end
  end
  return nil
end

local function getCitizenIdFromQBCore(src)
  if GetResourceState('qb-core') ~= 'started' then return nil end
  local QBCore = exports['qb-core'] and exports['qb-core']:GetCoreObject()
  local Player = QBCore and QBCore.Functions and QBCore.Functions.GetPlayer(src)
  return Player and Player.PlayerData and Player.PlayerData.citizenid or nil
end

local function getLicense(src)
  local lic = GetPlayerIdentifierByType(src, 'license')
  return lic or ('src:'..src)
end

-- Override identifier ให้เป็น Qbox → QBCore → license
function Adapter.getIdentifier(src)
  local cid = getCitizenIdFromQbox(src) or getCitizenIdFromQBCore(src)
  if cid then return ('qb:%s'):format(cid) end
  return ('license:%s'):format(getLicense(src))
end

-- ปรับตามระบบสิทธิ์ของคุณภายหลังได้
function Adapter.canDamageModify(src)
  return true
end
