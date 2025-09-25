fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'survival_needs'
author 'Realistic Survival Bundle'
description 'Headless needs engine: food, water, energy, stress, poop, pee'
version '0.1.1'

shared_scripts {
  'config.lua'
}

client_scripts {
  'client/main.lua'
}

server_scripts {
  '@oxmysql/lib/MySQL.lua',
  'server/persist.lua',
  'server/adapters/qb.lua',
  'server/main.lua'
}

provides { 'survival_needs' }
