local M = {}

local function register()
	local versions = require("gox.versions")
	local parsers = require("nvim-treesitter.parsers")
	parsers.gox = {
		install_info = {
			url = "https://github.com/doors-dev/tree-sitter-gox",
			revision = versions.tree_sitter_gox,
			generate = false,
			queries = "queries",
		},
	}
end

local required = { "go", "html", "css", "javascript", "gox" }

local function attach(buf, lang)
	-- the parser may not be installed yet
	if not pcall(vim.treesitter.start, buf, lang) then
		return
	end
	if M.indent then
		vim.bo[buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
	end
	if M.fold then
		-- [0][0]: this window and buffer only, not the window's later buffers
		vim.wo[0][0].foldexpr = 'v:lua.vim.treesitter.foldexpr()'
		vim.wo[0][0].foldmethod = 'expr'
		vim.wo[0][0].foldenable = true
		vim.wo[0][0].foldlevel = 99
	end
end

local function collect_missing(installed)
	local missing = {}
	for _, lang in ipairs(required) do
		if not vim.tbl_contains(installed, lang) then
			table.insert(missing, lang)
		end
	end
	return missing
end


function M.health(cb)
	if not M.enabled then
		if type(cb) == "function" then
			cb()
		end
		return
	end
	local ok = pcall(require, "nvim-treesitter")
	if not ok then
		vim.notify(
			"GoX: nvim-treesitter is not installed. Install it or disable Tree-sitter in GoX config.",
			vim.log.levels.WARN
		)
		if type(cb) == "function" then
			cb()
		end
		return
	end
	local ok_cfg, cfg = pcall(require, "nvim-treesitter.config")
	if not ok_cfg or cfg.get_installed == nil then
		vim.notify(
			"GoX: nvim-treesitter is too old or incompatible (missing config.get_installed). Update nvim-treesitter (main branch).",
			vim.log.levels.WARN
		)
		if type(cb) == "function" then
			cb()
		end
		return
	end
	local installed = cfg.get_installed("parsers")
	local missing = collect_missing(installed)
	if #missing == 0 then
		if type(cb) == "function" then
			cb()
		end
		return
	end
	local msg = ("GoX: Missing required Tree-sitter parsers: %s. Install now?"):format(table.concat(missing, ", "))
	vim.ui.select({ "Install", "Cancel" }, { prompt = msg }, function(choice)
		if choice == "Install" then
			local ok_inst, inst = pcall(require, "nvim-treesitter.install")
			if ok_inst and inst.install ~= nil then
				inst.install(missing)
			else
				vim.notify(
					"GoX: nvim-treesitter install module unavailable.",
					vim.log.levels.WARN
				)
			end
		else
			vim.notify(
				"GoX: Required Tree-sitter parsers were not installed. Tree-sitter features may be incomplete.",
				vim.log.levels.WARN
			)
		end
		if type(cb) == "function" then
			cb()
		end
	end)
end

function M.setup(opts)
	M.enabled = vim.tbl_get(opts, "treesitter", "enabled") ~= false
	if not M.enabled then
		return
	end
	M.indent = vim.tbl_get(opts, "treesitter", "indent") ~= false
	M.fold = vim.tbl_get(opts, "treesitter", "fold") ~= false
	local startGo = vim.tbl_get(opts, "treesitter", "start_go") == true
	vim.api.nvim_create_autocmd('User', {
		pattern = 'TSUpdate',
		callback = register
	})
	-- always registered: parsers installed later in this session are picked up by the next buffer
	vim.api.nvim_create_autocmd("FileType", {
		pattern = "gox",
		callback = function(e)
			attach(e.buf, "gox")
		end,
	})
	if startGo then
		vim.api.nvim_create_autocmd("FileType", {
			pattern = "go",
			callback = function(e)
				attach(e.buf, "go")
			end,
		})
	end
	M.health()
end

return M
