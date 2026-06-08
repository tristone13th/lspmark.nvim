local M = {}
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")
local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local previewers = require("telescope.previewers")
local sorters = require("telescope.sorters")
local bookmarks = require("lspmark.bookmarks")
local config = require("lspmark.config")
local highlight = require("telescope._extensions.highlight")
local entry_display = require("telescope.pickers.entry_display")
local utils = require("lspmark.utils")

local function get_field_width(field, widths)
	local width = widths[field]
	local max_width = config.options.telescope.entry_fields.max_widths[field]

	return function(_, max_columns)
		return math.min(width, math.floor(max_width * max_columns))
	end
end

local function display_items(widths)
	return vim.iter(config.options.telescope.entry_fields.order)
		:map(function(field)
			return { width = get_field_width(field, widths) }
		end)
		:totable()
end

local function display_values(entry, file_name)
	return vim.iter(config.options.telescope.entry_fields.order)
		:map(function(field)
			if field == "file" then
				return { file_name }
			elseif field == "kind" then
				return { entry.kind_str, entry.kind_hl_group }
			else
				return { entry[field] }
			end
		end)
		:totable()
end

function M.lspmark(opts)
	opts = opts or {}
	local results = {}
	local protocol = vim.lsp.protocol

	local bufnr = vim.api.nvim_get_current_buf()
	if vim.api.nvim_get_option_value("modified", { buf = bufnr }) then
		bookmarks.lsp_calibrate_bookmarks(bufnr, false, bookmarks.bookmark_file)
	end

	local max_file_name_len, max_kind_len, max_symbol_len, max_line_len, max_comment_len = 0, 0, 0, 0, 0
	for file_name, kinds in pairs(bookmarks.bookmarks) do
		max_file_name_len = math.max(string.len(utils.get_file_name(file_name)), max_file_name_len)
		for kind, name_symbols in pairs(kinds) do
			if kind == bookmarks.plain_magic then
				max_kind_len = math.max(string.len(kind), max_kind_len)
				for _, mark in ipairs(name_symbols) do
					local text = mark.text:match("^%s*(.-)%s*$")
					max_line_len = math.max(string.len(text), max_line_len)
					max_comment_len = math.max(string.len(mark.comment), max_comment_len)
					table.insert(results, {
						filename = file_name,
						kind = kind,
						kind_str = kind,
						kind_hl_group = "Normal",
						lnum = mark.line,
						col = mark.col,
						symbol = "No Symbol",
						text = text,
						comment = mark.comment,
						id = mark.id,
					})
				end
			else
				local kind_hl_group = highlight.symbol_colors[tonumber(kind)]
				local kind_str = protocol.SymbolKind[tonumber(kind)] or "Unknown"
				max_kind_len = math.max(string.len(kind_str), max_kind_len)
				for name, symbols in pairs(name_symbols) do
					max_symbol_len = math.max(string.len(name), max_symbol_len)
					for offset, marks in pairs(symbols) do
						for _, mark in ipairs(marks) do
							local text = mark.text:match("^%s*(.-)%s*$")
							max_line_len = math.max(string.len(text), max_line_len)
							max_comment_len = math.max(string.len(mark.comment), max_comment_len)
							table.insert(results, {
								filename = file_name,
								kind = kind,
								kind_str = kind_str,
								kind_hl_group = kind_hl_group,
								lnum = mark.range[1] + tonumber(offset) + 1,
								offset = offset,
								col = mark.range[3],
								symbol = name,
								text = text,
								comment = mark.comment,
								id = mark.id,
							})
						end
					end
				end
			end
		end
	end

	local display = entry_display.create({
		separator = "  ",
		items = display_items({
			file = max_file_name_len,
			kind = max_kind_len,
			symbol = max_symbol_len,
			text = max_line_len,
			comment = max_comment_len,
		}),
	})

	pickers
		.new(opts, {
			prompt_title = "Bookmarks",
			finder = finders.new_table({
				results = results,
				entry_maker = function(entry)
					local file_name = utils.get_file_name(entry.filename)
					return {
						display = function()
							return display(display_values(entry, file_name))
						end,
						ordinal = entry.comment .. entry.text .. entry.symbol .. entry.kind_str .. file_name,
						filename = entry.filename,
						lnum = entry.lnum,
						col = entry.col,
						kind = entry.kind,
						symbol = entry.symbol,
						offset = entry.offset,
						text = entry.text,
						comment = entry.comment,
						id = entry.id,
					}
				end,
			}),
			previewer = previewers.vim_buffer_vimgrep.new(opts),
			sorter = sorters.get_generic_fuzzy_sorter(),
			attach_mappings = function(prompt_bufnr, map)
				actions.select_default:replace(function()
					local selection = action_state.get_selected_entry()

					-- 0 bookmarks
					if not selection then
						return
					end

					if selection.col < 0 then
						selection.col = 0 -- block negative column index
					end
					actions.close(prompt_bufnr)
					local nr = vim.fn.bufnr(selection.filename, true)
					vim.api.nvim_buf_set_option(nr, "buflisted", true)
					vim.api.nvim_set_current_buf(nr)
					vim.api.nvim_win_set_cursor(0, { selection.lnum, selection.col })
				end)

				actions.close:enhance({
					post = function()
						bookmarks.display_bookmarks(0)
					end,
				})

				map("i", "<CR>", function()
					actions.select_default()
				end)

				map("n", "<CR>", function()
					actions.select_default()
				end)

				map("n", "d", function()
					local s = action_state.get_selected_entry()
					-- 0 bookmarks
					if not s then
						return
					end

					local kinds = bookmarks.bookmarks[s.filename]
					if not kinds then
						print("Cannot find the mark under the cursor")
						return
					end
					local symbols = kinds[s.kind]
					if not symbols then
						print("Cannot find the mark under the cursor")
						return
					end

					local function helper(array)
						local index = 1
						for idx, mark in ipairs(array) do
							if mark.id == s.id then
								index = idx
								break
							end
						end

						table.remove(array, index)
						utils.clear_empty_tables(bookmarks.bookmarks)
						bookmarks.save_bookmarks()
						local current_picker = action_state.get_current_picker(prompt_bufnr)
						current_picker:delete_selection(function() end)
						print("Selected entry deleted.")
					end

					if s.kind == bookmarks.plain_magic then
						helper(symbols)
					else
						local symbol = symbols[s.symbol]
						if not symbol then
							print("Cannot find the mark under the cursor")
							return
						end
						local marks = symbol[tostring(s.offset)]
						if not marks then
							print("Cannot find the mark under the cursor")
							return
						end
						helper(marks)
					end
				end)
				return true
			end,
		})
		:find()
end

return require("telescope").register_extension({
	exports = {
		lspmark = M.lspmark,
	},
})
