local M = {
	active = false,
}

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
			cmd = { goxPath, "srv", "-gopls", goplsPath },
			filetypes = { "go", "gomod", "gowork", "gosum", "gox" },
			root_markers = { "go.work", "go.mod", ".git" },
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
