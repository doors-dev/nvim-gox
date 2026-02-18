local Tool = require("gox.tool").Tool
local uv = vim.uv or vim.loop

local Gox = {}
Gox.__index = Gox
setmetatable(Gox, { __index = Tool })

Gox.name = "gox"

function Gox.new(opt, version)
	local self = Tool.new(opt, version)
	return setmetatable(self, Gox)
end

local function detect_os()
	if vim.fn.has("win32") == 1 or vim.fn.has("win64") == 1 then
		return "windows"
	end
	local sys = (uv.os_uname().sysname or ""):lower()
	if sys:find("darwin", 1, true) then
		return "darwin"
	end
	if sys:find("linux", 1, true) then
		return "linux"
	end
	return nil
end

local function detect_cpu()
	-- Prefer uname machine; fall back to jit.arch
	local m = (uv.os_uname().machine or ""):lower()
	local a = (jit and jit.arch or ""):lower()

	local v = (m ~= "" and m) or a

	if v == "x86_64" or v == "amd64" or v == "x64" then
		return "amd64"
	end
	if v == "aarch64" or v == "arm64" then
		return "arm64"
	end
	return nil
end

function Gox:install()
	local os = detect_os()
	local cpu = detect_cpu()

	if not os or not cpu then
		error(
			"No binaries available for your platform and arch : "
			.. tostring(uv.os_uname().sysname)
			.. " "
			.. tostring((uv.os_uname().machine or (jit and jit.arch) or "unknown"))
			.. " Please install GoX language server by following the instructions in the README.",
			0
		)
	end

	local ext = (os == "windows") and ".zip" or ".tar.gz"
	local file_name = string.format("gox_%s_%s%s", os, cpu, ext)

	local url = string.format(
		"https://github.com/doors-dev/gox/releases/download/%s/%s",
		self.version,
		file_name
	)

	local archive = self:download(url, file_name)
	self:extract(archive, self:install_dir())

	self:make_executable(self:executable_path())
	self:clean_temp_dir()
end

return Gox
