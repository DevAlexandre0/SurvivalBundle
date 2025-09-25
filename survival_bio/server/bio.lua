local debug = function(...) if Config.Debug then print(('%s %s'):format(Config.DebugPrefix, table.concat({...}, ' '))) end end

-- Utility
local function clamp01(x) return math.max(0.0, math.min(100.0, x)) end
local function nearly(a,b,eps) return math.abs(a-b) <= (eps or Config.DeltaEpsilon) end

-- In-memory cache
local Bio = {}  -- [source] = {infection, parasite, disease, immunity, metabolism, stomach, ts}

-- Adapter: Qbox-first → QBCore
local Adapter = require('adapters/qb')  -- fixed, no ESX/ox/standalone

-- Persistence
local function dbReady()
    return Config.Persistence.enabled and GetResourceState('oxmysql') == 'started'
end

local function dbEnsure()
    if not dbReady() or _BIO_DB_READY then return end
    local q = ([[
        CREATE TABLE IF NOT EXISTS `%s` (
          identifier VARCHAR(64) NOT NULL,
          infection FLOAT NOT NULL,
          parasite  FLOAT NOT NULL,
          disease   FLOAT NOT NULL,
          immunity  FLOAT NOT NULL,
          metabolism FLOAT NOT NULL,
          stomach   FLOAT NOT NULL,
          PRIMARY KEY (identifier)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]]):format(Config.Persistence.table)
    exports.oxmysql:execute(q, {})
    _BIO_DB_READY = true
end

local function idOf(src)
    return Adapter.getIdentifier(src) or ('license:%s'):format(GetPlayerIdentifierByType(src,'license') or tostring(src))
end

local function dbLoad(src)
    if not dbReady() then return nil end
    dbEnsure()
    local identifier = idOf(src)
    local row = MySQL.single.await(('SELECT * FROM `%s` WHERE identifier = ?'):format(Config.Persistence.table), {identifier})
    return row
end

local function dbSave(src, state)
    if not dbReady() then return end
    dbEnsure()
    local identifier = idOf(src)
    MySQL.insert.await(
        ('INSERT INTO `%s` (identifier,infection,parasite,disease,immunity,metabolism,stomach) VALUES (?,?,?,?,?,?,?) ON DUPLICATE KEY UPDATE infection=VALUES(infection), parasite=VALUES(parasite), disease=VALUES(disease), immunity=VALUES(immunity), metabolism=VALUES(metabolism), stomach=VALUES(stomach)'):format(Config.Persistence.table),
        {identifier, state.infection, state.parasite, state.disease, state.immunity, state.metabolism, state.stomach}
    )
end

-- Initialize state
local function defaultState()
    return {
        infection = 0.0, parasite = 0.0, disease = 0.0, immunity = 50.0,
        metabolism = 100.0, stomach = 0.0, ts = os.time()
    }
end

local function pushState(src, st, force)
    local p = Player(src); if not p then return end
    local cur = p.state.bio or {}
    local changed =
        (not nearly(cur.infection or -1, st.infection)) or
        (not nearly(cur.parasite  or -1, st.parasite )) or
        (not nearly(cur.disease   or -1, st.disease  )) or
        (not nearly(cur.immunity  or -1, st.immunity )) or
        (not nearly(cur.metabolism or -1, st.metabolism)) or
        (not nearly(cur.stomach   or -1, st.stomach  ))
    if changed or force then
        p.state:set('bio', {
            infection = st.infection, parasite = st.parasite, disease = st.disease,
            immunity = st.immunity, metabolism = st.metabolism, stomach = st.stomach
        }, true)
        if Config.Broadcast then
            TriggerClientEvent('survival:bio:progress', src, p.state.bio)
        end
    end
end

-- Exposure intake from other systems (e.g., dirty water, raw food, contaminated zones)
RegisterNetEvent('survival:bio:exposure', function(payload)
    local src = source
    if type(payload) ~= 'table' then return end
    local st = Bio[src]; if not st then return end
    local dirtyWater = tonumber(payload.dirtyWater or 0.0) or 0.0
    local rawFood    = tonumber(payload.rawFood or 0.0) or 0.0
    local woundInfx  = tonumber(payload.woundInfection or 0.0) or 0.0
    st.infection = clamp01(st.infection + dirtyWater * 0.2 + woundInfx * 0.4)
    st.parasite  = clamp01(st.parasite  + rawFood * 0.4 + dirtyWater * 0.1)
    pushState(src, st, false)
    if Config.Debug then debug(('exposure dirty=%.2f raw=%.2f wound=%.2f'):format(dirtyWater, rawFood, woundInfx)) end
    TriggerClientEvent('survival:bio:exposed', src, {dirtyWater=dirtyWater, rawFood=rawFood, wound=woundInfx})
end)

-- Treatment hook
RegisterNetEvent('survival:bio:treated', function(payload)
    local src = source
    local st = Bio[src]; if not st then return end
    local typ = tostring(payload and payload.type or 'generic')
    if typ == 'antibiotic' then st.infection = clamp01(st.infection - 25.0) end
    if typ == 'antiparasitic' then st.parasite = clamp01(st.parasite - 25.0) end
    if typ == 'antipyretic' then st.disease = clamp01(st.disease - 15.0) end
    st.immunity = clamp01(st.immunity + 10.0)
    pushState(src, st, true)
end)

-- Exports
exports('GetBioState', function(src) return (Bio[src] and table.clone and table.clone(Bio[src])) or Bio[src] end)
exports('SetBioFlag', function(src, key, val)
    local st = Bio[src]; if not st then return false end
    if st[key] == nil then return false end
    st[key] = clamp01(tonumber(val) or st[key])
    pushState(src, st, true)
    return true
end)
exports('ApplyBioExposure', function(src, payload)
    TriggerClientEvent('survival:bio:requestExposure', src, payload or {})
end)

-- Upstream pulls (read-only): rely on hub cache or state bags
local function snapshotUpstream(src)
    local p = Player(src); if not p then return {} end
    local needs = p.state.needs or {}
    local health= p.state.health or {}
    local env   = p.state.env   or {}
    return { needs=needs, health=health, env=env }
end

-- Progression tick
local function tickPlayer(src)
    local st = Bio[src]; if not st then return end
    local up = snapshotUpstream(src)

    local infectedRisk  = (up.health and (up.health.bleeding or 0) or 0) + (up.env and (up.env.wetness or 0) or 0)
    local parasiteRisk  = ((up.needs and (100 - (up.needs.water or 100))) or 0) * 0.01
    local sickLoad      = (st.infection * 0.5 + st.parasite * 0.4) / 100.0

    st.infection = clamp01(st.infection + Config.Coeff.infectionBase * (1.0 + infectedRisk/100.0) - st.immunity * 0.001)
    st.parasite  = clamp01(st.parasite  + Config.Coeff.parasiteBase  * (1.0 + parasiteRisk) - st.immunity * 0.0005)
    st.disease   = clamp01(st.disease + Config.Coeff.diseaseProg * (0.5 + sickLoad) - st.immunity * 0.0004)

    local immuneDelta = Config.Coeff.immunityGain
    immuneDelta = immuneDelta - (sickLoad * Config.Coeff.immunityLoss)
    st.immunity = clamp01(st.immunity + immuneDelta)

    st.metabolism = clamp01(100.0 * Config.Coeff.metabolismBase * (1.0 - sickLoad*0.5))
    st.stomach = clamp01(st.stomach - (Config.Coeff.stomachEmpty / 60.0)) -- per second

    if st.disease >= Config.Threshold.Symptomatic then
        TriggerClientEvent('survival:bio:progress', src, { symptomatic = true, disease = st.disease })
    end

    pushState(src, st, false)
end

-- Global tick
CreateThread(function()
    while true do
        Wait(Config.ServerTickMs)
        for src, _ in pairs(Bio) do
            if GetPlayerPed(src) ~= 0 then
                tickPlayer(src)
            end
        end
    end
end)

-- Save timer (optional)
CreateThread(function()
    while true do
        Wait((Config.Persistence.saveIntervalSec or 60) * 1000)
        if dbReady() then
            for src, st in pairs(Bio) do dbSave(src, st) end
        end
    end
end)

-- Lifecycle
AddEventHandler('playerJoining', function(src)
    local st = defaultState()
    if dbReady() then
        local row = dbLoad(src)
        if row then
            st.infection = row.infection; st.parasite=row.parasite; st.disease=row.disease
            st.immunity = row.immunity; st.metabolism=row.metabolism; st.stomach=row.stomach
        end
    end
    Bio[src] = st
    pushState(src, st, true)
    debug('init player', tostring(src))
end)

AddEventHandler('playerDropped', function()
    local src = source
    local st = Bio[src]
    if st and dbReady() then dbSave(src, st) end
    Bio[src] = nil
end)

AddEventHandler('onResourceStart', function(res)
    if res == GetCurrentResourceName() then
        if dbReady() then dbEnsure() end
        debug('resource started')
    end
end)
