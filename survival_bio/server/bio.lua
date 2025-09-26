local Adapter = SurvivalFramework.buildAdapter({
    priority = Config.Framework and Config.Framework.priority,
    permissions = Config.Framework and Config.Framework.permissions
})

local function debugLog(fmt, ...)
    if not Config.Debug then return end
    if select('#', ...) > 0 then
        print(('%s %s'):format(Config.DebugPrefix or '[BIO]', fmt:format(...)))
    else
        print(('%s %s'):format(Config.DebugPrefix or '[BIO]', tostring(fmt)))
    end
end

local function ensureSource(src)
    if type(src) ~= 'number' or src <= 0 then
        debugLog('rejected event from invalid source=%s', tostring(src))
        return false
    end
    return true
end

local function clamp01(x) return math.max(0.0, math.min(100.0, x)) end
local function nearly(a, b, eps) return math.abs(a - b) <= (eps or Config.DeltaEpsilon) end

local Bio = {}
local pendingSave = {}
local hasOx = GetResourceState and GetResourceState('oxmysql') == 'started' and MySQL ~= nil

local function dbReady()
    return Config.Persistence.enabled and hasOx
end

local function dbEnsure()
    if not dbReady() or Bio._schemaReady then return end
    MySQL.query.await(([[
        CREATE TABLE IF NOT EXISTS `%s` (
            identifier VARCHAR(64) NOT NULL,
            infection FLOAT NOT NULL,
            parasite  FLOAT NOT NULL,
            disease   FLOAT NOT NULL,
            immunity  FLOAT NOT NULL,
            metabolism FLOAT NOT NULL,
            stomach   FLOAT NOT NULL,
            ts INT NOT NULL,
            PRIMARY KEY (identifier)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]]):format(Config.Persistence.table))
    Bio._schemaReady = true
end

local function idOf(src)
    return Adapter.getIdentifier(src) or ('license:%s'):format(GetPlayerIdentifierByType(src, 'license') or tostring(src))
end

local function dbLoad(src)
    if not dbReady() then return nil end
    dbEnsure()
    local identifier = idOf(src)
    return MySQL.single.await(('SELECT * FROM `%s` WHERE identifier = ?'):format(Config.Persistence.table), { identifier })
end

local function dbSave(identifier, state)
    if not dbReady() or not identifier then return end
    dbEnsure()
    pendingSave[identifier] = state
end

CreateThread(function()
    while true do
        Wait((Config.Persistence.saveIntervalSec or 60) * 1000)
        if dbReady() and next(pendingSave) ~= nil then
            local batch = pendingSave
            pendingSave = {}
            for identifier, state in pairs(batch) do
                MySQL.prepare.await(([[
                    INSERT INTO `%s` (identifier, infection, parasite, disease, immunity, metabolism, stomach, ts)
                    VALUES (?,?,?,?,?,?,?,?)
                    ON DUPLICATE KEY UPDATE
                        infection = VALUES(infection),
                        parasite  = VALUES(parasite),
                        disease   = VALUES(disease),
                        immunity  = VALUES(immunity),
                        metabolism= VALUES(metabolism),
                        stomach   = VALUES(stomach),
                        ts        = VALUES(ts)
                ]]):format(Config.Persistence.table), {
                    identifier,
                    state.infection,
                    state.parasite,
                    state.disease,
                    state.immunity,
                    state.metabolism,
                    state.stomach,
                    state.ts or os.time(),
                })
            end
        end
    end
end)

local function defaultState()
    return {
        infection = 0.0,
        parasite = 0.0,
        disease = 0.0,
        immunity = 50.0,
        metabolism = 100.0,
        stomach = 0.0,
        ts = os.time(),
    }
end

local function pushState(src, st, force)
    local ply = Player(src)
    if not ply or not ply.state then return end
    local current = ply.state.bio or {}
    local changed =
        (not nearly(current.infection or -1, st.infection)) or
        (not nearly(current.parasite  or -1, st.parasite )) or
        (not nearly(current.disease   or -1, st.disease  )) or
        (not nearly(current.immunity  or -1, st.immunity )) or
        (not nearly(current.metabolism or -1, st.metabolism)) or
        (not nearly(current.stomach   or -1, st.stomach  ))

    if changed or force then
        ply.state:set('bio', {
            infection = st.infection,
            parasite = st.parasite,
            disease = st.disease,
            immunity = st.immunity,
            metabolism = st.metabolism,
            stomach = st.stomach,
            ts = st.ts or os.time()
        }, true)
        if Config.Broadcast then
            TriggerClientEvent('survival:bio:progress', src, ply.state.bio)
        end
    end
end

RegisterNetEvent('survival:bio:exposure', function(payload)
    local src = source
    if not ensureSource(src) then return end
    if type(payload) ~= 'table' then return end
    local st = Bio[src]
    if not st then return end

    local dirtyWater = clamp01(tonumber(payload.dirtyWater) or 0.0)
    local rawFood = clamp01(tonumber(payload.rawFood) or 0.0)
    local woundInfx = clamp01(tonumber(payload.woundInfection) or 0.0)

    st.infection = clamp01(st.infection + dirtyWater * 0.2 + woundInfx * 0.4)
    st.parasite  = clamp01(st.parasite  + rawFood * 0.4 + dirtyWater * 0.1)
    st.ts = os.time()
    pushState(src, st, false)

    if Config.Debug then
        debugLog('exposure src=%d dirty=%.2f raw=%.2f wound=%.2f', src, dirtyWater, rawFood, woundInfx)
    end
    TriggerClientEvent('survival:bio:exposed', src, {
        dirtyWater = dirtyWater,
        rawFood = rawFood,
        wound = woundInfx,
    })
end)

RegisterNetEvent('survival:bio:treated', function(payload)
    local src = source
    if not ensureSource(src) then return end
    if type(payload) ~= 'table' then return end
    local st = Bio[src]
    if not st then return end

    if not Adapter.hasPermission(src, 'medical') then
        debugLog('blocked treatment from %d (no permission)', src)
        return
    end

    local typ = tostring(payload.type or 'generic')
    if typ == 'antibiotic' then st.infection = clamp01(st.infection - 25.0) end
    if typ == 'antiparasitic' then st.parasite = clamp01(st.parasite - 25.0) end
    if typ == 'antipyretic' then st.disease = clamp01(st.disease - 15.0) end
    st.immunity = clamp01(st.immunity + 10.0)
    st.ts = os.time()
    pushState(src, st, true)
end)

exports('GetBioState', function(src)
    local st = Bio[src]
    if not st then return nil end
    return {
        infection = st.infection,
        parasite = st.parasite,
        disease = st.disease,
        immunity = st.immunity,
        metabolism = st.metabolism,
        stomach = st.stomach,
        ts = st.ts,
    }
end)

exports('SetBioFlag', function(src, key, val)
    local st = Bio[src]
    if not st or st[key] == nil then return false end
    st[key] = clamp01(tonumber(val) or st[key])
    st.ts = os.time()
    pushState(src, st, true)
    dbSave(idOf(src), st)
    return true
end)

exports('ApplyBioExposure', function(src, payload)
    if type(src) ~= 'number' or src <= 0 then return false end
    TriggerClientEvent('survival:bio:requestExposure', src, payload or {})
    return true
end)

local function snapshotUpstream(src)
    local ply = Player(src)
    if not ply or not ply.state then return {} end
    return {
        needs = ply.state.needs or {},
        health = ply.state.health or {},
        env = ply.state.env or {},
    }
end

local function tickPlayer(src)
    local st = Bio[src]
    if not st then return end
    local up = snapshotUpstream(src)

    local infectedRisk = (up.health and (up.health.bleed or up.health.bleeding or 0) or 0) + (up.env and (up.env.wetness or 0) or 0)
    local parasiteRisk = ((up.needs and (100 - (up.needs.water or 100))) or 0) * 0.01
    local sickLoad = (st.infection * 0.5 + st.parasite * 0.4) / 100.0

    st.infection = clamp01(st.infection + Config.Coeff.infectionBase * (1.0 + infectedRisk / 100.0) - st.immunity * 0.001)
    st.parasite  = clamp01(st.parasite  + Config.Coeff.parasiteBase  * (1.0 + parasiteRisk) - st.immunity * 0.0005)
    st.disease   = clamp01(st.disease + Config.Coeff.diseaseProg * (0.5 + sickLoad) - st.immunity * 0.0004)

    local immuneDelta = Config.Coeff.immunityGain - (sickLoad * Config.Coeff.immunityLoss)
    st.immunity = clamp01(st.immunity + immuneDelta)

    st.metabolism = clamp01(100.0 * Config.Coeff.metabolismBase * (1.0 - sickLoad * 0.5))
    st.stomach = clamp01(st.stomach - (Config.Coeff.stomachEmpty / 60.0))
    st.ts = os.time()

    if st.disease >= Config.Threshold.Symptomatic then
        TriggerClientEvent('survival:bio:progress', src, { symptomatic = true, disease = st.disease })
    end

    pushState(src, st, false)
    dbSave(idOf(src), st)
end

CreateThread(function()
    while true do
        Wait(Config.ServerTickMs)
        for src in pairs(Bio) do
            if GetPlayerPed(src) ~= 0 then
                tickPlayer(src)
            end
        end
    end
end)

local function initPlayer(src)
    if type(src) ~= 'number' or src <= 0 then return end
    local st = defaultState()
    if dbReady() then
        local row = dbLoad(src)
        if row then
            st.infection = row.infection
            st.parasite = row.parasite
            st.disease = row.disease
            st.immunity = row.immunity
            st.metabolism = row.metabolism
            st.stomach = row.stomach
            st.ts = row.ts or os.time()
        end
    end
    Bio[src] = st
    pushState(src, st, true)
    debugLog('initialised player %d adapter=%s', src, Adapter.name or 'unknown')
end

AddEventHandler('playerJoining', function(src)
    initPlayer(src)
end)

Adapter.onPlayerLoaded(function(src)
    initPlayer(src)
end)

local function handleDrop(src)
    if type(src) ~= 'number' or src <= 0 then return end
    local st = Bio[src]
    if st then
        dbSave(idOf(src), st)
    end
    Bio[src] = nil
end

Adapter.onPlayerDropped(handleDrop)
AddEventHandler('playerDropped', function()
    handleDrop(source)
end)

AddEventHandler('onResourceStart', function(res)
    if res ~= GetCurrentResourceName() then return end
    if dbReady() then dbEnsure() end
    debugLog('resource started adapter=%s hasOx=%s', Adapter.name or 'unknown', tostring(hasOx))
end)
