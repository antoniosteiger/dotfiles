--- @since 25.5.31
-- Jump to or unmount any mounted drive, phone or camera.
-- Devices are read live from gvfs (`gio mount -l`), which sees both udisks
-- drives (/run/media/...) and MTP/PTP devices (/run/user/<uid>/gvfs/...).

local KEYS = "123456789abcdefghijklmnopqrstvwxyz" -- no "u": it opens the unmount menu

local get_cwd = ya.sync(function() return tostring(cx.active.current.cwd) end)

local function notify(content, level)
	ya.notify({ title = "Devices", content = content, timeout = 3, level = level or "info" })
end

local function url_decode(s)
	return (s:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end))
end

-- Local folder of a mount: decoded file:// URI, or the gvfs FUSE path for mtp:// etc.
local function local_path(uri)
	if uri:sub(1, 7) == "file://" then
		return url_decode(uri:sub(8))
	end
	local out = Command("gio"):arg({ "info", uri }):output()
	return out and out.stdout:match("local path: ([^\n]+)")
end

local function list_mounts()
	local out, err = Command("gio"):arg({ "mount", "-l" }):output()
	if not out then
		return nil, tostring(err)
	end
	local mounts, seen = {}, {}
	for name, uri in out.stdout:gmatch("Mount%(%d+%): ([^\n]-) %-> (%S+)") do
		-- A phone is listed twice (under its volume and as a bare mount); keep the first.
		if not seen[uri] then
			seen[uri] = true
			local path = local_path(uri)
			if path then
				mounts[#mounts + 1] = { name = name, uri = uri, path = path }
			end
		end
	end
	return mounts
end

local function unmount(m)
	local cwd = get_cwd()
	if cwd == m.path or cwd:sub(1, #m.path + 1) == m.path .. "/" then
		-- yazi's own working directory would keep the device busy
		ya.emit("cd", { os.getenv("HOME"), raw = true })
		ya.sleep(0.3)
	end
	local out, err = Command("gio"):arg({ "mount", "-u", m.uri }):stderr(Command.PIPED):output()
	if out and out.status.success then
		notify("Unmounted " .. m.name .. ", safe to unplug")
	else
		notify("Unmount failed: " .. (out and out.stderr or tostring(err)), "error")
	end
end

local function entry()
	local mounts, err = list_mounts()
	if not mounts then
		return notify("gio failed: " .. err, "error")
	elseif #mounts == 0 then
		return notify("No devices mounted")
	end

	local cands = {}
	for i, m in ipairs(mounts) do
		cands[i] = { on = KEYS:sub(i, i), desc = m.name .. "  →  " .. m.path }
	end
	cands[#cands + 1] = { on = "u", desc = "Unmount a device…" }

	local idx = ya.which({ cands = cands })
	if not idx then
		return
	elseif idx <= #mounts then
		return ya.emit("cd", { mounts[idx].path, raw = true })
	end

	cands[#cands] = nil
	idx = ya.which({ cands = cands })
	if idx then
		unmount(mounts[idx])
	end
end

return { entry = entry }
