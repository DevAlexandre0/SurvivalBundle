fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'survival_movement'
author 'FiveM Realistic Survival Bundle'
version '0.1.1'
description 'Headless movement module: stamina + oxygen (Qbox only)'

shared_scripts {
  '@survival_shared/framework.lua',
  'config.lua'
}

client_scripts {
  'client/movement.lua'
}

server_scripts {
  '@oxmysql/lib/MySQL.lua', -- required if you use persistence
  'server/movement.lua'
}

provide 'survival_movement'
