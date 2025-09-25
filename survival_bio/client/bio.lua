local function log(...) if Config.Debug then print(('%s [CL] %s'):format(Config.DebugPrefix, table.concat({...}, ' '))) end end

-- Client is read-only for bio state; may display or forward exposure requests to other modules
RegisterNetEvent('survival:bio:progress', function(delta)
    -- no UI; reserved for other client systems to react if needed
    if Config.Debug and delta then log(('progress symptomatic=%s disease=%.2f'):format(tostring(delta.symptomatic), tonumber(delta.disease or -1))) end
end)

-- If a server module wants to solicit exposure from client-side context (e.g., drank from stream)
RegisterNetEvent('survival:bio:requestExposure', function(payload)
    -- In headless mode do nothing; other resources can intercept and send 'survival:bio:exposure'
    if Config.Debug then log('requestExposure received') end
end)
