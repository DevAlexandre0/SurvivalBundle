local RESOURCE = GetCurrentResourceName()

local function dbg(fmt, ...)
    if not Config.Debug then return end
    local prefix = Config.LogPrefix or ('[' .. RESOURCE .. ']')
    print(('%s %s'):format(prefix, select('#', ...) > 0 and (fmt:format(...)) or tostring(fmt)))
end

local function fallbackIdentifier(src)
    local lic = GetPlayerIdentifierByType(src, 'license')
    if lic and lic ~= '' then
        return ('license:%s'):format(lic)
    end
    return ('src:%d'):format(src)
end

local function buildAdapter()
    local adapters = {}

    adapters.qbox = function()
        if GetResourceState('qbx_core') ~= 'started' then return nil end
        local ex = exports['qbx_core']
        if not ex then return nil end
        local function fetchPlayer(src)
            if ex.GetPlayer then
                local ok, player = pcall(ex.GetPlayer, ex, src)
                if ok and player then return player end
            end
            if ex.GetCoreObject then
                local ok, core = pcall(ex.GetCoreObject, ex)
                if ok and core and core.Functions and core.Functions.GetPlayer then
                    local ok2, player = pcall(core.Functions.GetPlayer, core.Functions, src)
                    if ok2 and player then return player end
                end
            end
            return nil
        end
        return {
            name = 'qbox',
            getPlayer = function(src)
                return fetchPlayer(src)
            end,
            getIdentifier = function(src)
                local player = fetchPlayer(src)
                local cid = player and player.PlayerData and player.PlayerData.citizenid
                if cid and cid ~= '' then
                    return ('qb:%s'):format(cid)
                end
                return fallbackIdentifier(src)
            end,
        }
    end

    adapters.qb = function()
        if GetResourceState('qb-core') ~= 'started' then return nil end
        local function core()
            local ok, obj = pcall(function() return exports['qb-core']:GetCoreObject() end)
            return ok and obj or nil
        end
        local cached = core()
        local function fetchPlayer(src)
            cached = cached or core()
            if not cached or not cached.Functions or not cached.Functions.GetPlayer then return nil end
            local ok, player = pcall(cached.Functions.GetPlayer, cached.Functions, src)
            if ok and player then return player end
            return nil
        end
        return {
            name = 'qb-core',
            getPlayer = function(src)
                return fetchPlayer(src)
            end,
            getIdentifier = function(src)
                local player = fetchPlayer(src)
                local cid = player and player.PlayerData and player.PlayerData.citizenid
                if cid and cid ~= '' then
                    return ('qb:%s'):format(cid)
                end
                return fallbackIdentifier(src)
            end,
        }
    end

    adapters.esx = function()
        if GetResourceState('es_extended') ~= 'started' then return nil end
        local ESX
        local function ensureESX()
            if ESX then return ESX end
            local ok, obj = pcall(function()
                return exports['es_extended']:getSharedObject()
            end)
            if ok and obj then ESX = obj end
            return ESX
        end
        return {
            name = 'es_extended',
            getPlayer = function(src)
                local obj = ensureESX()
                if not obj or not obj.GetPlayerFromId then return nil end
                local ok, player = pcall(obj.GetPlayerFromId, obj, src)
                if ok and player then return player end
                return nil
            end,
            getIdentifier = function(src)
                local obj = ensureESX()
                if obj and obj.GetIdentifier then
                    local ok, identifier = pcall(obj.GetIdentifier, obj, src)
                    if ok and identifier and identifier ~= '' then
                        return identifier
                    end
                end
                return fallbackIdentifier(src)
            end,
        }
    end

    adapters.standalone = function()
        return {
            name = 'standalone',
            getPlayer = function(_)
                return nil
            end,
            getIdentifier = fallbackIdentifier,
        }
    end

    local priority = Config.FrameworkPriority or { 'qbox', 'qb', 'esx', 'standalone' }
    for _, name in ipairs(priority) do
        local factory = adapters[name]
        if factory then
            local adapter = factory()
            if adapter then
                return adapter
            end
        end
    end

    return adapters.standalone()
end

local Adapter = buildAdapter()
local SNAP, RATE, DIRTY = {}, {}, {}
local hasOx = GetResourceState('oxmysql') == 'started' and MySQL ~= nil
local persistenceTable = Config.Persistence and (Config.Persistence.table or 'survival_states') or 'survival_states'

local function clamp(v, mn, mx)
    if type(v) ~= 'number' then return v end
    if mn and v < mn then return mn end
    if mx and v > mx then return mx end
    return v
end

local function clampNamespace(ns, delta)
    local rules = Config.Clamps and Config.Clamps[ns]
    if not rules then return delta end
    local out = {}
    for k, v in pairs(delta) do
        local r = rules[k]
        if r and type(v) == 'number' then
            out[k] = clamp(v, r[1], r[2])
        else
            out[k] = v
        end
    end
    return out
end

local function mergeDelta(dst, src)
    for k, v in pairs(src) do
        if type(v) == 'table' and type(dst[k]) == 'table' then
            mergeDelta(dst[k], v)
        else
            dst[k] = v
        end
    end
end

local function ensureSnapshot(src)
    if not SNAP[src] then
        SNAP[src] = {
            identifiers = Adapter.getIdentifier(src),
            ts = os.time(),
        }
        for _, ns in ipairs(Config.Namespaces or {}) do
            SNAP[src][ns] = SNAP[src][ns] or {}
        end
    end
    return SNAP[src]
end

local function setStateBag(src, ns, data)
    local ply = Player(src)
    if not ply or not ply.state then return end
    ply.state:set(('survival:%s'):format(ns), data, true)
end

local function exceededRate(src, ns, payloadLen)
    RATE[src] = RATE[src] or {}
    local now = GetGameTimer()
    local win = (Config.Rate and Config.Rate.windowMs) or 1000
    local bucket = RATE[src][ns]
    if not bucket or now - bucket.t0 > win then
        RATE[src][ns] = { t0 = now, n = 0, bytes = 0 }
        bucket = RATE[src][ns]
    end
    bucket.n = bucket.n + 1
    bucket.bytes = bucket.bytes + (payloadLen or 0)
    if Config.Rate then
        if bucket.n > (Config.Rate.maxMsgs or 20) then return true end
        if bucket.bytes > (Config.Rate.maxPayloadBytes or 2048) then return true end
    end
    return false
end

local function ensureSchema()
    if not hasOx or not Config.Persistence or Config.Persistence.enabled == false then return end
    local sql = ([[
        CREATE TABLE IF NOT EXISTS `%s` (
            `identifier` VARCHAR(128) NOT NULL,
            `snapshot` LONGTEXT NOT NULL,
            `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY (`identifier`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]]):format(persistenceTable)
    MySQL.query.await(sql)
end

local function persistOne(src)
    local snap = SNAP[src]
    if not snap or Config.Persistence and Config.Persistence.enabled == false then return end
    snap.identifiers = Adapter.getIdentifier(src)
    if hasOx then
        MySQL.prepare.await(([[ 
            INSERT INTO `%s` (identifier, snapshot)
            VALUES (?, ?)
            ON DUPLICATE KEY UPDATE snapshot = VALUES(snapshot), updated_at = CURRENT_TIMESTAMP
        ]]):format(persistenceTable), {
            snap.identifiers,
            json.encode(snap),
        })
    else
        local prefix = Config.Persistence and Config.Persistence.fileFallbackPrefix or 'snapshot_'
        local path = ('%s%s.json'):format(prefix, snap.identifiers)
        SaveResourceFile(RESOURCE, path, json.encode(snap), -1)
    end
end

local function flushDirty()
    for src in pairs(DIRTY) do
        persistOne(src)
        DIRTY[src] = nil
    end
end

CreateThread(function()
    while true do
        local interval = (Config.Persistence and Config.Persistence.flushIntervalSec or 30) * 1000
        Wait(interval)
        flushDirty()
    end
end)

local function registerNamespace(ns)
    local evt = ('survival:%s:update'):format(ns)
    RegisterNetEvent(evt, function(delta)
        local src = source
        if type(src) ~= 'number' or src <= 0 then return end
        if type(delta) ~= 'table' then return end
        local payload = json.encode(delta)
        if exceededRate(src, ns, #payload) then return end

        local snap = ensureSnapshot(src)
        snap[ns] = snap[ns] or {}
        local clamped = clampNamespace(ns, delta)

        local before = json.encode(snap[ns])
        mergeDelta(snap[ns], clamped)
        snap.ts = os.time()

        local after = json.encode(snap[ns])
        if before ~= after then
            setStateBag(src, ns, snap[ns])
            DIRTY[src] = true
            if Config.BroadcastEnabled then
                TriggerClientEvent(('survival:%s:broadcast'):format(ns), -1, src, snap[ns])
            end
        end
    end)
    dbg('registered %s for framework=%s', evt, Adapter.name)
end

for _, ns in ipairs(Config.Namespaces or {}) do
    registerNamespace(ns)
end

AddEventHandler('playerConnecting', function()
    local src = source
    if type(src) ~= 'number' or src <= 0 then return end
    ensureSnapshot(src)
end)

AddEventHandler('playerDropped', function()
    local src = source
    if type(src) ~= 'number' or src <= 0 then return end
    flushDirty()
    if SNAP[src] then
        persistOne(src)
        SNAP[src], RATE[src] = nil, nil
    end
end)

RegisterNetEvent('survival:hub:requestSync', function()
    local src = source
    if type(src) ~= 'number' or src <= 0 then return end
    local snap = ensureSnapshot(src)
    for _, ns in ipairs(Config.Namespaces or {}) do
        setStateBag(src, ns, snap[ns])
    end
end)

exports('getState', function(src)
    if type(src) ~= 'number' then return nil end
    return SNAP[src]
end)

exports('update', function(src, ns, delta)
    if type(src) ~= 'number' or type(ns) ~= 'string' or type(delta) ~= 'table' then return false end
    ns = ns:lower()
    local allowed = false
    for _, name in ipairs(Config.Namespaces or {}) do
        if name == ns then allowed = true break end
    end
    if not allowed then return false end

    local snap = ensureSnapshot(src)
    snap[ns] = snap[ns] or {}
    local clamped = clampNamespace(ns, delta)
    mergeDelta(snap[ns], clamped)
    setStateBag(src, ns, snap[ns])
    DIRTY[src] = true
    return true
end)

CreateThread(function()
    ensureSchema()
    dbg('initialised hub adapter=%s oxmysql=%s', Adapter.name, tostring(hasOx))
end)
