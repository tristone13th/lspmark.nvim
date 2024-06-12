local M = {}
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")
local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local previewers = require("telescope.previewers")
local sorters = require("telescope.sorters")
local bookmarks = require("lspmark.bookmarks")

function M.lspmark(opts)
	opts = opts or {}
	local results = {}
	local protocol = vim.lsp.protocol

	for file_name, kinds in pairs(bookmarks.bookmarks) do
		for kind, symbols in pairs(kinds) do
			for name, range in pairs(symbols) do
				table.insert(results, {
					filename = file_name,
					kind = protocol.SymbolKind[tonumber(kind)] or "Unknown",
					lnum = range[1] + 1,
					col = range[3],
					text = name,
				})
			end
		end
	end

	pickers.new(opts, {
		prompt_title = "Bookmarks",
		finder = finders.new_table({
			results = results,
			entry_maker = function(entry)
				local filename = entry.filename:match("^.+/(.+)$")
				return {
					value = entry,
					display = string.format(
						"%s:%d:%d: [%s] %s",
						filename,
						entry.lnum,
						entry.col,
						entry.kind,
						entry.text
					),
					ordinal = entry.text .. entry.kind .. filename,
					filename = entry.filename,
					lnum = entry.lnum,
					col = entry.col,
				}
			end,
		}),
		previewer = previewers.vim_buffer_vimgrep.new(opts),
		sorter = sorters.get_generic_fuzzy_sorter(),
		attach_mappings = function(prompt_bufnr, _)
			actions.select_default:replace(function()
				local selection = action_state.get_selected_entry()
				actions.close(prompt_bufnr)
				vim.api.nvim_set_current_buf(vim.fn.bufnr(selection.filename))
				vim.api.nvim_win_set_cursor(0, { selection.lnum, selection.col - 1 })
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
