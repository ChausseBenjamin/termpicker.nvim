---@class TermpickerPreviewConfig
---@field text? string Text to preview colors as foreground/background (nil uses termpicker default: "The quick brown fox jumps over the lazy dog")
---@field background? string Background color for preview when target color is used as foreground (nil uses termpicker default: "#111a1f")
---@field foreground? string Foreground color for preview when target color is used as background (nil uses termpicker default: "#ebcb88")

---@class TermpickerBehaviorConfig
---@field prefer_config_color? boolean If true, per-call starting_color overrides visual selection (default: false)
---@field preserve_selection? boolean If true, don't replace visual selection, use configured output method instead (default: false)

---@class TermpickerConfig
---@field output? string|nil Output destination: nil = insert at cursor, string = register name (e.g. '"', '+', '*', 'a')
---@field starting_color? string Initial color to start with in hex format (default: "#7F7F7F")
---@field preview? TermpickerPreviewConfig Preview/sample text configuration
---@field behavior? TermpickerBehaviorConfig Behavior modification options

---@class TermpickerModule
---@field setup fun(opts?: TermpickerConfig): nil Configure the termpicker plugin
---@field pick fun(opts?: TermpickerConfig): nil Open color picker with optional per-call configuration
---@field pick_replace_selection fun(selected_text: string, start_row: integer, start_col: integer, end_row: integer, end_col: integer, opts?: TermpickerConfig): nil Replace visual selection with picked color
---@field termpicker_path fun(): string|nil Get the path to termpicker binary if it exists
---@field install_termpicker fun(): boolean Install termpicker binary
local M = {}

-- Import the installer module
local installer = require('termpicker.installer')

---@type TermpickerConfig
local config = {
	output = nil,              -- nil = insert at cursor, string = register name (e.g. '"', '+', '*')
	starting_color = '#7F7F7F', -- -c, --color: Initial color to start with (light gray default)

	-- Preview/sample options
	preview = {
		text = nil,     -- -t, --sample-text: Text to preview colors (nil uses termpicker default)
		background = nil, -- --bg: Background color for preview (nil uses termpicker default)
		foreground = nil, -- --fg: Foreground color for preview (nil uses termpicker default)
	},

	-- Behavior options
	behavior = {
		prefer_config_color = false, -- If true, per-call starting_color overrides visual selection
		preserve_selection = false, -- If true, don't replace visual selection, use configured output method instead
	}
}

---Configure the termpicker plugin with global options
---@param opts? TermpickerConfig Configuration options
M.setup = function(opts)
	config = vim.tbl_deep_extend('force', config, opts or {})
end

---Check if a string represents a valid color format
---@param str? string The string to check
---@return boolean true if the string is a valid color (hex, rgb, hsl, cmyk, oklch, or ansi)
local function is_color(str)
	if not str then return false end
	return (str:match('^#%x%x%x%x%x%x$') ~= nil) or                                     -- hex: #B7416E
			(str:match('^rgb%(%s*%d+%s*,%s*%d+%s*,%s*%d+%s*%)$') ~= nil) or                 -- rgb: rgb(183, 65, 110)
			(str:match('^hsl%(%s*%d+%s*,%s*%d+%%%s*,%s*%d+%%%s*%)$') ~= nil) or             -- hsl: hsl(337, 48%, 49%)
			(str:match('^cmyk%(%s*%d+%%%s*,%s*%d+%%%s*,%s*%d+%%%s*,%s*%d+%%%s*%)$') ~= nil) or -- cmyk: cmyk(0%, 64%, 40%, 28%)
			(str:match('^oklch%(%s*[%d%.]+%%%s*[%d%.]+%s*[%d%.]+%s*%)$') ~= nil) or         -- oklch: oklch(55.2% 0.158 0.10)
			(str:match('^\\X1B%[38;2;%d+;%d+;%d+m$') ~= nil) or                             -- ANSI foreground: \X1B[38;2;183;65;110m
			(str:match('^\\X1B%[48;2;%d+;%d+;%d+m$') ~= nil)                                -- ANSI background: \X1B[48;2;183;65;110m
end

---Extract a valid color from text that may contain other content
---@param text? string The text to search for color patterns
---@return string|nil color The extracted color if found, nil otherwise
local function extract_color_from_text(text)
	if not text then return nil end

	-- If the text is already a valid color, return it
	if is_color(text) then
		return text
	end

	-- Look for color patterns within the text
	return text:match('(#%x%x%x%x%x%x)') or
			text:match('(rgb%(%s*%d+%s*,%s*%d+%s*,%s*%d+%s*%))') or
			text:match('(hsl%(%s*%d+%s*,%s*%d+%%%s*,%s*%d+%%%s*%))') or
			text:match('(cmyk%(%s*%d+%%%s*,%s*%d+%%%s*,%s*%d+%%%s*,%s*%d+%%%s*%))') or
			text:match('(oklch%(%s*[%d%.]+%%%s*[%d%.]+%s*[%d%.]+%s*%))') or
			text:match('(\\X1B%[38;2;%d+;%d+;%d+m)') or
			text:match('(\\X1B%[48;2;%d+;%d+;%d+m)')
end

---Create a floating window for the termpicker interface
---@param buf? integer Optional buffer handle to use for the window
---@return integer buf Buffer handle
---@return integer win Window handle
local function create_float_win(buf)
	buf = buf or vim.api.nvim_create_buf(false, true)
	local width = 59
	local height = 21 -- tall enough for help + input
	local opts = {
		relative = 'editor',
		width = width,
		height = height,
		col = math.floor((vim.o.columns - width) / 2),
		row = math.floor((vim.o.lines - height) / 2),
		style = 'minimal',
		border = 'rounded',
	}
	local win = vim.api.nvim_open_win(buf, true, opts)
	return buf, win
end

---Check if termpicker is available and prompt for installation if not
---@return boolean available True if termpicker is available or user chose to install
local function ensure_termpicker_available()
	if installer.termpicker_exists() then
		return true
	end

	-- Prompt user for installation
	local choice = vim.fn.confirm(
		'Termpicker binary not found. Would you like to install it?',
		'&Yes\n&No',
		1
	)

	if choice == 1 then
		return installer.install_termpicker()
	else
		vim.notify('Termpicker installation cancelled', vim.log.levels.WARN)
		return false
	end
end

---Launch termpicker and handle color selection
---@param initial_color? string Initial color to start with (nil uses config default)
---@param callback fun(color: string): nil Function to call with the selected color
---@param opts? TermpickerConfig Optional configuration for this picker instance
local function pick_color(initial_color, callback, opts)
	local buf, win = create_float_win()

	-- Merge per-call options with global config
	opts = opts or {}
	local merged_opts = vim.tbl_deep_extend('force', config, opts)

	-- Get the termpicker binary path
	local termpicker_binary = installer.termpicker_path()
	if not termpicker_binary then
		vim.notify('Termpicker binary not found', vim.log.levels.ERROR)
		callback('')
		return
	end

	local args = { termpicker_binary, '--oneshot' }

	-- Determine initial color with precedence:
	-- 1. Visual selection (initial_color parameter) - highest precedence (unless overridden)
	-- 2. Per-call starting_color option (opts.starting_color) - can override selection if prefer_config_color = true
	-- 3. Global starting_color config (config.starting_color)
	-- 4. No color (termpicker default) - lowest precedence
	local color_to_use = nil
	if merged_opts.behavior.prefer_config_color and merged_opts.starting_color and is_color(merged_opts.starting_color) then
		-- Per-call starting_color overrides visual selection when prefer_config_color = true
		color_to_use = merged_opts.starting_color
	elseif initial_color and is_color(initial_color) then
		-- Visual selection takes precedence (default behavior)
		color_to_use = initial_color
	elseif merged_opts.starting_color and is_color(merged_opts.starting_color) then
		-- Per-call or global config
		color_to_use = merged_opts.starting_color
	end

	if color_to_use then
		table.insert(args, '--color')
		table.insert(args, color_to_use)
	end

	-- Add termpicker-specific options
	if merged_opts.preview.text ~= nil then
		table.insert(args, '--sample-text')
		table.insert(args, merged_opts.preview.text)
	end

	if merged_opts.preview.background ~= nil then
		table.insert(args, '--background-sample')
		table.insert(args, merged_opts.preview.background)
	end

	if merged_opts.preview.foreground ~= nil then
		table.insert(args, '--foreground-sample')
		table.insert(args, merged_opts.preview.foreground)
	end

	local color_output = ''

	-- Run termpicker directly without redirecting stdout - UI renders to stderr
	vim.fn.termopen(args, {
		on_stdout = function(_, data, _)
			-- Capture color output from stdout
			if data then
				for _, line in ipairs(data) do
					if line and line ~= '' then
						local trimmed = line:match('^%s*(.-)%s*$')
						if trimmed and is_color(trimmed) then
							color_output = trimmed
						end
					end
				end
			end
		end,
		on_exit = function(_, _, _)
			-- Close window and cleanup
			pcall(vim.api.nvim_win_close, win, true)
			pcall(vim.api.nvim_buf_delete, buf, { force = true })
			callback(color_output)
		end
	})

	-- Enter terminal mode automatically so user can interact with TUI
	vim.cmd('startinsert')
end

local function insert_at_cursor(text)
	local pos = vim.api.nvim_win_get_cursor(0)
	vim.api.nvim_buf_set_text(0, pos[1] - 1, pos[2], pos[1] - 1, pos[2], { text })
	vim.api.nvim_win_set_cursor(0, { pos[1], pos[2] + #text })
end

local function handle_output(text, output_option)
	output_option = output_option or config.output
	if output_option == nil then
		-- Insert at cursor (default behavior)
		insert_at_cursor(text)
	elseif type(output_option) == "string" then
		-- Store in specified register
		vim.fn.setreg(output_option, text)
	else
		-- Fallback to insert at cursor if invalid option
		insert_at_cursor(text)
	end
end



---Pick a color and replace the specified text range with it
---@param selected_text string The currently selected text (may contain a color to use as starting point)
---@param start_row integer Start row (0-based)
---@param start_col integer Start column (0-based)
---@param end_row integer End row (0-based)
---@param end_col integer End column (0-based, exclusive)
---@param opts? TermpickerConfig Optional per-call configuration
M.pick_replace_selection = function(selected_text, start_row, start_col, end_row,
																		end_col, opts)
	-- Check if termpicker is available before proceeding
	if not ensure_termpicker_available() then
		return
	end
	opts = opts or {}
	local initial_color = extract_color_from_text(selected_text)

	pick_color(initial_color, function(color)
		if color == '' then return end
		-- Replace the visual selection with the new color
		-- Use nvim_buf_set_text with proper coordinates
		local success, err = pcall(vim.api.nvim_buf_set_text, 0, start_row, start_col,
			end_row, end_col, { color })
		if not success then
			-- Fallback: just insert at cursor if replacement fails
			insert_at_cursor(color)
		end
	end, opts)
end

---Open the color picker interface
---Behavior depends on current mode:
--- - Visual mode: Uses selected text as initial color, replaces selection with picked color (unless preserve_selection is true)
--- - Insert mode: Inserts picked color at cursor and returns to insert mode
--- - Normal mode: Uses configured output method (insert at cursor or register)
---@param opts? TermpickerConfig Optional per-call configuration that overrides global settings
M.pick = function(opts)
	-- Check if termpicker is available before proceeding
	if not ensure_termpicker_available() then
		return
	end
	local mode = vim.api.nvim_get_mode().mode
	local original_win = vim.api.nvim_get_current_win()
	local original_buf = vim.api.nvim_get_current_buf()

	-- Handle visual mode selection
	if mode == 'v' or mode == 'V' or mode == '\22' then -- \22 is visual block mode
		-- Merge per-call options with global config to check preserve_selection
		local merged_opts = vim.tbl_deep_extend('force', config, opts or {})

		-- Get visual mode type before we exit visual mode
		local vmode = vim.fn.visualmode()

		-- Get the selected text first
		vim.cmd('normal! y')
		local selected_text = vim.fn.getreg('"')

		-- Exit visual mode
		vim.api.nvim_feedkeys(
			vim.api.nvim_replace_termcodes('<Esc>', true, false, true), 'n', false)

		if merged_opts.behavior.preserve_selection then
			-- Don't replace selection, treat selected_text as initial color and use configured output
			local initial_color = extract_color_from_text(selected_text)

			pick_color(initial_color, function(color)
				if color == '' then return end

				-- Switch back to original window/buffer
				if vim.api.nvim_win_is_valid(original_win) then
					vim.api.nvim_set_current_win(original_win)
				end
				if vim.api.nvim_buf_is_valid(original_buf) then
					vim.api.nvim_set_current_buf(original_buf)
				end

				-- Use the configured output method instead of replacing selection
				handle_output(color, merged_opts.output)
			end, opts)
			return
		else
			-- Normal behavior: replace the visual selection
			-- Get selection range using vim.fn.getpos which is more reliable
			local start_pos = vim.fn.getpos("'<")
			local end_pos = vim.fn.getpos("'>")

			-- Convert positions: getpos returns 1-based, nvim_buf_set_text expects 0-based
			-- getpos("'>") gives 1-based position of last selected character (inclusive)
			-- nvim_buf_set_text expects 0-based exclusive end position
			-- So: 1-based inclusive -> 0-based exclusive means we keep the value as-is
			local start_row = start_pos[2] - 1
			local start_col = start_pos[3] - 1
			local end_row = end_pos[2] - 1
			local end_col = end_pos[3] -- Keep 1-based value for 0-based exclusive end

			-- Use the selection replacement function
			M.pick_replace_selection(selected_text, start_row, start_col, end_row,
				end_col, opts)
			return
		end
	end

	-- Handle normal/insert/operator-pending modes
	local initial_color = nil
	pick_color(initial_color, function(color)
		if color == '' then return end

		-- Switch back to original window/buffer
		if vim.api.nvim_win_is_valid(original_win) then
			vim.api.nvim_set_current_win(original_win)
		end
		if vim.api.nvim_buf_is_valid(original_buf) then
			vim.api.nvim_set_current_buf(original_buf)
		end

		-- Merge per-call options with global config for output handling
		local merged_opts = vim.tbl_deep_extend('force', config, opts or {})

		if mode == 'i' then
			-- Insert mode: always insert at cursor for better UX, then return to insert mode
			insert_at_cursor(color)
			-- Use defer_fn with longer delay and try 'a' command instead
			vim.defer_fn(function()
				vim.api.nvim_feedkeys('a', 'n', true)
			end, 10)
		else -- normal mode or operator-pending
			-- Use the configured output method (insert at cursor or register)
			handle_output(color, merged_opts.output)
		end
	end, opts)
end

---Get the path to the termpicker binary
---@return string|nil path The path to termpicker binary if it exists
M.termpicker_path = function()
	return installer.termpicker_path()
end

---Install termpicker binary
---@return boolean success True if installation succeeded
M.install_termpicker = function()
	return installer.install_termpicker()
end

---@type TermpickerModule
return M
