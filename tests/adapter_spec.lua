package.path = 'survival_shared/?.lua;' .. package.path

local events = {}

function AddEventHandler(name, handler)
  events[name] = handler
end

function print() end -- silence

_G.GetResourceState = function(_) return 'missing' end
_G.exports = {}
_G.IsPlayerAceAllowed = function() return true end

local framework = require('framework')

local function assertEquals(a, b, msg)
  if a ~= b then
    error((msg or 'assert failed') .. string.format(' expected %s got %s', tostring(b), tostring(a)))
  end
end

-- Standalone fallback
local adapter = SurvivalFramework.buildAdapter({ priority = { 'standalone' } })
assertEquals(adapter.name, 'standalone', 'standalone adapter selected')

-- Mock qbox export
exports['qbx_core'] = {
  GetPlayer = function(_, src)
    if src == 5 then
      return { PlayerData = { citizenid = 'CITZ' } }
    end
  end
}
GetResourceState = function(name)
  if name == 'qbx_core' then return 'started' end
  return 'missing'
end
local qbAdapter = SurvivalFramework.buildAdapter({ priority = { 'qbox', 'standalone' } })
assertEquals(qbAdapter.name, 'qbox', 'qbox adapter selected')
assertEquals(qbAdapter.getIdentifier(5), 'qb:CITZ', 'identifier resolved')

print('adapter tests passed')
