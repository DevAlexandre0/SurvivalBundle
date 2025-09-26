local RESOURCE = GetCurrentResourceName()

local Adapter = SurvivalFramework.buildAdapter({
    priority = Config.FrameworkPriority,
    permissions = Config.AdapterPermissions
})

local SNAP, RATE, DIRTY = {}, {}, {}
local hasOx = GetResourceState and GetResourceState('oxmysql') == 'started' and MySQL ~= nil
local persistenceTable = Config.Persistence and (Config.Persistence.table or 'survival_states') or 'survival_states'

local function dbg(fmt, ...)
    if not Config.Debug then return end
    local prefix = Config.LogPrefix or ('[' .. RESOURCE .. ']')
    if select('#', ...) > 0 then
        print(('%s %s'):format(prefix, fmt:format(...)))
    else
        print(('%s %s'):format(prefix, tostring(fmt)))
    end
end

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
        local rule = rules[k]
        if rule and type(v) == 'number' then
            out[k] = clamp(v, rule[1], rule[2])
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

local function setStateBag(src, ns, data)
    local ply = Player(src)
    if not ply or not ply.state then return end
    ply.state:set(('survival:%s'):format(ns), data, true)
end

local function ensureSnapshot(src)
    if not SNAP[src] then
        SNAP[src] = {
            identifier = Adapter.getIdentifier(src),
            ts = os.time()
        }
        for _, ns in ipairs(Config.Namespaces or {}) do
            SNAP[src][ns] = {}
        end
    end
    return SNAP[src]
end

local function exceededRate(src, ns, payloadLen)
    RATE[src] = RATE[src] or {}
    local now = GetGameTimer()
    local win = (Config.Rate and Config.Rate.windowMs) or 1000
    local bucket = RATE[src][ns]
    if not bucket or now - bucket.t0 > win then
        bucket = { t0 = now, n = 0, bytes = 0 }
        RATE[src][ns] = bucket
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
    MySQL.query.await(([[
        CREATE TABLE IF NOT EXISTS `%s` (
            `identifier` VARCHAR(128) NOT NULL,
            `snapshot` LONGTEXT NOT NULL,
            `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY (`identifier`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]]):format(persistenceTable))
end

local function loadSnapshot(identifier)
    if not identifier then return nil end
    if hasOx and (not Config.Persistence or Config.Persistence.enabled ~= false) then
        local row = MySQL.single.await(([[SELECT snapshot FROM `%s` WHERE identifier = ? LIMIT 1]]):format(persistenceTable), { identifier })
        if row and row.snapshot then
            local ok, decoded = pcall(json.decode, row.snapshot)
            if ok and decoded then
                return decoded
            end
        end
    else
        local prefix = Config.Persistence and Config.Persistence.fileFallbackPrefix or 'survival_state_'
        local path = ('%s%s.json'):format(prefix, identifier)
        local blob = LoadResourceFile(RESOURCE, path)
        if blob then
            local ok, decoded = pcall(json.decode, blob)
            if ok and decoded then return decoded end
        end
    end
    return nil
end

local function persistSnapshot(src)
    local snap = SNAP[src]
    if not snap then return end
    snap.identifier = Adapter.getIdentifier(src)
    if not snap.identifier then return end

    if hasOx and (not Config.Persistence or Config.Persistence.enabled ~= false) then
        MySQL.prepare.await(([[
            INSERT INTO `%s` (identifier, snapshot)
            VALUES (?, ?)
            ON DUPLICATE KEY UPDATE snapshot = VALUES(snapshot), updated_at = CURRENT_TIMESTAMP
        ]]):format(persistenceTable), {
            snap.identifier,
            json.encode(snap)
        })
    else
        local prefix = Config.Persistence and Config.Persistence.fileFallbackPrefix or 'survival_state_'
        local path = ('%s%s.json'):format(prefix, snap.identifier)
        SaveResourceFile(RESOURCE, path, json.encode(snap), -1)
    end
end

local function flushDirty()
    for src in pairs(DIRTY) do
        persistSnapshot(src)
        DIRTY[src] = nil
    end
end

CreateThread(function()
    ensureSchema()
    local interval = ((Config.Persistence and Config.Persistence.flushIntervalSec) or 30) * 1000
    while true do
        Wait(interval)
        flushDirty()
    end
end)

local function applySnapshotToState(src)
    local snap = SNAP[src]
    if not snap then return end
    for _, ns in ipairs(Config.Namespaces or {}) do
        if snap[ns] then
            setStateBag(src, ns, snap[ns])
        end
    end
end

local function handleJoin(src)
    if type(src) ~= 'number' or src <= 0 then return end
    local identifier = Adapter.getIdentifier(src)
    local cached = identifier and loadSnapshot(identifier) or nil
    SNAP[src] = cached or ensureSnapshot(src)
    SNAP[src].identifier = identifier
    applySnapshotToState(src)
    dbg('synced join src=%d adapter=%s identifier=%s', src, Adapter.name or 'unknown', tostring(identifier))
end

Adapter.onPlayerLoaded(function(src)
    handleJoin(src)
end)

Adapter.onPlayerDropped(function(src, reason)
    if type(src) ~= 'number' or src <= 0 then return end
    flushDirty()
    if SNAP[src] then
        persistSnapshot(src)
        SNAP[src], RATE[src] = nil, nil
    end
    dbg('player dropped src=%d reason=%s', src, tostring(reason))
end)

AddEventHandler('playerJoining', function(src)
    handleJoin(src)
end)

RegisterNetEvent('survival:hub:requestSync', function()
    local src = source
    if type(src) ~= 'number' or src <= 0 then return end
    ensureSnapshot(src)
    applySnapshotToState(src)
end)

local function registerNamespace(ns)
    local evt = ('survival:%s:update'):format(ns)
    RegisterNetEvent(evt, function(delta)
        local src = source
        if type(src) ~= 'number' or src <= 0 then return end
        if type(delta) ~= 'table' then return end

        local payloadSize = #json.encode(delta)
        if exceededRate(src, ns, payloadSize) then
            dbg('rate limit triggered src=%d ns=%s size=%d', src, ns, payloadSize)
            return
        end

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
    dbg('registered namespace %s via adapter=%s', ns, Adapter.name or 'unknown')
end

for _, ns in ipairs(Config.Namespaces or {}) do
    registerNamespace(ns)
end

exports('getState', function(src)
    if type(src) ~= 'number' then return nil end
    return SNAP[src]
end)

exports('update', function(src, ns, delta)
    if type(src) ~= 'number' or src <= 0 then return false end
    if type(ns) ~= 'string' or type(delta) ~= 'table' then return false end
    ns = ns:lower()

    local allowed = false
    for _, name in ipairs(Config.Namespaces or {}) do
        if name == ns then allowed = true break end
    end
    if not allowed then return false end

    local snap = ensureSnapshot(src)
    snap[ns] = snap[ns] or {}
    mergeDelta(snap[ns], clampNamespace(ns, delta))
    setStateBag(src, ns, snap[ns])
    DIRTY[src] = true
    return true
end)

CreateThread(function()
    dbg('hub initialised adapter=%s hasOx=%s', Adapter.name or 'unknown', tostring(hasOx))
end)
