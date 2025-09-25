CreateThread(function()
  -- ตรวจลำดับ: qbx_core → qb-core
  local hasQbox = GetResourceState('qbx_core') == 'started'
  local hasQBC  = GetResourceState('qb-core') == 'started'
  if not hasQbox and not hasQBC then return end

  Adapter.name = 'qbox' -- ชี้ชัดว่าโหมด qbox

  -- ดึง Core ให้ยืดหยุ่นทั้งสองเคส
  local Core
  if hasQbox then
    -- Qbox มักไม่ต้อง GetCoreObject ก็ได้ แต่รองรับทั้งสอง
    Core = (exports['qbx_core'] and (exports['qbx_core'].GetCoreObject and exports['qbx_core']:GetCoreObject())) or exports['qbx_core']
  elseif hasQBC then
    Core = exports['qb-core']:GetCoreObject()
  end

  -- events โหลดผู้เล่น: Qbox ใช้ชุดเดียวกับ QBCore โดยทั่วไป
  function Adapter.onPlayerLoaded(cb)
    AddEventHandler('QBCore:Server:PlayerLoaded', function(player)
      local src = (type(player) == 'table' and player.PlayerData and player.PlayerData.source) or source
      cb(src)
    end)
  end

  -- events ออกเกม
  function Adapter.onPlayerDropped(cb)
    AddEventHandler('playerDropped', function(reason)
      cb(source, reason or 'dropped')
    end)
  end

  -- หา identifier ที่เสถียรสุด: license: → citizenid → ตกสุดเป็น src
  local function findLicenseIdentifier(src)
    for _, id in ipairs(GetPlayerIdentifiers(src)) do
      if id:sub(1, 8) == 'license:' then
        return id
      end
    end
    return nil
  end

  local function getPlayerObject(src)
    if hasQbox and exports['qbx_core'] and exports['qbx_core'].GetPlayer then
      return exports['qbx_core']:GetPlayer(src)
    end
    if Core and Core.Functions and Core.Functions.GetPlayer then
      return Core.Functions.GetPlayer(src)
    end
    return nil
  end

  function Adapter.identify(src)
    -- 1) license: จาก identifiers
    local lic = findLicenseIdentifier(src)
    if lic then return lic end

    -- 2) citizenid จากตัวผู้เล่น
    local p = getPlayerObject(src)
    local cid = p and p.PlayerData and p.PlayerData.citizenid
    if cid then return ('cid:%s'):format(cid) end

    -- 3) ตกสุดเป็น src
    return ('src:%s'):format(src)
  end
end)
