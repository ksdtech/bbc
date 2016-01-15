bbc - Blackboard Connect Uploader
=================================
Converts data from PowerSchool export to Blackboard Connect contacts import files.

bbc.py (Python 2.7 version)
===========================
Requires pycurl package

Todo (Python)
-------------
Put these global variables into command line options:
  
verboseFlag
regFormStartDate
sourceDir
uploadDir
strUserName
strUserPass
destURL
allPreRegs
allGraduates
preRegGroups
regStatusGroups
# 0 - do not add these groups
# 1 - check pre-regs (before EOY)
# 2 - check active (after EOY)

Send success/failure by SMTP.

bbc.lua (lua version)
=====================
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

Todo (lua)
----------
Update existing work in send_status.lua to send results of upload.
send_status.lua requires the following lua libraries:

- socket.smtp
- mime
- ltn12
- lfs
