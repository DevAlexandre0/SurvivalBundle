Persist = {}

local hasOx = GetResourceState and GetResourceState('oxmysql') == 'started' and MySQL ~= nil
local useDb = Config.Persistence.Enabled and hasOx
local tableName = Config.Persistence.TableName

local function log(...)
  if Config.Debug then
    print(('%s [persist] ' .. string.rep('%s ', select('#', ...))):format(Config.DebugPrefix, ...))
  end
end

local function ensureSchema()
  if not useDb then
    log('DB disabled or oxmysql missing; using in-memory store')
    return
  end

  -- Create table if not exists
  local createSql = ([[
    CREATE TABLE IF NOT EXISTS `%s` (
      `license`    VARCHAR(80) NOT NULL,
      `data`       JSON NOT NULL,
      `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
      PRIMARY KEY (`license`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
  ]]):format(tableName)
  MySQL.query.await(createSql)

  -- Basic sanity indexes (optional if large scale)
  local idxSql = ([[CREATE INDEX IF NOT EXISTS `%s_updated_at_idx` ON `%s` (`updated_at`);]]):format(tableName, tableName)
  pcall(function() MySQL.query.await(idxSql) end)

  log('schema ensured for table ', tableName)
end

AddEventHandler('onResourceStart', function(res)
  if res ~= GetCurrentResourceName() then return end
  ensureSchema()
end)

-- PUBLIC API
if not useDb then
  -- In-memory fallback
  local mem = {}
  Persist.load = function(license)
    return mem[license]
  end
  Persist.save = function(license, data)
    mem[license] = data
    return true
  end
  Persist.saveAll = function(allData)
    for k, v in pairs(allData or {}) do mem[k] = v end
    return true
  end
else
  Persist.load = function(license)
    if not license then return nil end
    local row = MySQL.single.await(('SELECT `data` FROM `%s` WHERE `license` = ? LIMIT 1'):format(tableName), { license })
    if row and row.data then
      local ok, decoded = pcall(json.decode, row.data)
      return ok and decoded or nil
    end
    return nil
  end

  Persist.save = function(license, data)
    if not license or not data then return false end
    local payload = json.encode(data)
    MySQL.update.await(([[INSERT INTO `%s` (`license`, `data`)
                          VALUES (?, ?)
                          ON DUPLICATE KEY UPDATE `data` = VALUES(`data`)]]
                        ):format(tableName), { license, payload })
    return true
  end

  Persist.saveAll = function(allData)
    if not allData or next(allData) == nil then return true end
    local inserts = {}
    for license, data in pairs(allData) do
      inserts[#inserts+1] = { license, json.encode(data) }
    end
    MySQL.prepare.await(([[INSERT INTO `%s` (`license`, `data`) VALUES (?, ?)
                           ON DUPLICATE KEY UPDATE `data` = VALUES(`data`)]]
                         ):format(tableName), inserts)
    return true
  end
end
