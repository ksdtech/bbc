bbc
===

Blackboard Connect uploader (lua)

Converts data from PowerSchool export to Blackboard Connect contacts import files.

Requires lua 5.1 or 5.2 and lib-cURL library from http://msva.github.com/lua-curl/

Build lua-curl on OS X

    export LUA_CFLAGS="-I/usr/local/include"
    export LUA_LIBS="-L/usr/local/lib -lm -llua"
    ./configure  --with-cmoddir=/usr/local/lib/lua/5.2
    emacs config.status, add “-DLUA_COMPAT_ALL” to DEFS macro
    make
    sudo make install

Copy app_config.lua.sample to app_config.lua and edit global variables,
specifying source directory of PowerSchool files and working directory
for Blackboard Connect files and results.

Then: 

    lua bbc.lua
