local M = {}
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")
local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local previewers = require("telescope.previewers")
local sorters = require("telescope.sorters")
local bookmarks = require("lspmark.bookmarks")
local highlight = require("telescope._extensions.highlight")
local entry_display = require("telescope.pickers.entry_display")

function M.lspmark(opts)
	opts = opts or {}
	local results = {}
	local protocol = vim.lsp.protocol

	local max_file_name_len, max_kind_len, max_symbol_len, max_line_len = 0, 0, 0, 0
	for file_name, kinds in pairs(bookmarks.bookmarks) do
		max_file_name_len = math.max(string.len(file_name:match("^.+/(.+)$")), max_file_name_len)
		for kind, symbols in pairs(kinds) do
			local kind_hl_group = highlight.symbol_colors[tonumber(kind)]
			local kind_str = protocol.SymbolKind[tonumber(kind)] or "Unknown"
			max_kind_len = math.max(string.len(kind_str), max_kind_len)
			for name, symbol in pairs(symbols) do
				max_symbol_len = math.max(string.len(name), max_symbol_len)
				for offset, mark in pairs(symbol.marks) do
					local text = mark.text:match("^%s*(.-)%s*$")
					max_line_len = math.max(string.len(text), max_line_len)
					table.insert(results, {
						filename = file_name,
						kind = kind,
						kind_str = kind_str,
						kind_hl_group = kind_hl_group,
						lnum = symbol.range[1] + tonumber(offset) + 1,
						offset = offset,
						col = symbol.range[3],
						symbol = name,
						text = text,
					})
				end
			end
		end
	end

	local display = entry_display.create({
		separator = "  ",
		items = {
			{ width = max_file_name_len },
			{ width = max_kind_len },
			{ width = max_symbol_len },
			{ width = max_line_len },
			{ remaining = true },
		},
	})

	pickers.new(opts, {
		prompt_title = "Bookmarks",
		finder = finders.new_table({
			results = results,
			entry_maker = function(entry)
				local file_name = entry.filename:match("^.+/(.+)$")
				return {
					display = function()
						return display({
							{ file_name },
							{ entry.kind_str, entry.kind_hl_group },
							{ entry.symbol },
							{ entry.text },
						})
					end,
					ordinal = entry.text .. entry.symbol .. entry.kind_str .. file_name,
					filename = entry.filename,
					lnum = entry.lnum,
					col = entry.col,
					kind = entry.kind,
					symbol = entry.symbol,
					offset = entry.offset,
					text = entry.text,
				}
			end,
		}),
		previewer = previewers.vim_buffer_vimgrep.new(opts),
		sorter = sorters.get_generic_fuzzy_sorter(),
		attach_mappings = function(prompt_bufnr, map)
			actions.select_default:replace(function()
				local selection = action_state.get_selected_entry()
				actions.close(prompt_bufnr)
				vim.api.nvim_set_current_buf(vim.fn.bufnr(selection.filename))
				vim.api.nvim_win_set_cursor(0, { selection.lnum, selection.col - 1 })
			end)

			actions.close:enhance({
				post = function()
					bookmarks.display_bookmarks()
				end,
			})

			map("n", "d", function()
				local s = action_state.get_selected_entry()
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
				local symbol = symbols[s.symbol]
				if not symbol then
					print("Cannot find the mark under the cursor")
					return
				end

				symbol.marks[tostring(s.offset)] = nil
				if vim.tbl_isempty(symbol.marks) then
					symbols[s.symbol] = nil
				end

				bookmarks.save_bookmarks()
				local current_picker = action_state.get_current_picker(prompt_bufnr)
				current_picker:delete_selection(function() end)
				print("Selected entry deleted.")
			end)
			return true
		end,
	}):find()
end

return require("telescope").register_extension({
	exports = {
		lspmark = M.lspmark,
	},
})
