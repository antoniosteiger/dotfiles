--[[
=====================================================================
==================== CUSTOM NEOVIM CONFIGURATION ====================
=====================================================================
Based on Kickstart.nvim with personal customizations
Configured for NixOS - LSPs managed externally
--]]

-- Set <space> as the leader key
vim.g.mapleader = " "
vim.g.maplocalleader = " "

-- Set to true if you have a Nerd Font installed
vim.g.have_nerd_font = true

-- [[ Setting options ]]
vim.o.number = true
vim.o.relativenumber = true
vim.o.mouse = "a"
vim.o.showmode = false
vim.o.breakindent = true
vim.o.undofile = true
vim.o.ignorecase = true
vim.o.smartcase = true
vim.o.signcolumn = "yes"
vim.o.updatetime = 250
vim.o.timeoutlen = 300
vim.o.splitright = true
vim.o.splitbelow = true
vim.o.list = true
vim.opt.listchars = { tab = "» ", trail = "·", nbsp = "␣" }
vim.o.inccommand = "split"
vim.o.cursorline = true
vim.o.scrolloff = 10
vim.o.confirm = true

-- Sync clipboard between OS and Neovim
vim.schedule(function()
	vim.o.clipboard = "unnamedplus"
end)

-- [[ Basic Keymaps ]]
vim.keymap.set("n", "<Esc>", "<cmd>nohlsearch<CR>")
vim.keymap.set("n", "<leader>q", vim.diagnostic.setloclist, { desc = "Open diagnostic [Q]uickfix list" })
vim.keymap.set("t", "<Esc><Esc>", "<C-\\><C-n>", { desc = "Exit terminal mode" })

-- Window navigation
vim.keymap.set("n", "<A-h>", "<C-w>h", { desc = "Move to left pane" })
vim.keymap.set("n", "<A-j>", "<C-w>j", { desc = "Move to pane below" })
vim.keymap.set("n", "<A-k>", "<C-w>k", { desc = "Move to pane above" })
vim.keymap.set("n", "<A-l>", "<C-w>l", { desc = "Move to right pane" })

-- [[ Basic Autocommands ]]
vim.api.nvim_create_autocmd("TextYankPost", {
	desc = "Highlight when yanking text",
	group = vim.api.nvim_create_augroup("kickstart-highlight-yank", { clear = true }),
	callback = function()
		vim.hl.on_yank()
	end,
})

-- [[ Plugin Configurations ]]

-- Neo-tree
vim.api.nvim_create_autocmd("VimEnter", {
	callback = function()
		if vim.fn.argc() == 0 then
			vim.cmd("Neotree show left")
		end
	end,
})

require("neo-tree").setup({
	close_if_last_window = true,
	popup_border_style = "rounded",
	enable_git_status = true,
	enable_diagnostics = true,
	default_component_configs = {
		git_status = {
			symbols = {
				added = "✚",
				modified = "",
				deleted = "✖",
				renamed = "➜",
				untracked = "★",
				ignored = "◌",
				unstaged = "✗",
				staged = "✓",
				conflict = "",
			},
		},
	},
	window = {
		position = "left",
		width = 35,
		mappings = {
			["<space>"] = "none",
			["a"] = {
				"add",
				config = {
					show_path = "relative",
				},
			},
			["A"] = "add_directory",
			["d"] = "delete",
			["r"] = "rename",
			["y"] = "copy_to_clipboard",
			["x"] = "cut_to_clipboard",
			["p"] = "paste_from_clipboard",
			["c"] = "copy",
			["m"] = "move",
		},
	},
	filesystem = {
		filtered_items = {
			visible = false,
			hide_dotfiles = false,
			hide_gitignored = false,
		},
		follow_current_file = {
			enabled = true,
		},
		use_libuv_file_watcher = true,
	},
	event_handlers = {
		{
			event = "neo_tree_buffer_enter",
			handler = function()
				vim.cmd("setlocal number relativenumber")
			end,
		},
	},
})

vim.keymap.set("n", "<leader>e", "<cmd>Neotree toggle left<CR>", { desc = "[E]xplorer toggle" })

-- Bufferline
require("bufferline").setup({
	options = {
		mode = "buffers",
		numbers = function(opts)
			return string.format("%s", opts.ordinal)
		end,
		close_command = "bdelete! %d",
		right_mouse_command = "bdelete! %d",
		left_mouse_command = "buffer %d",
		middle_mouse_command = nil,
		indicator = {
			style = "icon",
			icon = "▎",
		},
		buffer_close_icon = "",
		modified_icon = "●",
		close_icon = "",
		left_trunc_marker = "",
		right_trunc_marker = "",
		offsets = {
			{
				filetype = "neo-tree",
				text = "File Explorer",
				text_align = "left",
				separator = true,
			},
		},
		show_buffer_icons = true,
		show_buffer_close_icons = true,
		show_close_icon = true,
		show_tab_indicators = true,
		separator_style = "thin",
		always_show_bufferline = true,
	},
})

-- Alt+1-9 to switch to tab
for i = 1, 9 do
	vim.keymap.set("n", string.format("<A-%d>", i), function()
		require("bufferline").go_to(i, true)
	end, { desc = "Go to buffer " .. i })
end

-- Tab navigation
vim.keymap.set("n", "<Tab>", "<cmd>BufferLineCycleNext<CR>", { desc = "Next buffer" })
vim.keymap.set("n", "<S-Tab>", "<cmd>BufferLineCyclePrev<CR>", { desc = "Previous buffer" })
vim.keymap.set("n", "<leader>x", "<cmd>bdelete<CR>", { desc = "Close buffer" })

-- Flash
require("flash").setup({})

-- Guess indent
require("guess-indent").setup({})

-- Gitsigns
require("gitsigns").setup({
	signs = {
		add = { text = "+" },
		change = { text = "~" },
		delete = { text = "_" },
		topdelete = { text = "‾" },
		changedelete = { text = "~" },
	},
})

-- Which-key
require("which-key").setup({
	delay = 200,
	icons = {
		mappings = vim.g.have_nerd_font,
		keys = vim.g.have_nerd_font and {} or {
			Up = "<Up> ",
			Down = "<Down> ",
			Left = "<Left> ",
			Right = "<Right> ",
			C = "<C-…> ",
			M = "<M-…> ",
			S = "<S-…> ",
			CR = "<CR> ",
			Esc = "<Esc> ",
			Space = "<Space> ",
			Tab = "<Tab> ",
		},
	},
	spec = {
		{ "<leader>s", group = "[S]earch" },
		{ "<leader>t", group = "[T]oggle" },
		{ "<leader>h", group = "Git [H]unk", mode = { "n", "v" } },
	},
})

-- Telescope
require("telescope").setup({
	extensions = {
		["ui-select"] = {
			require("telescope.themes").get_dropdown(),
		},
	},
})

pcall(require("telescope").load_extension, "fzf")
pcall(require("telescope").load_extension, "ui-select")

local builtin = require("telescope.builtin")
vim.keymap.set("n", "<leader>sh", builtin.help_tags, { desc = "[S]earch [H]elp" })
vim.keymap.set("n", "<leader>sk", builtin.keymaps, { desc = "[S]earch [K]eymaps" })
vim.keymap.set("n", "<leader>sf", builtin.find_files, { desc = "[S]earch [F]iles" })
vim.keymap.set("n", "<leader>ss", builtin.builtin, { desc = "[S]earch [S]elect Telescope" })
vim.keymap.set("n", "<leader>sw", builtin.grep_string, { desc = "[S]earch current [W]ord" })
vim.keymap.set("n", "<leader>sg", builtin.live_grep, { desc = "[S]earch by [G]rep" })
vim.keymap.set("n", "<leader>sd", builtin.diagnostics, { desc = "[S]earch [D]iagnostics" })
vim.keymap.set("n", "<leader>sr", builtin.resume, { desc = "[S]earch [R]esume" })
vim.keymap.set("n", "<leader>s.", builtin.oldfiles, { desc = "[S]earch Recent Files" })
vim.keymap.set("n", "<leader><leader>", builtin.buffers, { desc = "[ ] Find buffers" })
vim.keymap.set("n", "<leader>/", function()
	builtin.current_buffer_fuzzy_find(require("telescope.themes").get_dropdown({
		winblend = 10,
		previewer = false,
	}))
end, { desc = "[/] Fuzzily search in current buffer" })
vim.keymap.set("n", "<leader>s/", function()
	builtin.live_grep({
		grep_open_files = true,
		prompt_title = "Live Grep in Open Files",
	})
end, { desc = "[S]earch [/] in Open Files" })
vim.keymap.set("n", "<leader>sn", function()
	builtin.find_files({ cwd = vim.fn.stdpath("config") })
end, { desc = "[S]earch [N]eovim files" })

-- Lazydev
require("lazydev").setup({
	library = {
		{ path = "${3rd}/luv/library", words = { "vim%.uv" } },
	},
})

-- LSP Configuration
require("fidget").setup({})

vim.api.nvim_create_autocmd("LspAttach", {
	group = vim.api.nvim_create_augroup("kickstart-lsp-attach", { clear = true }),
	callback = function(event)
		local map = function(keys, func, desc, mode)
			mode = mode or "n"
			vim.keymap.set(mode, keys, func, { buffer = event.buf, desc = "LSP: " .. desc })
		end

		map("grn", vim.lsp.buf.rename, "[R]e[n]ame")
		map("gra", vim.lsp.buf.code_action, "Code [A]ction", { "n", "x" })
		map("grr", require("telescope.builtin").lsp_references, "[G]oto [R]eferences")
		map("gri", require("telescope.builtin").lsp_implementations, "[G]oto [I]mplementation")
		map("grd", require("telescope.builtin").lsp_definitions, "[G]oto [D]efinition")
		map("grD", vim.lsp.buf.declaration, "[G]oto [D]eclaration")
		map("gO", require("telescope.builtin").lsp_document_symbols, "Document Symbols")
		map("gW", require("telescope.builtin").lsp_dynamic_workspace_symbols, "Workspace Symbols")
		map("grt", require("telescope.builtin").lsp_type_definitions, "[G]oto [T]ype Definition")

		local client = vim.lsp.get_client_by_id(event.data.client_id)
		if client and client.supports_method("textDocument/documentHighlight") then
			local highlight_augroup = vim.api.nvim_create_augroup("kickstart-lsp-highlight", { clear = false })
			vim.api.nvim_create_autocmd({ "CursorHold", "CursorHoldI" }, {
				buffer = event.buf,
				group = highlight_augroup,
				callback = vim.lsp.buf.document_highlight,
			})
			vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
				buffer = event.buf,
				group = highlight_augroup,
				callback = vim.lsp.buf.clear_references,
			})
		end

		if client and client.supports_method("textDocument/inlayHint") then
			map("<leader>th", function()
				vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled({ bufnr = event.buf }))
			end, "[T]oggle Inlay [H]ints")
		end
	end,
})

-- Diagnostic configuration
vim.diagnostic.config({
	severity_sort = true,
	float = { border = "rounded", source = "if_many" },
	underline = { severity = vim.diagnostic.severity.ERROR },
	virtual_text = {
		source = "if_many",
		spacing = 2,
	},
})

local capabilities = require("blink.cmp").get_lsp_capabilities()

-- Manual LSP setup (assumes LSPs are installed via Nix)

-- Rust
vim.lsp.enable("rust_analyzer")
vim.lsp.config("rust_analyzer", {
	capabilities = capabilities,
	settings = {
		["rust-analyzer"] = {
			cargo = {
				allFeatures = true,
			},
		},
	},
})

-- TypeScript/JavaScript
vim.lsp.enable("ts_ls")
vim.lsp.config("ts_ls", {
	capabilities = capabilities,
})

vim.lsp.enable("biome")
vim.lsp.config("biome", {
	capabilities = capabilities,
})

vim.lsp.enable("eslint")
vim.lsp.config("eslint", {
	capabilities = capabilities,
})

vim.lsp.enable("cssls")
vim.lsp.config("cssls", {
	capabilities = capabilities,
})

-- Svelte
vim.lsp.enable("svelte")
vim.lsp.config("svelte", {
	capabilities = capabilities,
})

-- Python
vim.lsp.enable("pyrefly")
vim.lsp.config("pyrefly", {
	capabilities = capabilities,
})

-- Markdown
vim.lsp.enable("marksman")
vim.lsp.config("marksman", {
	capabilities = capabilities,
})

-- Typst
vim.lsp.enable("tinymist")
vim.lsp.config("tinymist", {
	capabilities = capabilities,
	settings = {
		-- exportPdf = "onSave",
	},
})

-- Spell Checking
vim.lsp.config("ltex_plus", {
	cmd = { "ltex-ls-plus" },
	filetypes = { "typst" },
	root_markers = { ".git" },
	settings = {
		ltex = {
			language = "en-US",
			checkFrequency = "edit", -- check as you type, not just on save
			sentenceCacheSize = 2000,
			disabledRules = {
				["en-US"] = {
					"WHITESPACE_RULE", -- false positives around Typst markup
					"EN_QUOTES", -- Typst handles its own smart quotes
				},
			},
			additionalRules = {
				enablePickyRules = false, -- disable pedantic style warnings
			},
		},
	},
})
vim.lsp.enable("ltex_plus")
vim.api.nvim_create_autocmd("FileType", {
	pattern = "typst",
	callback = function()
		vim.opt_local.spell = false
		vim.opt_local.spelllang = "en_us"
		vim.opt_local.textwidth = 100
	end,
})

-- Lua
vim.lsp.enable("lua_ls")
vim.lsp.config("lua_ls", {
	capabilities = capabilities,
	settings = {
		Lua = {
			completion = {
				callSnippet = "Replace",
			},
			diagnostics = {
				globals = { "vim" },
			},
		},
	},
})

-- Nix
vim.lsp.enable("nil_ls")
vim.lsp.config("nil_ls", {
	capabilities = capabilities,
	settings = {
		["nil"] = {
			formatting = {
				command = { "nixpkgs-fmt" },
			},
		},
	},
})

-- Conform (formatting)
require("conform").setup({
	notify_on_error = false,
	format_on_save = function(bufnr)
		local disable_filetypes = { c = true, cpp = true }
		if disable_filetypes[vim.bo[bufnr].filetype] then
			return nil
		else
			return {
				timeout_ms = 4000,
				lsp_format = "fallback",
			}
		end
	end,
	formatters_by_ft = {
		lua = { "stylua" },
		javascript = { "biome" },
		javascriptreact = { "biome" },
		typescriptreact = { "biome" },
		typescript = { "biome" },
		svelte = { "prettier" },
		css = { "biome" },
		html = { "biome" },
		python = { "ruff" },
		nix = { "nixfmt" },
		rust = { "rustfmt" },
	},
})

vim.keymap.set("", "<leader>f", function()
	require("conform").format({ async = true, lsp_format = "fallback" })
end, { desc = "[F]ormat buffer" })

-- Blink.cmp (autocompletion)
require("luasnip").setup({})

require("blink.cmp").setup({
	keymap = {
		preset = "default",
		["<Tab>"] = {
			function(cmp)
				if cmp.is_visible() then
					return cmp.select_and_accept()
				else
					return vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Tab>", true, false, true), "n", false)
				end
			end,
		},
	},
	appearance = {
		nerd_font_variant = "mono",
	},
	completion = {
		documentation = { auto_show = false, auto_show_delay_ms = 500 },
	},
	sources = {
		default = { "lsp", "path", "snippets", "lazydev" },
		providers = {
			lazydev = { module = "lazydev.integrations.blink", score_offset = 100 },
		},
	},
	snippets = { preset = "luasnip" },
	fuzzy = { implementation = "lua" },
	signature = { enabled = true },
})

-- Theme
vim.g.gruvbox_material_enable_italic = true
vim.cmd.colorscheme("gruvbox-material")

-- Todo comments
require("todo-comments").setup({ signs = false })

-- Mini.nvim
require("mini.ai").setup({ n_lines = 500 })
require("mini.surround").setup()

local statusline = require("mini.statusline")
statusline.setup({ use_icons = vim.g.have_nerd_font })
statusline.section_location = function()
	return "%2l:%-2v"
end

-- Treesitter
require("nvim-treesitter.configs").setup({
	auto_install = false,
	highlight = {
		enable = true,
		additional_vim_regex_highlighting = { "ruby" },
	},
	indent = { enable = true, disable = { "ruby" } },
})

-- Autopairs
require("nvim-autopairs").setup({})

-- Comment.nvim
require("Comment").setup({})

-- vim: ts=2 sts=2 sw=2 et
