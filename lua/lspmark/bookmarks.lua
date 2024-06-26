local M = {}
local persistence = require("lspmark.persistence")
local utils = require("lspmark.utils")

M.bookmarks = {}
M.text = nil
M.yanked = false
M.marks_in_selection = {}
M.mode = "c"
M.process_selection = false
local ns_id = vim.api.nvim_create_namespace("lspmark")

function M.setup()
	vim.api.nvim_create_autocmd({ "DirChangedPre" }, {
		callback = M.save_bookmarks,
		pattern = { "*" },
	})
	-- Include the case when session is loaded since that will also change the cwd.
	-- Will trigger when vim is launched and load the session
	vim.api.nvim_create_autocmd({ "DirChanged" }, {
		callback = M.load_bookmarks,
		pattern = { "*" },
	})
	-- Lazy calibration
	vim.api.nvim_create_autocmd({ "LspAttach" }, {
		callback = M.on_lsp_attach,
		pattern = { "*" },
	})
	vim.api.nvim_create_autocmd({ "BufEnter" }, {
		callback = M.on_buf_enter,
		pattern = { "*" },
	})
	vim.api.nvim_create_autocmd({ "BufWritePost" }, {
		callback = M.on_buf_write_post,
		pattern = { "*" },
	})
	vim.api.nvim_create_autocmd({ "TextYankPost" }, {
		callback = function()
			M.yanked = true
		end,
		pattern = { "*" },
	})
end

local function get_mark_from_id(id)
	local file_name = vim.api.nvim_buf_get_name(0)
	for _, kind_symbols in pairs(M.bookmarks[file_name]) do
		for _, name_symbols in pairs(kind_symbols) do
			for _, marks in pairs(name_symbols) do
				for index, mark in ipairs(marks) do
					if mark.id == id then
						return { marks = marks, index = index }
					end
				end
			end
		end
	end
end

local function delete_id(id)
	local res = get_mark_from_id(id)
	table.remove(res.marks, res.index)
end

local function create_right_aligned_highlight(text, offset)
	local res = vim.fn.getwininfo(vim.api.nvim_get_current_win())[1]
	local line_width = vim.api.nvim_win_get_width(0) - res.textoff
	local target_col = line_width - string.len(text) + offset
	return target_col
end

function M.display_bookmarks(bufnr)
	if bufnr == 0 then
		bufnr = vim.api.nvim_get_current_buf()
	end

	local icon_group = "lspmark"

	vim.fn.sign_unplace(icon_group, { buffer = bufnr })
	vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)

	local file_name = vim.api.nvim_buf_get_name(bufnr)

	if not M.bookmarks[file_name] then
		return
	end

	local sign_name = "lspmark_symbol"
	local icon = "->"

	if vim.fn.sign_getdefined(sign_name) == nil or #vim.fn.sign_getdefined(sign_name) == 0 then
		vim.fn.sign_define(sign_name, { text = icon, texthl = "LspMark", numhl = "LspMark" })
	end

	for _, kind_symbols in pairs(M.bookmarks[file_name]) do
		for _, name_symbols in pairs(kind_symbols) do
			for offset, marks in pairs(name_symbols) do
				for _, mark in ipairs(marks) do
					local start_line = mark.range[1] -- Convert to 1-based indexing

					local line = start_line + tonumber(offset)
					local id = vim.fn.sign_place(0, icon_group, sign_name, bufnr, { lnum = line + 1, priority = 100 })
					mark.id = id

					local comment = mark.comment
					-- -1 for placing other signs such as gitsigns
					if string.len(mark.comment) > 15 then
						comment = string.sub(mark.comment, 1, 13) .. ".."
					end
					local col = create_right_aligned_highlight(comment, -1)
					local opts = {
						virt_text = { { comment, "LspMarkComment" } },
						virt_text_pos = "overlay",
						hl_mode = "combine",
						virt_text_win_col = col,
					}
					vim.api.nvim_buf_set_extmark(bufnr, ns_id, line, 0, opts)
				end
			end
		end
	end
end

function M.get_document_symbol(bufnr)
	if bufnr == nil then
		bufnr = vim.api.nvim_get_current_buf()
	end

	local cursor = vim.api.nvim_win_get_cursor(0)
	local line, _ = cursor[1] - 1, cursor[2]
	local params = vim.lsp.util.make_position_params()
	local result, err = vim.lsp.buf_request_sync(bufnr, "textDocument/documentSymbol", params, 1000)

	if err then
		print("Error getting semantic tokens: ", err)
		return
	end

	if not result or vim.tbl_isempty(result) then
		print("No symbols found")
		return
	end

	for client_id, response in pairs(result) do
		if response.result then
			for _, symbol in ipairs(response.result) do
				-- selection range is the same, all need to be modified is following:
				-- local sr = symbol.selectionRange
				if symbol.location then -- SymbolInformation type
					symbol.range = symbol.location.range
				end
				local r = symbol.range

				if utils.is_position_in_range(line, r.start.line, r["end"].line) then
					return symbol
				end
			end
		elseif response.error then
			print("Error from client ID: ", client_id, response.error)
		end
	end

	return nil
end

local function _modify_comment(marks, index)
	vim.ui.input({ prompt = "Input new comment: ", default = marks[index].comment }, function(input)
		if input ~= nil then
			marks[index].comment = input
			M.save_bookmarks()
			M.display_bookmarks(0)
		end
	end)
end

function M.create_bookmark(symbol, with_comment)
	if not symbol then
		return
	end

	local file_name = vim.api.nvim_buf_get_name(0)

	if not M.bookmarks[file_name] then
		M.bookmarks[file_name] = {}
	end

	local l1 = M.bookmarks[file_name]
	if not l1[tostring(symbol.kind)] then
		l1[tostring(symbol.kind)] = {}
	end

	local l2 = l1[tostring(symbol.kind)]
	if not l2[symbol.name] then
		l2[symbol.name] = {}
	end

	if symbol.location then -- SymbolInformation type
		symbol.range = symbol.location.range
	end
	local r = symbol.range
	local l3 = l2[symbol.name]
	local cursor = vim.api.nvim_win_get_cursor(0)
	local offset, character = cursor[1] - r.start.line - 1, cursor[2]
	if not l3[tostring(offset)] then
		l3[tostring(offset)] = {}
	end

	table.insert(l3[tostring(offset)], {
		range = {
			r.start.line,
			r["end"].line,
			r.start.character,
			r["end"].character,
		},
		col = character,
		text = vim.api.nvim_get_current_line(),
		comment = "",
		details = symbol.details,
		symbol_text = utils.remove_blanks(
			table.concat(utils.get_text(r.start.line + 1, r["end"].line + 1, r.start.character, r["end"].character), "")
		),
	})

	if with_comment then
		_modify_comment(l3[tostring(offset)], #l3[tostring(offset)])
	else
		M.save_bookmarks()
		M.display_bookmarks(0)
	end
end

local function match(lsp_symbols, mark)
	local index = 1
	local min = 2147483647
	for i, symbol in ipairs(lsp_symbols) do
		if symbol.location then -- SymbolInformation type
			symbol.range = symbol.location.range
		end
		local r = symbol.range
		local lsp_text = table.concat(
			utils.get_text(r.start.line + 1, r["end"].line + 1, r.start.character, r["end"].character),
			""
		)
		lsp_text = utils.remove_blanks(lsp_text)
		local s = utils.levenshtein(mark.symbol_text, lsp_text)
		if s < min then
			min = s
			index = i
		end
	end

	return index
end

function M.delete_bookmark()
	local bufnr = vim.api.nvim_get_current_buf()
	local cursor = vim.api.nvim_win_get_cursor(0)
	local extmarks = vim.fn.sign_getplaced(bufnr, { group = "lspmark" })
	for _, marks in ipairs(extmarks) do
		for _, sign in ipairs(marks.signs) do
			if sign.lnum == cursor[1] then
				delete_id(sign.id)
			end
		end
	end

	M.save_bookmarks()
	M.display_bookmarks(0)
end

-- Do we have a bookmark in current cursor?
function M.has_bookmark()
	local bufnr = vim.api.nvim_get_current_buf()
	-- We suppose all the boobmarks are up-to-date

	local cursor = vim.api.nvim_win_get_cursor(0)
	-- The following cover the case when we want to toggle a bookmark
	-- and the buffer is modified, it is a corner case, so comment this.
	local extmarks = vim.fn.sign_getplaced(bufnr, { group = "lspmark" })
	for _, marks in ipairs(extmarks) do
		for _, sign in ipairs(marks.signs) do
			if sign.lnum == cursor[1] then
				return get_mark_from_id(sign.id)
			end
		end
	end

	return false
end

function M.toggle_bookmark(opts)
	local bufnr = vim.api.nvim_get_current_buf()
	local with_comment = false
	if opts then
		with_comment = opts.with_comment
	end

	if vim.api.nvim_get_option_value("modified", { buf = bufnr }) then
		print("Could toggle bookmark, please save the buffer first.")
		return
	end

	local symbol = M.get_document_symbol()

	if not symbol then
		print("Couldn't match a LSP symbol under the cursor.")
		return
	end

	local res = M.has_bookmark()
	if res then
		M.delete_bookmark()
	else
		M.create_bookmark(symbol, with_comment)
	end
end

function M.modify_comment()
	local bufnr = vim.api.nvim_get_current_buf()

	if vim.api.nvim_get_option_value("modified", { buf = bufnr }) then
		print("Could toggle bookmark, please save the buffer first.")
		return
	end

	local symbol = M.get_document_symbol()

	if not symbol then
		print("Couldn't match a LSP symbol under the cursor.")
		return
	end

	local res = M.has_bookmark()
	if res then
		_modify_comment(res.marks, res.index)
	else
		print("Couldn't find a bookmark under the cursor.")
	end
end

function M.show_comment()
	local bufnr = vim.api.nvim_get_current_buf()

	if vim.api.nvim_get_option_value("modified", { buf = bufnr }) then
		print("Could toggle bookmark, please save the buffer first.")
		return
	end

	local symbol = M.get_document_symbol()

	if not symbol then
		print("Couldn't match a LSP symbol under the cursor.")
		return
	end

	local res = M.has_bookmark()
	if res then
		print(res.marks[res.index].comment)
	else
		print("Couldn't find a bookmark under the cursor.")
	end
end

-- function M.display_all_bookmarks()
-- 	for file_name, _ in pairs(M.bookmarks) do
-- 		local buffers = utils.get_buffers_for_file(file_name)
-- 		for _, bufnr in ipairs(buffers) do
-- 			M.display_bookmarks(bufnr)
-- 		end
-- 	end
-- end
--
function M.on_lsp_attach(event)
	M.lsp_calibrate_bookmarks(event.buf)
end

function M.on_buf_enter(event)
	M.display_bookmarks(event.buf)
end

function M.on_buf_write_post(event)
	M.lsp_calibrate_bookmarks(event.buf)
end

-- We store each mark in a relative way, so we don't need
-- to modify the offset value. What we need is updated the
-- text information and the start line of each LSP symbol.
-- Also delete the marks if their symbol is deleted.
-- lsp.format() can only affect the marks in the formated symbols,
-- Let's hope we do format frequently so each time the file is not huge-changed.
function M.lsp_calibrate_bookmarks(bufnr)
	if bufnr == nil then
		bufnr = vim.api.nvim_get_current_buf()
	end
	local file_name = vim.api.nvim_buf_get_name(bufnr)
	if (not vim.tbl_isempty(M.bookmarks) and M.bookmarks[file_name] ~= nil) or M.process_selection then
		local params = vim.lsp.util.make_position_params()
		vim.lsp.buf_request(bufnr, "textDocument/documentSymbol", params, function(err, result)
			if err then
				vim.api.nvim_err_writeln("Error getting semantic tokens: " .. err.message)
				return
			end
			if not result or vim.tbl_isempty(result) then
				print("Empty LSP result.")
				return
			end

			if M.process_selection then
				for _, mark in ipairs(M.marks_in_selection) do
					for _, symbol in ipairs(result) do
						if symbol.location then -- SymbolInformation type
							symbol.range = symbol.location.range
						end
						local r = symbol.range
						if mark.line and utils.is_position_in_range(mark.line, r.start.line, r["end"].line) then
							if not M.bookmarks[file_name] then
								M.bookmarks[file_name] = {}
							end
							if not M.bookmarks[file_name][tostring(symbol.kind)] then
								M.bookmarks[file_name][tostring(symbol.kind)] = {}
							end
							local kind_symbols = M.bookmarks[file_name][tostring(symbol.kind)]
							if not kind_symbols[symbol.name] then
								kind_symbols[symbol.name] = {}
							end
							local name_symbols = kind_symbols[symbol.name]
							local new_offset = mark.line - r.start.line - 1
							if not name_symbols[tostring(new_offset)] then
								name_symbols[tostring(new_offset)] = {}
							end

							table.insert(name_symbols[tostring(new_offset)], {
								range = {
									r.start.line,
									r["end"].line,
									r.start.character,
									r["end"].character,
								},
								col = 0,
								text = vim.api.nvim_buf_get_lines(bufnr, mark.line, mark.line + 1, false)[1],
								comment = "",
								details = symbol.details,
								symbol_text = utils.remove_blanks(
									table.concat(
										utils.get_text(
											r.start.line + 1,
											r["end"].line + 1,
											r.start.character,
											r["end"].character
										),
										""
									)
								),
							})
						end
					end
				end
			end

			-- calibrate each mark using LSP information
			for kind, kind_symbols in pairs(M.bookmarks[file_name]) do
				for name, name_symbols in pairs(kind_symbols) do
					-- Get all LSP symbols with the same kind and name
					local same_name_symbols = {}
					for _, s in ipairs(result) do
						if s.name == name and tostring(s.kind) == kind then
							table.insert(same_name_symbols, s)
						end
					end

					-- Find the most suitable LSP symbol for each mark
					for offset, marks in pairs(name_symbols) do
						for _, mark in ipairs(marks) do
							local idx = match(same_name_symbols, mark)
							local symbol = same_name_symbols[idx]

							local r = symbol.range
							mark.range = {
								r.start.line,
								r["end"].line,
								r.start.character,
								r["end"].character,
							}
							mark.details = symbol.details
							local line = tonumber(offset) + r.start.line
							mark.text = vim.api.nvim_buf_get_lines(bufnr, line, line + 1, false)[1]
							mark.symbol_text = utils.remove_blanks(
								table.concat(
									utils.get_text(
										r.start.line + 1,
										r["end"].line + 1,
										r.start.character,
										r["end"].character
									),
									""
								)
							)
						end
					end
				end
			end

			-- Calibrate each mark's information (mainly offset) using sign information
			-- The following cover the case when we want to toggle a bookmark
			-- and the buffer is modified, it is a corner case, so comment this.
			local extmarks = vim.fn.sign_getplaced(bufnr, { group = "lspmark" })
			for _, marks in ipairs(extmarks) do
				for _, sign in ipairs(marks.signs) do
					for kind, kind_symbols in pairs(M.bookmarks[file_name]) do
						for name, name_symbols in pairs(kind_symbols) do
							for _, bookmarks in pairs(name_symbols) do
								for index, mark in ipairs(bookmarks) do
									if mark.id == sign.id then
										local new_offset = sign.lnum - bookmarks[index].range[1] - 1
										table.remove(bookmarks, index)

										local l1 = M.bookmarks[file_name]
										if not l1[tostring(kind)] then
											l1[tostring(kind)] = {}
										end
										local l2 = l1[tostring(kind)]
										if not l2[name] then
											l2[name] = {}
										end
										local l3 = l2[name]
										if not l3[tostring(new_offset)] then
											l3[tostring(new_offset)] = {}
										end

										table.insert(l3[tostring(new_offset)], {
											range = mark.range,
											col = mark.col,
											text = mark.text,
											comment = mark.comment,
											details = mark.details,
											symbol_text = mark.symbol_text,
										})
									end
								end
							end
						end
					end
				end
			end

			M.process_selection = false
			M.save_bookmarks()
			M.display_bookmarks(bufnr)
		end)
	else
		M.display_bookmarks(bufnr)
	end
end

function M.load_bookmarks()
	M.bookmarks = persistence.load()
end

function M.save_bookmarks()
	persistence.save(M.bookmarks)
end

function M.delete_line()
	-- get all bookmarks in the selection
	M.marks_in_selection = {}
	M.process_selection = false
	local bufnr = vim.api.nvim_get_current_buf()
	local extmarks = vim.fn.sign_getplaced(bufnr, { group = "lspmark" })
	local cursor = vim.api.nvim_win_get_cursor(0)
	for _, marks in ipairs(extmarks) do
		for _, sign in ipairs(marks.signs) do
			if utils.is_position_in_range(sign.lnum, cursor[1], cursor[1]) then
				table.insert(M.marks_in_selection, { offset_in_selection = 0 })
				delete_id(sign.id)
			end
		end
	end
	local lines = vim.api.nvim_buf_get_lines(0, cursor[1] - 1, cursor[1], false)
	M.mode = "l"
	M.text = lines[1]
	vim.api.nvim_buf_set_lines(bufnr, cursor[1] - 1, cursor[1], false, {})
	M.yanked = false
end

local function get_visual_selection()
	local s_start = vim.fn.getpos("'<")
	local s_end = vim.fn.getpos("'>")
	local start_line = s_start[2]
	local end_line = s_end[2]
	local start_c = s_start[3]
	local end_c = s_end[3]

	-- get all bookmarks in the selection
	local bufnr = vim.api.nvim_get_current_buf()
	local extmarks = vim.fn.sign_getplaced(bufnr, { group = "lspmark" })

	for _, marks in ipairs(extmarks) do
		for _, sign in ipairs(marks.signs) do
			if utils.is_position_in_range(sign.lnum, start_line, end_line) then
				table.insert(M.marks_in_selection, { offset_in_selection = sign.lnum - start_line })
				delete_id(sign.id)
			end
		end
	end

	local lines = utils.get_text(start_line, end_line, start_c, end_c)

	if end_c == 2147483647 then
		M.mode = "l"
	else
		M.mode = "c"
	end

	return table.concat(lines, "\n")
end

local function split_text(text)
	local sep = "\n"
	local t = {}
	for str in string.gmatch(text, "([^" .. sep .. "]+)") do
		table.insert(t, str)
	end
	return t
end

function M.paste_text()
	if not M.yanked then
		if M.text ~= nil then
			local cursor = vim.api.nvim_win_get_cursor(0)
			vim.api.nvim_put(split_text(M.text), M.mode, true, false)
			for _, mark in ipairs(M.marks_in_selection) do
				if M.mode == "l" then
					mark.line = mark.offset_in_selection + cursor[1] + 1
				else
					mark.line = mark.offset_in_selection + cursor[1]
				end
			end
			if not vim.tbl_isempty(M.marks_in_selection) then
				M.process_selection = true
			else
				M.process_selection = false
			end
			vim.cmd("silent! w")
		end
	else
		vim.cmd("normal! p")
	end
end

function M.delete_visual_selection()
	M.marks_in_selection = {}
	M.process_selection = false
	M.text = get_visual_selection()
	vim.cmd('normal! gv"') -- Re-select the last selected text
	vim.cmd('normal! "_d') -- Delete the selected text without affecting registers
	M.yanked = false
end

return M
