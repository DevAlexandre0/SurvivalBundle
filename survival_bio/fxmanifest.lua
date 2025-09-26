fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'survival_bio'
author 'YourTeam'
description 'Headless bio module: infection, parasites, diseases, metabolism, stomach. (Qbox/QBCore only)'
version '0.1.1'

shared_scripts {
    '@survival_shared/framework.lua',
    'config.lua',
    'locales/en.lua',
    '@ox_lib/init.lua' -- optional
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',   -- only if Config.Persistence.enabled = true
    'server/bio.lua'
}

client_scripts {
    'client/bio.lua'
}

dependencies { }
