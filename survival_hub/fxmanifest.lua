fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'survival_hub'
description 'Qbox-only survival hub: state bus + persistence'
version '0.3.0'

shared_scripts {
  'config.lua'
}

server_scripts {
  '@oxmysql/lib/MySQL.lua',
  'server/hub.lua'
}

client_scripts {
  'client/hub.lua'
}

provides { 'survival_hub' }