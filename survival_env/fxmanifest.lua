fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'survival_env'
description 'Headless environment pipeline (weather/time/wetness/wind/radiation) - Qbox only'
author 'FiveM Realistic Survival Bundle'

shared_scripts {
  'config.lua'
}

client_scripts {
  'client/env.lua'
}

server_scripts {
  '@oxmysql/lib/MySQL.lua', -- optional; safe if missing
  'server/env.lua'
}

provides { 'survival_env' }
