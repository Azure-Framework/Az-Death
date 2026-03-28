fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'Az-Death'
author 'Azure-Framework'
description 'Death / downed system with NUI UI (Az-Framework compatible)'
version '1.0.0'

shared_scripts {
  '@ox_lib/init.lua',
  'config.lua'
}

ui_page 'html/index.html'

files {
  'html/index.html',
  'html/**/*'
}

client_scripts {
  'client.lua',
  'source/clie/client.lua',
  'source/veh/client.lua',

  -- ALWAYS LAST so it can reclaim commands
  'aiems.lua'
}

server_scripts {
  'server.lua',
  'source/serv/server.lua'
}
