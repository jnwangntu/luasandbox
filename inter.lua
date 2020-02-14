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
local srcdb="/tmp/nms/rawdb.db"
local targetdb="/tmp/nms/operate.db"

local update_list = {}
local users = {}

local nms_enable = read_file("/db/capwap_wtp/capwap_status")
if nms_enable ~= "Enabled" then
	print("nms is disable")
	return
end

local ha_enable = read_file("/tmp/status/ha_enable")
if ha_enable == "Enabled" then
	local ha_mode = read_file("/tmp/status/ha_mode")
	if ha_mode == "Standby" then
		return
	end
end

local nms_ip = string.trim(read_file("/db/capwap_wtp/ac_cluster_ip"))

function webpush(path, value, keep)
    write_file("/tmp/nms/" .. path, value)
    local url = string.format("curl -k --connect-timeout 5 --max-time 60 -X POST -H 'Content-Type: application/json' https://%s/report/%s -d@/tmp/nms/%s", nms_ip, path, path)
    local status = os.execute(url)
    if keep == 1 and status ~= 0 then
    	ostime=os.time(os.date("!*t"))
    	write_file("/tmp/nms/" ..path.."/"..ostime ,value)
    end
end

function prepare_database()
	local dumppath="/tmp/nms/dumprows"
	local users_str = read_exec(string.format([[cipgwcli dump]]))
	local rows = string.split(users_str, "\n")

	local fp = io.open(dumppath, 'wb')
	fp:write("begin transaction;\n")
	for _, v in pairs(rows) do
		local data = string.split(v, ",")
		-- mac, login_time, session_time, tx, rx, others
		fp:write("insert into rawacct (user_mac, login_time, session_time, type, tx, rx, others) values ('"..data[1].."',"..data[2]..","..data[3]..", 2, "..data[4]..", "..data[5]..", '');\n")
	end
        fp:write("commit;\n")

	fp.close()

	read_exec(string.format([[rm -f %s; sqlite -init /tmp/timeout.sql %s '.clone %s' </dev/null]], targetdb, srcdb, targetdb))

	read_exec(string.format([[sqlite -init /tmp/timeout.sql %s < %s]], targetdb, dumppath))

end

function createupdate(mac, apmac, ut, tx1, rx1, tx2, rx2)
	local v = {}
	v.mac = mac
	v.apmac = apmac
	v.ut = ut
	v.tx = tx2 - tx1
	v.rx = rx2 - rx1
	return v
end

function cal_useage()
	local TYPE_LOGIN='1'
	local TYPE_UPDATE='2'
	local TYPE_LOGOUT='3'

	local STATUS_UNKNOWN=0
	local STATUS_ONLINE=1
	local STATUS_OFFLINE=2

	local output = read_exec(string.format([[sqlite -init /tmp/timeout.sql %s "select * from rawacct order by user_mac, login_time, session_time, type asc" </dev/null]], targetdb))
	local rows = string.split(output, "\n")

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
			users[mac] = {}
			users[mac].mac = mac
			users[mac].lt = lt
			users[mac].st = st
			users[mac].mode = mode
			users[mac].tx = tx
			users[mac].rx = rx
			if mode == TYPE_LOGIN then
				users[mac].status = STATUS_ONLINE
				users[mac].apmac = apmac
			elseif mode == TYPE_UPDATE then
				users[mac].status = STATUS_UNKNOWN
				users[mac].apmac = apmac
			else
				users[mac].status = STATUS_OFFLINE
			end
		else
			if users[mac].lt == lt then
				if mode == TYPE_LOGIN then
					users[mac].status = STATUS_ONLINE
					users[mac].st = st
					users[mac].apmac = apmac
					users[mac].mode = mode
				elseif mode == TYPE_LOGOUT then
					users[mac].status = STATUS_OFFLINE
					local update = createupdate(mac, users[mac].apmac, lt+st, users[mac].tx, users[mac].rx, tx, rx)
					table.insert(update_list, update)

					users[mac].st = st
				elseif mode == TYPE_UPDATE then
					if users[mac].status ~= STATUS_OFFLINE then
						users[mac].status = STATUS_ONLINE
						local update = createupdate(mac, users[mac].apmac, lt+st, users[mac].tx, users[mac].rx, tx, rx)
						table.insert(update_list, update)
						users[mac].st = st
						users[mac].tx = tx
						users[mac].rx = rx
						users[mac].mode = mode
					end
				end
			else
				users[mac].lt = lt
				users[mac].st = st
				users[mac].tx = tx
				users[mac].rx = rx
				users[mac].mode = mode
				if mode == TYPE_LOGIN then
					users[mac].status = STATUS_ONLINE
					users[mac].apmac = apmac
				elseif mode == TYPE_LOGOUT then
					users[mac].status = STATUS_OFFLINE
				elseif mode == TYPE_UPDATE then
					users[mac].status = STATUS_ONLINE
				end
			end
		end
	end
end

prepare_database()

cal_useage()

print("=== update users status back to /tmp/nms/rawdb.db and update current users status to NMS ===")
for _, v in pairs(users) do
	print(inspect(v))
end

-- webpubsh("report_current", )

print("=== prepare update entry and update to NMS ===")
print(inspect(cjson.encode(update_list)))
webpush("report_recently", cjson.encode(update_list), 1)




