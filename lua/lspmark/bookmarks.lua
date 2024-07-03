local M = {}
local persistence = require("lspmark.persistence")
local utils = require("lspmark.utils")

M.bookmarks = {}
M.text = nil
M.yanked = false
M.marks_in_selection = {}
M.mode = "c"
local sign_info = {}
local icon_group = "lspmark"
local sign_name = "lspmark_symbol"
local icon = "->"
local ns_id = vim.api.nvim_create_namespace("lspmark")
local virt_text_opts = {
	virt_text = { { "", "LspMarkComment" } },
	virt_text_pos = "overlay",
	hl_mode = "combine",
	undo_restore = true,
}

local function create_bookmark(symbol, line, col, id, with_comment)
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
	local offset, character = line - r.start.line - 1, col
	if not l3[tostring(offset)] then
		l3[tostring(offset)] = {}
	end
	table.insert(l3[tostring(offset)], {
		id = id,
		range = {
			r.start.line,
			r["end"].line,
			r.start.character,
			r["end"].character,
		},
		col = character,
		text = vim.api.nvim_buf_get_lines(0, line - 1, line, false)[1],
		comment = "",
		details = symbol.details,
		symbol_text = utils.remove_blanks(
			table.concat(utils.get_text(r.start.line + 1, r["end"].line + 1, r.start.character, r["end"].character), "")
		),
	})
	if with_comment then
		l3[tostring(offset)][#l3[tostring(offset)]].comment = with_comment
	end
end

local function match(lsp_symbols, mark)
	if #lsp_symbols == 1 then
		return 1
	end
	local index = 0
	local min = 2147483647
	-- First match details
	if mark.details then
		local values = {}
		for i, symbol in ipairs(lsp_symbols) do
			if not symbol.details then
				symbol.details = ""
			end
			local score
			if symbol.details == "" or mark.details == "" then
				score = 2147483647
			else
				score = utils.levenshtein(symbol.details, mark.details)
			end
			if score < min then
				index = i
				min = score
			end
			values[tostring(score)] = "lspmark"
		end
		local num = 0
		for _, _ in pairs(values) do
			num = num + 1
		end
		if num > 1 then
			return index
		end
	end
	index = 0
	min = 2147483647
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

-- 2 phases calibration:
--   1. Precise calibration: calibrate each mark's offset and other stuffs using
--      sign/symbol information which is up-to-date.
--   2. Rough calibration: calibrate each mark's other stuffs only using LSP symbol
--      information when it doesn't have a corresponding sign.
local function lsp_calibrate_bookmarks(bufnr, async)
	if bufnr == nil then
		bufnr = vim.api.nvim_get_current_buf()
	end
	if async == nil then
		async = true
	end
	local file_name = vim.api.nvim_buf_get_name(bufnr)
	if not vim.tbl_isempty(M.bookmarks) and M.bookmarks[file_name] ~= nil then
		local function helper(result)
			if not result or vim.tbl_isempty(result) then
				print("Empty LSP result.")
				return
			end
			-- Calibrate each mark's information (mainly offset) using sign information.
			--
			-- If a sign has a corresponding mark, then calibrate the mark with the sign's info
			-- since the sign is always up-to-date (Such as when the buffer is modified).
			--
			-- If a sign doesn't have a corresponding mark, then create the mark. This relates to
			-- the case we pasted the text with marks included.
			local extmarks = vim.fn.sign_getplaced(bufnr, { group = "lspmark" })
			for _, marks in ipairs(extmarks) do
				for _, sign in ipairs(marks.signs) do
					local matched = false
					for _, kind_symbols in pairs(M.bookmarks[file_name]) do
						for _, name_symbols in pairs(kind_symbols) do
							for _, bookmarks in pairs(name_symbols) do
								for index, mark in ipairs(bookmarks) do
									if mark.id == sign.id then
										for _, s in ipairs(result) do
											if s.location then -- SymbolInformation type
												s.range = s.location.range
											end
											local r = s.range
											if
												utils.is_position_in_range(sign.lnum - 1, r.start.line, r["end"].line)
											then
												matched = true
												local new_offset = sign.lnum - r.start.line - 1
												table.remove(bookmarks, index)
												local l1 = M.bookmarks[file_name]
												if not l1[tostring(s.kind)] then
													l1[tostring(s.kind)] = {}
												end
												local l2 = l1[tostring(s.kind)]
												if not l2[s.name] then
													l2[s.name] = {}
												end
												local l3 = l2[s.name]
												if not l3[tostring(new_offset)] then
													l3[tostring(new_offset)] = {}
												end
												table.insert(l3[tostring(new_offset)], {
													range = {
														r.start.line,
														r["end"].line,
														r.start.character,
														r["end"].character,
													},
													col = mark.col,
													text = vim.api.nvim_buf_get_lines(
														bufnr,
														sign.lnum - 1,
														sign.lnum,
														false
													)[1],
													comment = mark.comment,
													details = s.details,
													symbol_text = utils.remove_blanks(
														table.concat(
															utils.get_text(
																r.start.line + 1,
																r["end"].line + 1,
																r.start.character,
																r["end"].character,
																bufnr
															),
															""
														)
													),
													calibrated = true,
												})
											end
										end
									end
								end
							end
						end
					end
					-- This sign is created when pasting, create a new bookmark for it
					if not matched then
						for _, s in ipairs(result) do
							if s.location then -- SymbolInformation type
								s.range = s.location.range
							end
							local r = s.range
							if utils.is_position_in_range(sign.lnum - 1, r.start.line, r["end"].line) then
								create_bookmark(s, sign.lnum, 0, sign.id, sign_info[tostring(sign.id)] or "")
							end
						end
					end
				end
			end
			sign_info = {}
			-- Fallback to calibrate each mark using LSP information.
			--
			-- Not all bookmarks will get calibrated in the first phase using signs,
			-- if we format a buffer then all the signs will get lost. thus we need to
			-- calibrate the bookmarks with the LSP information, we don't need to update
			-- the offset for each mark, we need to update the information related to the mark
			-- such as line text and symbol text.
			for kind, kind_symbols in pairs(M.bookmarks[file_name]) do
				for name, name_symbols in pairs(kind_symbols) do
					-- Get all LSP symbols with the same kind and name
					local same_name_symbols = {}
					for _, s in ipairs(result) do
						if s.name == name and tostring(s.kind) == kind then
							table.insert(same_name_symbols, s)
						end
					end
					-- Delete the marks if it doesn't match any symbol.
					-- We don't need to delete the sign since it will be cleared
					-- when calling display()
					if vim.tbl_isempty(same_name_symbols) then
						kind_symbols[name] = nil
					else
						-- Find the most suitable LSP symbol for each mark
						for offset, bookmarks in pairs(name_symbols) do
							for _, mark in ipairs(bookmarks) do
								if not mark.calibrated then
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
									local line = tonumber(offset) + r.start.line + 1
									mark.text = vim.api.nvim_buf_get_lines(bufnr, line - 1, line, false)[1]
									mark.symbol_text = utils.remove_blanks(
										table.concat(
											utils.get_text(
												r.start.line + 1,
												r["end"].line + 1,
												r.start.character,
												r["end"].character,
												bufnr
											),
											""
										)
									)
								end
								mark.calibrated = false
							end
						end
					end
				end
			end
			M.save_bookmarks()
			M.display_bookmarks(bufnr)
		end
		local params = vim.lsp.util.make_position_params()

		if async then
			vim.lsp.buf_request_all(bufnr, "textDocument/documentSymbol", params, function(result)
				if not result or vim.tbl_isempty(result) or not result[1] then
					print("Empty LSP result.")
					return
				end
				result = result[1].result
				helper(result)
			end)
		else
			local result, err = vim.lsp.buf_request_sync(bufnr, "textDocument/documentSymbol", params, 1000)
			if err then
				print("Some errors when getting semantic tokens: ", err)
				return
			end
			if not result or vim.tbl_isempty(result) then
				print("Empty LSP result.")
				return
			end

			-- calibrate
			for client_id, response in pairs(result) do
				if response.result then
					helper(response.result)
				elseif response.error then
					print("Error from client ID: ", client_id, response.error)
				end
			end
		end
	else
		M.display_bookmarks(bufnr)
	end
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

	vim.fn.sign_unplace(icon_group, { buffer = bufnr })
	vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)

	local file_name = vim.api.nvim_buf_get_name(bufnr)

	if not M.bookmarks[file_name] then
		return
	end

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

					local comment = utils.string_truncate(mark.comment, 15)
					local col = create_right_aligned_highlight(comment, -1)
					virt_text_opts.virt_text_win_col = col
					virt_text_opts.virt_text[1][1] = comment
					vim.api.nvim_buf_set_extmark(bufnr, ns_id, line, 0, virt_text_opts)
				end
			end
		end
	end
end

local function delete_bookmark()
	local bufnr = vim.api.nvim_get_current_buf()
	local cursor = vim.api.nvim_win_get_cursor(0)
	local extmarks = vim.fn.sign_getplaced(bufnr, { group = "lspmark" })
	for _, marks in ipairs(extmarks) do
		for _, sign in ipairs(marks.signs) do
			if sign.lnum == cursor[1] then
				delete_id(sign.id)
				vim.fn.sign_unplace(icon_group, { buffer = bufnr, id = sign.id })
			end
		end
	end

	lsp_calibrate_bookmarks()
end

-- Do we have a bookmark in current cursor? We judge
-- this by seeing if there is a sign placed. This may not
-- accurate since if a format is triggered first then all the signs
-- are removed. So sometimes we cannot create a bookmark even if no
-- sign placed there.
local function has_bookmark()
	local bufnr = vim.api.nvim_get_current_buf()
	-- We suppose all the boobmarks are up-to-date

	local cursor = vim.api.nvim_win_get_cursor(0)
	-- The following cover the case when we want to toggle a bookmark
	-- and the buffer is modified, it is a corner case, so comment this.
	local extmarks = vim.fn.sign_getplaced(bufnr, { group = "lspmark" })
	for _, marks in ipairs(extmarks) do
		for _, sign in ipairs(marks.signs) do
			if sign.lnum == cursor[1] then
				return sign.id
			end
		end
	end

	return false
end

local function modify_comment(id)
	local res = get_mark_from_id(id)
	local default_input = ""
	if res ~= nil then
		default_input = res.marks[res.index].comment
	end
	vim.ui.input({ prompt = "Input new comment: ", default = default_input }, function(input)
		-- Modify the comment on a sign that just pasted currently doesn't have a mark
		if input ~= nil then
			sign_info[tostring(id)] = input
		end

		-- Modify the comment of an existing mark
		if res ~= nil then
			res.marks[res.index].comment = input
		end
	end)
end

function M.toggle_bookmark(opts)
	local bufnr = vim.api.nvim_get_current_buf()
	local with_comment = false
	if opts then
		with_comment = opts.with_comment
	end

	lsp_calibrate_bookmarks(nil, false)
	local line = vim.api.nvim_win_get_cursor(0)[1]
	local id = has_bookmark()
	if id ~= false then
		delete_bookmark()
	else
		id = vim.fn.sign_place(0, icon_group, sign_name, bufnr, { lnum = line, priority = 100 })
		if with_comment then
			modify_comment(id)
		end
		lsp_calibrate_bookmarks()
	end
end

function M.modify_comment()
	lsp_calibrate_bookmarks(nil, false)
	local id = has_bookmark()
	if id ~= false then
		modify_comment(id)
	else
		print("Couldn't find a bookmark under the cursor.")
	end

	lsp_calibrate_bookmarks()
end

function M.show_comment()
	local bufnr = vim.api.nvim_get_current_buf()

	if vim.api.nvim_get_option_value("modified", { buf = bufnr }) then
		print("Could toggle bookmark, please save the buffer first.")
		return
	end

	local id = has_bookmark()
	if id ~= false then
		local res = get_mark_from_id(id)
		print(res.marks[res.index].comment)
	else
		print("Couldn't find a bookmark under the cursor.")
	end
end

local function on_lsp_attach(event)
	lsp_calibrate_bookmarks(event.buf)
end

local function on_buf_enter(event)
	M.display_bookmarks(event.buf)
end

local function on_buf_write_post(event)
	lsp_calibrate_bookmarks(event.buf)
end

function M.load_bookmarks()
	M.bookmarks = persistence.load()
end

function M.save_bookmarks()
	persistence.save(M.bookmarks)
end

-- Get the range of texts, delete the bookmarks inside, remove the comment
local function get_range_texts(start_line, end_line, start_c, end_c)
	-- get all bookmarks in the selection
	local bufnr = vim.api.nvim_get_current_buf()
	local extmarks = vim.fn.sign_getplaced(bufnr, { group = "lspmark" })

	for _, marks in ipairs(extmarks) do
		for _, sign in ipairs(marks.signs) do
			if utils.is_position_in_range(sign.lnum, start_line, end_line) then
				local mark = get_mark_from_id(sign.id)
				local comment
				if mark then
					comment = mark.marks[mark.index].comment
				else
					comment = ""
				end
				table.insert(M.marks_in_selection, { offset_in_selection = sign.lnum - start_line, comment = comment })
				delete_id(sign.id)
				-- Delete virtual text
				vim.api.nvim_buf_clear_namespace(bufnr, ns_id, start_line - 1, end_line)
			end
		end
	end

	local lines = utils.get_text(start_line, end_line, start_c, end_c, bufnr)

	if end_c == 2147483647 then
		M.mode = "l"
	else
		M.mode = "c"
	end

	return table.concat(lines, "\n")
end

function M.paste_text()
	if not M.yanked then
		if M.text ~= nil then
			local cursor = vim.api.nvim_win_get_cursor(0)
			local bufnr = vim.api.nvim_get_current_buf()
			vim.api.nvim_put(utils.split_text(M.text), M.mode, true, false)
			for _, mark in ipairs(M.marks_in_selection) do
				local line
				if M.mode == "l" then
					line = mark.offset_in_selection + cursor[1] + 1
				else
					line = mark.offset_in_selection + cursor[1]
				end

				if vim.fn.sign_getdefined(sign_name) == nil or #vim.fn.sign_getdefined(sign_name) == 0 then
					vim.fn.sign_define(sign_name, { text = icon, texthl = "LspMark", numhl = "LspMark" })
				end

				local id = vim.fn.sign_place(0, icon_group, sign_name, bufnr, { lnum = line, priority = 100 })
				sign_info[tostring(id)] = mark.comment
			end

			lsp_calibrate_bookmarks(bufnr)
		end
	else
		vim.cmd("normal! p")
	end
end

function M.delete_visual_selection()
	M.marks_in_selection = {}
	local s_start = vim.fn.getpos("'<")
	local s_end = vim.fn.getpos("'>")
	M.text = get_range_texts(s_start[2], s_end[2], s_start[3], s_end[3])
	vim.cmd('normal! gv"') -- Re-select the last selected text
	vim.cmd('normal! "_d') -- Delete the selected text without affecting registers
	M.yanked = false
end

function M.delete_line()
	M.marks_in_selection = {}
	-- get all bookmarks in the selection
	local cursor = vim.api.nvim_win_get_cursor(0)
	M.text = get_range_texts(cursor[1], cursor[1], 1, 2147483647)
	vim.api.nvim_buf_set_lines(0, cursor[1] - 1, cursor[1], false, {})
	M.yanked = false
end

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
		callback = on_lsp_attach,
		pattern = { "*" },
	})
	vim.api.nvim_create_autocmd({ "BufEnter" }, {
		callback = on_buf_enter,
		pattern = { "*" },
	})
	vim.api.nvim_create_autocmd({ "BufWritePost" }, {
		callback = on_buf_write_post,
		pattern = { "*" },
	})
	vim.api.nvim_create_autocmd({ "TextYankPost" }, {
		callback = function()
			M.yanked = true
		end,
		pattern = { "*" },
	})
end

return M
