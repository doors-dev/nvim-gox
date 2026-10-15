-- tool.lua
-- Base helper for managing external tool binaries
--
-- Subclass contract:
--   - set `self.name` (string)
--   - implement `function tool:install()` which must place the executable at:
--       self:executable_path()
--
-- Context (`opt`) fields (optional):

local uv = vim.uv or vim.loop

local M = {}
local Tool = {}
Tool.__index = Tool

local function is_windows()
	return vim.fn.has("win32") == 1 or vim.fn.has("win64") == 1
end

local PATH_SEP = package.config:sub(1, 1)
local STALE_VERSION_SEC = 7 * 24 * 60 * 60

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
	-- another Neovim may create it or a parent at the same time, which fails mkdir: try again
	for _ = 1, 5 do
		if pcall(vim.fn.mkdir, p, "p") or vim.fn.isdirectory(p) == 1 then
			return
		end
	end
	error("can't create directory " .. p)
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

local function sha256_file(p)
	local f = io.open(p, "rb")
	if not f then
		return nil
	end
	local data = f:read("*a")
	f:close()
	return vim.fn.sha256(data)
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

local function resolve_bin(cmd)
	if type(cmd) ~= "string" or cmd == "" then
		return nil
	end
	return vim.fn.expand(cmd)
end

function Tool.new(external_opt, version)
	external_opt = external_opt or {}
	local opt = {
		storage_path = join(vim.fn.stdpath("data"), "gox"),
		bin = external_opt.bin or {},
	}
	mkdirp(opt.storage_path)
	return setmetatable({
		opt = opt,
		version = version,
		-- set while ensure() installs
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

function Tool:executable_path()
	return join(self:install_dir(), self.name .. self:suffix())
end

function Tool:hash_path()
	return join(self:install_dir(), "sha256.txt")
end

function Tool:read_hash()
	return read_file_text(self:hash_path())
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

function Tool:check()
	local expected = self:read_hash()
	if not expected or expected == "" then
		return false
	end
	return sha256_file(self:executable_path()) == vim.trim(expected)
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
		local st = stat(p)
		-- another Neovim may still run a recent version (missed if it has been open for longer than this)
		if realpath(p) ~= current and st and os.time() - st.mtime.sec > STALE_VERSION_SEC then
			rm_rf(p)
		end
	end
end

function Tool:download(url, filename)
	local dest = join(self._temp_dir, filename)
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

-- checks the file against the "<sha256>  <name>" list published at sums_url
function Tool:verify_checksum(file, sums_url)
	local name = vim.fs.basename(file)
	local sums = read_file_text(self:download(sums_url, name .. ".sums")) or ""
	local expected
	for line in sums:gmatch("[^\r\n]+") do
		local hash, n = line:match("^(%x+)%s+%*?(.-)%s*$")
		if hash and #hash == 64 and n == name then
			expected = hash:lower()
			break
		end
	end
	if not expected then
		error(self:msg("no checksum for " .. name .. " in " .. sums_url), 0)
	end
	local actual = sha256_file(file)
	if actual ~= expected then
		error(self:msg(("checksum mismatch for %s: expected %s, got %s"):format(name, expected, tostring(actual))), 0)
	end
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

-- Abstract: override in subclasses, place the executable in dir
function Tool:install(dir)
	error("Tool:install() must be implemented by subclass")
end

function Tool:resolve_path()
	local alt = resolve_bin(self.opt.bin[self.name])
	if alt then
		return alt
	end
	if self:check() then
		-- marks the version as in use, see clean_old
		local now = os.time()
		uv.fs_utime(self:install_dir(), now, now)
		return self:executable_path()
	end
	return ""
end

function Tool:ensure()
	local p = self:resolve_path()
	if p ~= "" then
		return p
	end

	notify(self:msg("installing " .. self.version .. " to " .. self:install_dir()), vim.log.levels.INFO)

	-- install into a directory of our own next to the versions, then move it into place:
	-- another Neovim may run the same install. clean_old removes what an interrupted install left
	local tool_root = join(self:bin_dir(), self.name)
	mkdirp(tool_root)
	local temp = assert(uv.fs_mkdtemp(join(tool_root, "tmp-XXXXXX")))
	self._temp_dir = temp
	local ok, err = pcall(function()
		local stage = join(temp, "stage")
		mkdirp(stage)
		self:install(stage)
		local hash = sha256_file(join(stage, self.name .. self:suffix()))
		if not hash then
			error("binary not found after installation", 0)
		end
		write_file_text(join(stage, "sha256.txt"), hash)
		self:move_into_place(stage)
	end)
	self._temp_dir = nil
	rm_rf(temp)
	if not ok then
		error(self:msg("installation failed: " .. tostring(err)), 0)
	end

	self:clean_old()

	notify(self:msg("installed successfully"), vim.log.levels.INFO)

	return self:executable_path()
end

function Tool:move_into_place(stage)
	local dir = self:install_dir()
	if uv.fs_rename(stage, dir) then
		return
	end
	-- install dir exists: another Neovim got there first, or a broken leftover
	if self:check() then
		return
	end
	rm_rf(dir)
	local ok, err = uv.fs_rename(stage, dir)
	if not ok and not self:check() then
		error(err, 0)
	end
end

M.Tool = Tool
return M
