-- Qbox/QBCore adapter
local M = { name = 'qbox' }

local function getFromQbox(src)
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

local function getFromQBCore(src)
    if GetResourceState('qb-core') ~= 'started' then return nil end
    local QBCore = exports['qb-core'] and exports['qb-core']:GetCoreObject()
    local Player = QBCore and QBCore.Functions and QBCore.Functions.GetPlayer(src)
    return Player and Player.PlayerData and Player.PlayerData.citizenid or nil
end

function M.getIdentifier(src)
    local cid = getFromQbox(src) or getFromQBCore(src)
    if cid then return ('qb:%s'):format(cid) end
    local lic = GetPlayerIdentifierByType(src, 'license') or ('src:'..src)
    return ('license:%s'):format(lic)
end

return M
