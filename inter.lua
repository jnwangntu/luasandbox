package.path = package.path .. ";/ramfs/bin/?.lua"
require("custom")
local rex = require("rex_pcre")
local lfs = require("lfs")
-- for infinite loop
local assert, print = assert, print
local pairs = pairs
local inspect = require("inspect")
local cjson = require("cjson")

local rawdbpath="/tmp/nms/rawdb.db"
local dumppath="/tmp/nms/dumprows"

function dump_usage()
	local ostime=os.time(os.date("!*t"))
	local users_str = read_exec(string.format([[cipgwcli list]]))
	local rows = string.split(users_str, "\n")
	local fp = io.open(dumppath, 'wb')
	fp:write("begin transaction;\n")
	for _, v in pairs(rows) do
		local data = string.split(v, ",")
		-- data[1] name
		-- data[2] mac
		-- data[5] session
		-- data[9] tx
		-- data[10] rx
		-- data[11] login_time , use it with session_time
		data[11]=ostime-data[5]
		fp:write("insert into rawacct (user_mac, login_time, update_time, type, tx, rx, others) values ('"..data[2].."',"..data[11]..","..ostime..", 3, "..data[9]..", "..data[10]..", '');\n")
	end
        fp:write("commit;\n")
	fp.close()
	
	read_exec(string.format([[sqlite -init /tmp/timeout.sql %s < %s >/dev/null 2>&1]], rawdbpath, dumppath))
	
end

function query_from_raw()
	local file = assert(io.popen('sqlite -init /tmp/timeout.sql /tmp/rawdb.db "select * from rawacct order by user_mac, login_time, update_time asc" </dev/null','r'))
	local output = file:read('*all')
	file:close()
	print(output)
end

dump_usage()


