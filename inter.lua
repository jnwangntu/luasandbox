package.path = package.path .. ";/ramfs/bin/?.lua"
require("custom")
local rex = require("rex_pcre")
local lfs = require("lfs")
-- for infinite loop
local assert, print = assert, print
local pairs = pairs
local inspect = require("inspect")
local cjson = require("cjson")

--local rawdbpath="/tmp/nms/rawdb.db"
local rawdbpath="/tmp/nms/01.db"
local dumppath="/tmp/nms/dumprows"


local TYPE_LOGIN='1'
local TYPE_UPDATE='2'
local TYPE_LOGOUT='3'

local STATUS_INIT=0
local STATUS_ONLINE=1
local STATUS_OFFLINE=2

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
		fp:write("insert into rawacct (user_mac, login_time, session_time, type, tx, rx, others) values ('"..data[1].."',"..data[2]..","..data[3]..", 2, "..data[4]..", "..data[5]..", '');\n")
	end
        fp:write("commit;\n")
	fp.close()

	read_exec(string.format([[sqlite -init /tmp/timeout.sql %s < %s >/dev/null 2>&1]], rawdbpath, dumppath))

end

function createupdate(mac, apmac, tx1, rx1, tx2, rx2)
	local v = {}
	v.mac = mac
	v.apmac = apmac
	v.tx = tx2 - tx1
	v.rx = rx2 - rx1
	return v
end

function query_from_raw()
	local output = read_exec(string.format([[sqlite -init /tmp/timeout.sql %s "select * from rawacct order by user_mac, login_time, session_time, type asc" </dev/null]], rawdbpath))
	local rows = string.split(output, "\n")
	local users = {}
	local update_list = nil

	for _, v in pairs(rows) do
		print(v)
		local cur_row = string.split(v, "|")
		local mac = cur_row[1]
		local lt = cur_row[2]
		local st = cur_row[3]
		local mode = cur_row[4]
		local tx = cur_row[5]
		local rx = cur_row[6]
		local apmac = cur_row[7] or ''

		if users[mac] == nil then
			--print('1-0')
			users[mac] = {}
			users[mac].mac = mac
			users[mac].status = STATUS_INIT
			users[mac].lt = lt
			users[mac].st = st
			users[mac].tx = tx
			users[mac].rx = rx
			users[mac].apmac = apmac
		else
			if users[mac].lt == lt then
				if mode == TYPE_LOGIN then
					--print('1-1-a')
					users[mac].status = STATUS_ONLINE
					users[mac].lt = lt
					users[mac].st = st
					users[mac].tx = tx
					users[mac].rx = rx
					users[mac].apmac = apmac
				elseif mode == TYPE_LOGOUT then
					--print('1-1-b')
					users[mac].status = STATUS_OFFLINE
					local update = createupdate(mac, users[mac].apmac, users[mac].tx, users[mac].rx, tx, rx)
					update_list = { next = update_list, value = update}

					users[mac].lt = lt
					users[mac].st = st
				elseif mode == TYPE_UPDATE then
					--print('1-1-c')
					if users[mac].status == STATUS_ONLINE or users[mac].status == STATUS_INIT then
						local update = createupdate(mac, users[mac].apmac, users[mac].tx, users[mac].rx, tx, rx)
						update_list = { next = update_list, value = update}
						users[mac].lt = lt
						users[mac].st = st
						users[mac].tx = tx
						users[mac].rx = rx
						users[mac].status = STATUS_ONLINE
					end
				end
			else
				--print('1-2')
				if mode == TYPE_LOGIN then
					users[mac].status = STATUS_ONLINE
					users[mac].lt = lt
					users[mac].st = st
					users[mac].tx = tx
					users[mac].rx = rx
					users[mac].apmac = apmac
				elseif mode == TYPE_LOGOUT then
					users[mac].status = STATUS_OFFLINE
					users[mac].lt = lt
					users[mac].st = st
				elseif mode == TYPE_UPDATE then
					users[mac].status = STATUS_ONLINE
					users[mac].lt = lt
					users[mac].st = st
				end

			end
		end
		::continue::
	end

	print("===below are update entry===")
	local l = update_list
    while l do
      print(inspect(l.value))
      l = l.next
    end

    print("====below are account status ====")
    for _, v in pairs(users) do
    	print(inspect(v))
    end

end

--dump_usage()

query_from_raw()


