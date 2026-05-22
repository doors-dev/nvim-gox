local M = {
	active = false,
}

local function cmd_args(opts, goxPath, goplsPath)
	local cmd = { goxPath, "srv", "-gopls", goplsPath }
	local logFile = vim.tbl_get(opts, "lsp", "log", "file")
	local logLevel = vim.tbl_get(opts, "lsp", "log", "level")

	if type(logFile) == "string" and logFile ~= "" then
		table.insert(cmd, "-log")
		table.insert(cmd, logFile)
	end
	if type(logLevel) == "string" and logLevel ~= "" then
		table.insert(cmd, "-log.level")
		table.insert(cmd, logLevel)
	end

	return cmd
end

local function normalize_path(path)
	if type(path) ~= "string" or path == "" then
		return nil
	end
	local uv = vim.uv or vim.loop
	return vim.fs.normalize(uv.fs_realpath(path) or path)
end

local function path_contains(root, path)
	root = normalize_path(root)
	path = normalize_path(path)
	if not root or not path then
		return false
	end
	return path == root or vim.startswith(path, root .. "/")
end

local function client_root(client)
	local root = vim.tbl_get(client, "config", "root_dir")
	if type(root) == "string" and root ~= "" then
		return root
	end
	local folder = client.workspace_folders and client.workspace_folders[1]
	if folder and folder.uri then
		return vim.uri_to_fname(folder.uri)
	end
end

local function last_gox_root()
	local clients = vim.lsp.get_clients({ name = "gox" })
	for i = #clients, 1, -1 do
		local root = client_root(clients[i])
		if root then
			return root
		end
	end
end

local go_env_cache = {}

local function go_env(opts, name, suffix)
	local cache_key = name .. (suffix or "")
	if go_env_cache[cache_key] ~= nil then
		return go_env_cache[cache_key]
	end

	local go = vim.fn.expand(vim.tbl_get(opts, "bin", "go") or "go")
	local lines = vim.fn.systemlist({ go, "env", name })
	local value = ""
	if vim.v.shell_error == 0 and type(lines[1]) == "string" then
		value = vim.trim(lines[1])
		if value ~= "" and suffix then
			value = value .. suffix
		end
	end
	go_env_cache[cache_key] = value
	return value
end

local function gox_root_dir(opts)
	return function(bufnr, on_dir)
		local path = vim.api.nvim_buf_get_name(bufnr)
		if path == "" then
			return
		end

		local mod_cache = go_env(opts, "GOMODCACHE")
		local std_lib = go_env(opts, "GOROOT", "/src")
		if path_contains(mod_cache, path) or path_contains(std_lib, path) then
			local root = last_gox_root()
			if root then
				on_dir(root)
				return
			end
		end

		on_dir(
			vim.fs.root(path, "go.work")
			or vim.fs.root(path, "go.mod")
			or vim.fs.root(path, ".git")
		)
	end
end

function M.enabled()
	return vim.tbl_get(M.opts, "lsp", "enabled") ~= false
end


function M.health(cb, opts)
	opts = opts or {}
	if not M.enabled() then
		if type(cb) == "function" then
			cb()
		end
		return
	end
	local versions  = require("gox.versions")
	local Gopls     = require("gox.gopls")
	local gopls     = Gopls.new(M.opts, versions.gopls)
	local goplsPath = gopls:resolve_path()
	local skipGopls = opts.skipGopls or false
	if not skipGopls and goplsPath == "" then
		local msg =
			"GoX: Go language server " ..
			versions.gopls ..
			" not found. Configure bin.gopls, or install a compatible gopls into the GoX directory now?"
		vim.ui.select({ "Install", "Cancel" }, { prompt = msg }, function(choice)
			if choice == "Install" then
				gopls:ensure()
				M.health(cb, opts)
				return
			end
			vim.notify(
				"GoX: gopls is required. Configure bin.gopls to use your gopls, or rerun the health check to install it into the GoX directory.",
				vim.log.levels.WARN
			)
			opts.skipGopls = true
			M.health(cb, opts)
		end)
		return
	end
	local Goxls   = require("gox.goxls")
	local gox     = Goxls.new(M.opts, versions.gox)
	local goxPath = gox:resolve_path()
	if goxPath == "" then
		local msg =
			"GoX: GoX language server " ..
			versions.gox .. " not found. Configure bin.gox, or install a compatible gox into the GoX directory now?"
		vim.ui.select({ "Install", "Cancel" }, { prompt = msg }, function(choice)
			if choice == "Install" then
				gox:ensure()
				M.health(cb, opts)
				return
			end
			vim.notify(
				"GoX: gox is required. Configure bin.gox to use your gox binary, or rerun the health check to install it into the GoX directory.",
				vim.log.levels.WARN
			)
			if type(cb) == "function" then
				cb()
			end
		end)
		return
	end
	if goxPath ~= "" and goplsPath ~= "" and M.active == false then
		M.active = true
		vim.api.nvim_create_autocmd("LspAttach", {
			callback = function(args)
				local client = vim.lsp.get_client_by_id(args.data.client_id)
				if client and client.name == "gopls" then
					vim.notify(
						"GoX: Disabling standalone gopls (handled internally by GoX). To prevent this message, disable gopls in your LSP configuration.",
						vim.log.levels.INFO
					)
					client:stop()
					vim.lsp.enable('gopls', false)
				end
			end,
		})
		vim.lsp.config('gox', {
			cmd = cmd_args(M.opts, goxPath, goplsPath),
			filetypes = { "go", "gomod", "gowork", "gosum", "gox" },
			root_dir = gox_root_dir(M.opts),
		})
		vim.lsp.enable('gox')
	end
	if type(cb) == "function" then
		cb()
	end
end

function M.setup(opts)
	M.opts = opts or {}
	if not M.enabled() then
		return
	end
	M.health()
end

return M
