fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'survival_health'
description 'Headless health/wound/bleeding simulation (server-authoritative)'
author 'YourTeam'
version '0.1.0'

shared_scripts {
  '@ox_lib/init.lua',
  'config.lua',
  'shared/health_shared.lua'
}

client_scripts {
  'client/health.lua'
}

server_scripts {
  'server/adapters/qb.lua',
  'server/health.lua'
}

provides { 'survival_health' }
