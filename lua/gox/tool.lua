-- tool.lua
-- Base helper for managing external tool binaries
--
-- Subclass contract:
--   - set `self.name` (string)
--   - implement `function tool:install()` which must place the executable at:
--       self:executable_path()
--
-- Context (`opt`) fields (optional):
--   - storage_path: base directory for bin/tmp (default: stdpath("data") .. "/gox")
--   - alternate_tools: table mapping tool name -> absolute executable path

local uv = vim.uv or vim.loop

local M = {}
local Tool = {}
Tool.__index = Tool

local function is_windows()
	return vim.fn.has("win32") == 1 or vim.fn.has("win64") == 1
end

local PATH_SEP = package.config:sub(1, 1)

local function join(...)
	if vim.fs and vim.fs.joinpath then
		return vim.fs.joinpath(...)
	end
	local parts = { ... }
	local out = table.remove(parts, 1) or ""
	for _, p in ipairs(parts) do
		if p and p ~= "" then
			if out:sub(-1) == PATH_SEP then
				out = out .. p
			else
				out = out .. PATH_SEP .. p
			end
		end
	end
	return out
end

local function realpath(p)
	return uv.fs_realpath(p) or p
end

local function stat(p)
	return uv.fs_stat(p)
end

local function exists(p)
	return stat(p) ~= nil
end

local function mkdirp(p)
	vim.fn.mkdir(p, "p")
end

local function rm_rf(p)
	if not p or p == "" then
		return
	end
	pcall(vim.fn.delete, p, "rf")
end

local function read_file_text(p)
	local ok, lines = pcall(vim.fn.readfile, p)
	if not ok or not lines or #lines == 0 then
		return nil
	end
	return table.concat(lines, "\n")
end

local function write_file_text(p, text)
	mkdirp(vim.fn.fnamemodify(p, ":h"))
	vim.fn.writefile({ text }, p)
end

local function notify(msg, level)
	vim.notify(msg, level or vim.log.levels.INFO)
end

local function merge_env(ext)
	ext = ext or {}
	local env = {}
	for k, v in pairs(vim.fn.environ()) do
		env[k] = v
	end
	for k, v in pairs(ext) do
		env[k] = v
	end
	return env
end

local function system_run(cmd, args, env)
	args = args or {}
	local full = { cmd }
	for _, a in ipairs(args) do
		table.insert(full, a)
	end

	local obj = vim.system(full, { env = env, text = true })
	local res = obj:wait()
	if res.code == 0 then
		return true
	end
	local err = (res.stderr and res.stderr ~= "" and res.stderr) or (res.stdout or "")
	return nil, string.format("%s failed (code %d): %s", table.concat(full, " "), res.code, err)
end

function Tool.new(opt, version)
	opt = opt or {}
	if not opt.storage_path then
		opt.storage_path = join(vim.fn.stdpath("data"), "gox")
	end
	mkdirp(opt.storage_path)

	return setmetatable({
		opt = opt,
		version = version,
		_temp_dir = nil,
		_bin_dir = nil,
	}, Tool)
end

function Tool:msg(message)
	return string.format("[%s] %s", self.name, message)
end

function Tool:suffix()
	return is_windows() and ".exe" or ""
end

function Tool:temp_dir()
	if not self._temp_dir then
		self._temp_dir = join(self.opt.storage_path, "tmp")
		mkdirp(self._temp_dir)
	end
	return self._temp_dir
end

function Tool:clean_temp_dir()
	local td = self:temp_dir()
	if exists(td) then
		rm_rf(td)
	end
end

function Tool:bin_dir()
	if not self._bin_dir then
		self._bin_dir = join(self.opt.storage_path, "bin")
		mkdirp(self._bin_dir)
	end
	return self._bin_dir
end

function Tool:install_dir()
	return join(self:bin_dir(), self.name, self.version)
end

function Tool:ensure_install_dir()
	local d = self:install_dir()
	if not exists(d) then
		mkdirp(d)
	end
end

function Tool:executable_path()
	return join(self:install_dir(), self.name .. self:suffix())
end

function Tool:hash_path()
	return join(self:install_dir(), "sha256.txt")
end

function Tool:clear_install_dir()
	local d = self:install_dir()
	if exists(d) then
		rm_rf(d)
	end
end

function Tool:read_hash()
	return read_file_text(self:hash_path())
end

function Tool:write_hash(hash)
	write_file_text(self:hash_path(), hash)
end

function Tool:make_executable(file_path)
	if is_windows() then
		return
	end
	local st = stat(file_path)
	if not st or not st.mode then
		return
	end
	local bor = (bit and bit.bor) or (bit32 and bit32.bor)
	local mode = st.mode
	local exec_bits = 73 -- 0o111
	local new_mode = bor and bor(mode, exec_bits) or (mode + exec_bits)
	pcall(uv.fs_chmod, file_path, new_mode)
end

function Tool:run(cmd, args, env_ext)
	local ok, err = system_run(cmd, args, merge_env(env_ext))
	if not ok then
		error(err)
	end
end


function Tool:calc_hash()
	local p = self:executable_path()
	if not exists(p) then
		return nil
	end
	return vim.fn.system({
		"git", "hash-object", "--no-filters", p
	})
end

function Tool:check()
	local expected = self:read_hash()
	if not expected or expected == "" then
		return false
	end
	local actual = self:calc_hash()
	if not actual then
		return false
	end
	return vim.trim(actual) == vim.trim(expected)
end

function Tool:clean_old()
	local tool_root = join(self:bin_dir(), self.name)
	if not exists(tool_root) then
		return
	end

	local current = realpath(join(tool_root, self.version))
	local handle = uv.fs_scandir(tool_root)
	if not handle then
		return
	end

	while true do
		local entry = uv.fs_scandir_next(handle)
		if not entry then
			break
		end
		local p = join(tool_root, entry)
		if realpath(p) ~= current then
			rm_rf(p)
		end
	end
end

function Tool:download(url, filename)
	local dest = join(self:temp_dir(), filename)
	mkdirp(vim.fn.fnamemodify(dest, ":h"))

	if vim.fn.executable("curl") == 1 then
		local ok, err = system_run("curl", {
			"-fL",
			"-H",
			"Accept: application/octet-stream",
			"-o",
			dest,
			url,
		}, merge_env())
		if not ok then
			error(self:msg("download failed: " .. err))
		end
		return dest
	end

	if vim.fn.executable("wget") == 1 then
		local ok, err = system_run("wget", { "-O", dest, url }, merge_env())
		if not ok then
			error(self:msg("download failed: " .. err))
		end
		return dest
	end

	if is_windows() then
		local ps = string.format([[
$ProgressPreference = 'SilentlyContinue';
Invoke-WebRequest -Uri '%s' -OutFile '%s' -Headers @{ Accept='application/octet-stream' };
]], url:gsub("'", "''"), dest:gsub("'", "''"))
		local ok, err = system_run("powershell", {
			"-NoProfile",
			"-ExecutionPolicy",
			"Bypass",
			"-Command",
			ps,
		}, merge_env())
		if not ok then
			error(self:msg("download failed: " .. err))
		end
		return dest
	end

	error(self:msg("download failed: curl/wget not found"))
end

function Tool:extract(archive_path, out_dir)
	mkdirp(out_dir)

	local lower = archive_path:lower()
	if lower:sub(-7) == ".tar.gz" or lower:sub(-4) == ".tgz" then
		local ok, err = system_run("tar", { "-xzf", archive_path, "-C", out_dir }, merge_env())
		if not ok then
			error(self:msg("extraction failed: " .. err))
		end
		return
	end

	if lower:sub(-4) == ".zip" then
		if vim.fn.executable("unzip") == 1 then
			local ok, err = system_run("unzip", { "-o", archive_path, "-d", out_dir }, merge_env())
			if not ok then
				error(self:msg("extraction failed: " .. err))
			end
			return
		end
		if is_windows() then
			local ps = string.format(
				"Expand-Archive -Force -Path '%s' -DestinationPath '%s'",
				archive_path:gsub("'", "''"),
				out_dir:gsub("'", "''")
			)
			local ok, err = system_run("powershell", {
				"-NoProfile",
				"-ExecutionPolicy",
				"Bypass",
				"-Command",
				ps,
			}, merge_env())
			if not ok then
				error(self:msg("extraction failed: " .. err))
			end
			return
		end
	end

	error(self:msg("extraction failed: unsupported archive type"))
end

-- Abstract: override in subclasses
function Tool:install()
	error("Tool:install() must be implemented by subclass")
end

function Tool:resolve_path()
	local alt = self.opt.alternate_tools and self.opt.alternate_tools[self.name]
	if alt and alt ~= "" then
		return alt
	end
	if self:check() then
		return self:executable_path()
	end
	return ""
end

function Tool:ensure()
	local p = self:resolve_path()
	if not p == "" then
		return p
	end

	notify(self:msg("installing " .. self.version .. " to " .. self:install_dir()), vim.log.levels.INFO)

	self:clear_install_dir()
	self:ensure_install_dir()

	local ok, err = pcall(function()
		self:install()
	end)
	if not ok then
		local msg = (type(err) == "string" and err) or "unknown"
		error(self:msg("installation failed: " .. msg))
	end

	local hash = self:calc_hash()
	if not hash then
		error(self:msg("binary not found after installation"))
	end

	self:write_hash(hash)
	self:clean_old()

	notify(self:msg("installed successfully"), vim.log.levels.INFO)

	return self:executable_path()
end

M.Tool = Tool
return M
