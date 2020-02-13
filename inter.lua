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
	local users_str = read_exec(string.format([[cipgwcli dump]]))
	local rows = string.split(users_str, "\n")
	local fp = io.open(dumppath, 'wb')
	fp:write("begin transaction;\n")
	for _, v in pairs(rows) do
		local data = string.split(v, ",")
		-- data[1] mac
		-- data[2] login_time
		-- data[3] session
		-- data[4] tx
		-- data[5] rx
		fp:write("insert into rawacct (user_mac, login_time, session_time, type, tx, rx, others) values ('"..data[1].."',"..data[2]..","..data[3]..", 3, "..data[4]..", "..data[5]..", '');\n")
	end
        fp:write("commit;\n")
	fp.close()

	read_exec(string.format([[sqlite -init /tmp/timeout.sql %s < %s >/dev/null 2>&1]], rawdbpath, dumppath))

end

function query_from_raw()
	local output = read_exec(string.format([[sqlite -init /tmp/timeout.sql %s "select * from rawacct order by user_mac, login_time, session_time asc" </dev/null]], rawdbpath))
	print(output)
end

--dump_usage()

query_from_raw()


