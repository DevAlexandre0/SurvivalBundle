SurvivalFramework = SurvivalFramework or {}

local Framework = {}
Framework.__index = Framework

local function noop() end

local function safeCall(fn, ...)
    if type(fn) ~= 'function' then return end
    local ok, err = pcall(fn, ...)
    if not ok then
        print(('[survival_shared] callback error: %s'):format(err))
    end
end

local function fallbackIdentifier(src)
    if type(src) ~= 'number' then return nil end
    if GetPlayerIdentifierByType then
        local lic = GetPlayerIdentifierByType(src, 'license')
        if lic and lic ~= '' then
            return ('license:%s'):format(lic)
        end
    end
    return ('src:%s'):format(tostring(src))
end

local function fetchExport(name)
    if type(exports) ~= 'table' then return nil end
    local ex = exports[name]
    if ex ~= nil then return ex end
    if exports[name] ~= nil then return exports[name] end
    return nil
end

local function makeDispatcher()
    local handlers = {}
    return {
        add = function(cb)
            if type(cb) == 'function' then
                handlers[#handlers+1] = cb
            end
        end,
        fire = function(...)
            for _, cb in ipairs(handlers) do
                safeCall(cb, ...)
            end
        end
    }
end

local function ensureTable(value)
    return type(value) == 'table' and value or {}
end

local function adapterForQbox(options)
    if not GetResourceState or GetResourceState('qbx_core') ~= 'started' then return nil end
    local ex = fetchExport('qbx_core')
    if not ex then return nil end

    local function fetchPlayer(src)
        if not src then return nil end
        if ex.GetPlayer then
            local ok, player = pcall(ex.GetPlayer, ex, src)
            if ok and player then return player end
        end
        if ex.GetCoreObject then
            local okCore, core = pcall(ex.GetCoreObject, ex)
            if okCore and core and core.Functions and core.Functions.GetPlayer then
                local okP, player = pcall(core.Functions.GetPlayer, core.Functions, src)
                if okP and player then return player end
            end
        end
        return nil
    end

    local function identifier(src)
        local player = fetchPlayer(src)
        local cid = player and player.PlayerData and player.PlayerData.citizenid
        if cid and cid ~= '' then
            return ('qb:%s'):format(cid)
        end
        return fallbackIdentifier(src)
    end

    local loadDispatch, dropDispatch = makeDispatcher(), makeDispatcher()
    local registered = false
    local function register()
        if registered then return end
        registered = true
        AddEventHandler('QBCore:Server:PlayerLoaded', function(player)
            local src = player and player.PlayerData and player.PlayerData.source or source
            loadDispatch.fire(src)
        end)
        AddEventHandler('playerDropped', function(reason)
            dropDispatch.fire(source, reason)
        end)
    end

    return setmetatable({
        name = 'qbox',
        getPlayer = fetchPlayer,
        getIdentifier = identifier,
        onPlayerLoaded = function(cb)
            register()
            loadDispatch.add(cb)
        end,
        onPlayerDropped = function(cb)
            register()
            dropDispatch.add(cb)
        end,
        hasPermission = function(src, capability)
            local perms = ensureTable(options and options.permissions)
            local rule = perms[capability]
            if not rule then return true end
            if type(rule) == 'function' then
                local ok, result = pcall(rule, src, 'qbox')
                return ok and result or false
            end
            if type(rule) == 'string' then
                if rule:sub(1,4) == 'ace:' and IsPlayerAceAllowed then
                    return IsPlayerAceAllowed(src, rule:sub(5))
                end
                if rule:sub(1,4) == 'job:' then
                    local jobName = rule:sub(5)
                    local ply = fetchPlayer(src)
                    local job = ply and ply.PlayerData and ply.PlayerData.job
                    local current = job and (job.name or job.id or job.label)
                    return current == jobName
                end
            end
            if type(rule) == 'table' then
                for _, entry in ipairs(rule) do
                    if type(entry) == 'string' then
                        if entry:sub(1,4) == 'ace:' and IsPlayerAceAllowed and IsPlayerAceAllowed(src, entry:sub(5)) then
                            return true
                        elseif entry:sub(1,4) == 'job:' then
                            local jobName = entry:sub(5)
                            local ply = fetchPlayer(src)
                            local job = ply and ply.PlayerData and ply.PlayerData.job
                            local current = job and (job.name or job.id or job.label)
                            if current == jobName then return true end
                        end
                    elseif type(entry) == 'function' then
                        local ok, res = pcall(entry, src, 'qbox')
                        if ok and res then return true end
                    end
                end
                return false
            end
            return false
        end,
    }, Framework)
end

local function adapterForQBCore(options)
    if not GetResourceState or GetResourceState('qb-core') ~= 'started' then return nil end
    local ex = fetchExport('qb-core')
    if not ex or not ex.GetCoreObject then return nil end
    local ok, core = pcall(ex.GetCoreObject, ex)
    if not ok or not core then return nil end

    local function fetchPlayer(src)
        if not core.Functions or not core.Functions.GetPlayer then return nil end
        local okPlayer, player = pcall(core.Functions.GetPlayer, core.Functions, src)
        if okPlayer then return player end
        return nil
    end

    local function identifier(src)
        local ply = fetchPlayer(src)
        local cid = ply and ply.PlayerData and ply.PlayerData.citizenid
        if cid and cid ~= '' then
            return ('qb:%s'):format(cid)
        end
        return fallbackIdentifier(src)
    end

    local loadDispatch, dropDispatch = makeDispatcher(), makeDispatcher()
    local registered = false
    local function register()
        if registered then return end
        registered = true
        AddEventHandler('QBCore:Server:PlayerLoaded', function(player)
            local src = player and player.PlayerData and player.PlayerData.source or source
            loadDispatch.fire(src)
        end)
        AddEventHandler('playerDropped', function(reason)
            dropDispatch.fire(source, reason)
        end)
    end

    return setmetatable({
        name = 'qb-core',
        getPlayer = fetchPlayer,
        getIdentifier = identifier,
        onPlayerLoaded = function(cb)
            register()
            loadDispatch.add(cb)
        end,
        onPlayerDropped = function(cb)
            register()
            dropDispatch.add(cb)
        end,
        hasPermission = function(src, capability)
            local perms = ensureTable(options and options.permissions)
            local rule = perms[capability]
            if not rule then return true end
            if type(rule) == 'function' then
                local ok, res = pcall(rule, src, 'qb-core')
                return ok and res or false
            end
            if type(rule) == 'string' then
                if rule:sub(1,4) == 'ace:' and IsPlayerAceAllowed then
                    return IsPlayerAceAllowed(src, rule:sub(5))
                elseif rule:sub(1,4) == 'job:' then
                    local ply = fetchPlayer(src)
                    local job = ply and ply.PlayerData and ply.PlayerData.job
                    local current = job and (job.name or job.label)
                    return current == rule:sub(5)
                end
            end
            if type(rule) == 'table' then
                for _, entry in ipairs(rule) do
                    if type(entry) == 'string' then
                        if entry:sub(1,4) == 'ace:' and IsPlayerAceAllowed and IsPlayerAceAllowed(src, entry:sub(5)) then
                            return true
                        elseif entry:sub(1,4) == 'job:' then
                            local ply = fetchPlayer(src)
                            local job = ply and ply.PlayerData and ply.PlayerData.job
                            local current = job and (job.name or job.label)
                            if current == entry:sub(5) then return true end
                        end
                    elseif type(entry) == 'function' then
                        local ok, res = pcall(entry, src, 'qb-core')
                        if ok and res then return true end
                    end
                end
                return false
            end
            return false
        end,
    }, Framework)
end

local function adapterForESX(options)
    if not GetResourceState or GetResourceState('es_extended') ~= 'started' then return nil end
    local ex = fetchExport('es_extended')
    if not ex then return nil end
    local ESX
    local function ensureESX()
        if ESX then return ESX end
        if ex.getSharedObject then
            local ok, obj = pcall(ex.getSharedObject, ex)
            if ok and obj then ESX = obj end
        elseif ex.GetSharedObject then
            local ok, obj = pcall(ex.GetSharedObject, ex)
            if ok and obj then ESX = obj end
        end
        return ESX
    end

    local function fetchPlayer(src)
        local obj = ensureESX()
        if not obj or not obj.GetPlayerFromId then return nil end
        local ok, player = pcall(obj.GetPlayerFromId, obj, src)
        if ok then return player end
        return nil
    end

    local function identifier(src)
        local ply = fetchPlayer(src)
        if ply and ply.identifier then return ply.identifier end
        if ply and ply.getIdentifier then
            local ok, id = pcall(ply.getIdentifier, ply)
            if ok and id then return id end
        end
        return fallbackIdentifier(src)
    end

    local loadDispatch, dropDispatch = makeDispatcher(), makeDispatcher()
    local registered = false
    local function register()
        if registered then return end
        registered = true
        AddEventHandler('esx:playerLoaded', function(src)
            loadDispatch.fire(src)
        end)
        AddEventHandler('esx:playerDropped', function(src, reason)
            dropDispatch.fire(src, reason)
        end)
        AddEventHandler('playerDropped', function(reason)
            dropDispatch.fire(source, reason)
        end)
    end

    return setmetatable({
        name = 'es_extended',
        getPlayer = fetchPlayer,
        getIdentifier = identifier,
        onPlayerLoaded = function(cb)
            register()
            loadDispatch.add(cb)
        end,
        onPlayerDropped = function(cb)
            register()
            dropDispatch.add(cb)
        end,
        hasPermission = function(src, capability)
            local perms = ensureTable(options and options.permissions)
            local rule = perms[capability]
            if not rule then return true end
            if type(rule) == 'function' then
                local ok, res = pcall(rule, src, 'es_extended')
                return ok and res or false
            end
            if type(rule) == 'string' then
                if rule:sub(1,4) == 'ace:' and IsPlayerAceAllowed then
                    return IsPlayerAceAllowed(src, rule:sub(5))
                elseif rule:sub(1,4) == 'job:' then
                    local ply = fetchPlayer(src)
                    local job = ply and (ply.job or (ply.getJob and ply:getJob()))
                    local current = type(job) == 'table' and (job.name or job.id) or job
                    return current == rule:sub(5)
                end
            end
            if type(rule) == 'table' then
                for _, entry in ipairs(rule) do
                    if type(entry) == 'string' then
                        if entry:sub(1,4) == 'ace:' and IsPlayerAceAllowed and IsPlayerAceAllowed(src, entry:sub(5)) then
                            return true
                        elseif entry:sub(1,4) == 'job:' then
                            local ply = fetchPlayer(src)
                            local job = ply and (ply.job or (ply.getJob and ply:getJob()))
                            local current = type(job) == 'table' and (job.name or job.id) or job
                            if current == entry:sub(5) then return true end
                        end
                    elseif type(entry) == 'function' then
                        local ok, res = pcall(entry, src, 'es_extended')
                        if ok and res then return true end
                    end
                end
                return false
            end
            return false
        end,
    }, Framework)
end

local function adapterForOx(options)
    if not GetResourceState or GetResourceState('ox_core') ~= 'started' then return nil end
    local ex = fetchExport('ox_core')
    if not ex then return nil end

    local function fetchPlayer(src)
        if ex.GetPlayer then
            local ok, player = pcall(ex.GetPlayer, ex, src)
            if ok and player then return player end
        end
        if ex.Player and ex.Player(src) then
            local ok, player = pcall(ex.Player, ex, src)
            if ok and player then return player end
        end
        return nil
    end

    local function identifier(src)
        local ply = fetchPlayer(src)
        if not ply then return fallbackIdentifier(src) end
        if ply.identifier then return ply.identifier end
        if ply.charId or ply.charid then
            return ('ox:%s'):format(ply.charId or ply.charid)
        end
        return fallbackIdentifier(src)
    end

    local loadDispatch, dropDispatch = makeDispatcher(), makeDispatcher()
    local registered = false
    local function register()
        if registered then return end
        registered = true
        AddEventHandler('ox:playerLoaded', function(src)
            loadDispatch.fire(src)
        end)
        AddEventHandler('ox:playerLogout', function(src, reason)
            dropDispatch.fire(src, reason)
        end)
        AddEventHandler('playerDropped', function(reason)
            dropDispatch.fire(source, reason)
        end)
    end

    return setmetatable({
        name = 'ox_core',
        getPlayer = fetchPlayer,
        getIdentifier = identifier,
        onPlayerLoaded = function(cb)
            register()
            loadDispatch.add(cb)
        end,
        onPlayerDropped = function(cb)
            register()
            dropDispatch.add(cb)
        end,
        hasPermission = function(src, capability)
            local perms = ensureTable(options and options.permissions)
            local rule = perms[capability]
            if not rule then return true end
            if type(rule) == 'function' then
                local ok, res = pcall(rule, src, 'ox_core')
                return ok and res or false
            end
            if type(rule) == 'string' then
                if rule:sub(1,4) == 'ace:' and IsPlayerAceAllowed then
                    return IsPlayerAceAllowed(src, rule:sub(5))
                end
                if rule:sub(1,5) == 'group' then
                    -- ox_core group:groupname
                    local groupName = rule:match('group:(.+)')
                    if groupName then
                        if ex.GetGroup then
                            local ok, groups = pcall(ex.GetGroup, ex, src)
                            if ok and groups then
                                if type(groups) == 'table' then
                                    for name in pairs(groups) do
                                        if name == groupName then return true end
                                    end
                                elseif groups == groupName then
                                    return true
                                end
                            end
                        end
                    end
                end
            end
            if type(rule) == 'table' then
                for _, entry in ipairs(rule) do
                    if type(entry) == 'string' then
                        if entry:sub(1,4) == 'ace:' and IsPlayerAceAllowed and IsPlayerAceAllowed(src, entry:sub(5)) then
                            return true
                        elseif entry:sub(1,5) == 'group' then
                            local groupName = entry:match('group:(.+)')
                            if groupName and ex.GetGroup then
                                local ok, groups = pcall(ex.GetGroup, ex, src)
                                if ok and groups then
                                    if type(groups) == 'table' then
                                        for name in pairs(groups) do
                                            if name == groupName then return true end
                                        end
                                    elseif groups == groupName then
                                        return true
                                    end
                                end
                            end
                        end
                    elseif type(entry) == 'function' then
                        local ok, res = pcall(entry, src, 'ox_core')
                        if ok and res then return true end
                    end
                end
                return false
            end
            return false
        end,
    }, Framework)
end

local function adapterForStandalone(options)
    local loadDispatch, dropDispatch = makeDispatcher(), makeDispatcher()
    local registered = false
    local function register()
        if registered then return end
        registered = true
        AddEventHandler('playerJoining', function()
            loadDispatch.fire(source)
        end)
        AddEventHandler('playerDropped', function(reason)
            dropDispatch.fire(source, reason)
        end)
    end

    return setmetatable({
        name = 'standalone',
        getPlayer = function(_) return nil end,
        getIdentifier = fallbackIdentifier,
        onPlayerLoaded = function(cb)
            register()
            loadDispatch.add(cb)
        end,
        onPlayerDropped = function(cb)
            register()
            dropDispatch.add(cb)
        end,
        hasPermission = function(_, capability)
            local perms = ensureTable(options and options.permissions)
            local rule = perms[capability]
            if not rule then return true end
            if type(rule) == 'function' then
                local ok, res = pcall(rule, nil, 'standalone')
                return ok and res or false
            end
            if type(rule) == 'string' and rule:sub(1,4) == 'ace:' and IsPlayerAceAllowed then
                return IsPlayerAceAllowed(source, rule:sub(5))
            end
            if type(rule) == 'table' then
                for _, entry in ipairs(rule) do
                    if type(entry) == 'string' and entry:sub(1,4) == 'ace:' and IsPlayerAceAllowed and IsPlayerAceAllowed(source, entry:sub(5)) then
                        return true
                    elseif type(entry) == 'function' then
                        local ok, res = pcall(entry, nil, 'standalone')
                        if ok and res then return true end
                    end
                end
                return false
            end
            return false
        end,
    }, Framework)
end

local factories = {
    qbox = adapterForQbox,
    qb = adapterForQBCore,
    ['qb-core'] = adapterForQBCore,
    esx = adapterForESX,
    ['es_extended'] = adapterForESX,
    ox = adapterForOx,
    ['ox_core'] = adapterForOx,
    standalone = adapterForStandalone,
}

local defaultPriority = { 'qbox', 'qb', 'ox', 'esx', 'standalone' }

function SurvivalFramework.buildAdapter(options)
    local priority = ensureTable(options and options.priority)
    if #priority == 0 then
        priority = defaultPriority
    end

    for _, key in ipairs(priority) do
        local factory = factories[key]
        if factory then
            local adapter = factory(options)
            if adapter then
                adapter.priority = key
                adapter.options = options
                return adapter
            end
        end
    end

    local adapter = adapterForStandalone(options)
    adapter.priority = 'standalone'
    adapter.options = options
    return adapter
end

return SurvivalFramework
