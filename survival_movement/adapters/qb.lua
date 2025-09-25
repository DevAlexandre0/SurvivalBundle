CreateThread(function()
  local hasQbox = GetResourceState('qbx_core') == 'started'
  local hasQBC  = GetResourceState('qb-core') == 'started'
  if not hasQbox and not hasQBC then return end

  -- เมื่อผู้เล่นโหลดเสร็จ ให้ probe เพื่อโหลด snapshot จากเซิร์ฟเวอร์
  RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    TriggerServerEvent('survival:movement:probe')
  end)
end)
