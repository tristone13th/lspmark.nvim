local M = {}
local persistence = require("lspmark.persistence")
local utils = require("lspmark.utils")

M.bookmark_file = nil
M.bookmarks = {}
M.text = nil
M.yanked = false
M.marks_in_selection = {}
M.mode = "c"
M.plain_magic = "Plain"
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

-- SymbolInformation type will have symbol.location.range
-- rather than symbol.range, keep them consistent.
local function ensure_lsp_symbol_range(symbol)
	if symbol.location then -- SymbolInformation type
		symbol.range = symbol.location.range
	end
	return symbol.range
end

local function ensure_sign_defined()
	if vim.fn.sign_getdefined(sign_name) == nil or #vim.fn.sign_getdefined(sign_name) == 0 then
		vim.fn.sign_define(sign_name, { text = icon, texthl = "LspMark", numhl = "LspMark" })
	end
end

-- 2 types of path:
--  1. LSP mark path: bookmarks[file_name][kind][name][offset][index]
--  2. Plain mark path: bookmarks[file_name][kind][index]
local function ensure_path_valid(file_name, kind, name, offset)
	if not M.bookmarks[file_name] then
		M.bookmarks[file_name] = {}
	end
	local l1 = M.bookmarks[file_name]
	if not l1[tostring(kind)] then
		l1[tostring(kind)] = {}
	end
	if name == nil then
		return l1
	end
	local l2 = l1[tostring(kind)]
	if not l2[name] then
		l2[name] = {}
	end
	local l3 = l2[name]
	if not l3[tostring(offset)] then
		l3[tostring(offset)] = {}
	end
	return l3
end

local function create_bookmark(symbol, line, col, with_comment)
	local file_name = utils.standarize_path(vim.api.nvim_buf_get_name(0))
	-- Create a plain bookmark
	if symbol == nil then
		local l1 = ensure_path_valid(file_name, M.plain_magic)
		local mark = {
			line = line,
			col = col,
			text = vim.api.nvim_buf_get_lines(0, line - 1, line, false)[1],
			comment = with_comment,
		}
		table.insert(l1[M.plain_magic], mark)
		return mark
	end

	local r = ensure_lsp_symbol_range(symbol)
	local offset, character = line - r.start.line - 1, col
	local l3 = ensure_path_valid(file_name, symbol.kind, symbol.name, offset)
	local mark = {
		range = {
			r.start.line,
			r["end"].line,
			r.start.character,
			r["end"].character,
		},
		col = character,
		text = vim.api.nvim_buf_get_lines(0, line - 1, line, false)[1],
		comment = with_comment,
		details = symbol.details,
		symbol_text = utils.remove_blanks(
			table.concat(utils.get_text(r.start.line + 1, r["end"].line + 1, r.start.character, r["end"].character), "")
		),
	}
	table.insert(l3[tostring(offset)], mark)
	return mark
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
		local r = ensure_lsp_symbol_range(symbol)
		local lsp_text =
			table.concat(utils.get_text(r.start.line + 1, r["end"].line + 1, r.start.character, r["end"].character), "")
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
-- Be careful that sometimes you call this function in a directory (such as when bufleave)
-- but the async result returns in another directory. Current we use bookmark_file to
-- identify this.
function M.lsp_calibrate_bookmarks(bufnr, async, bookmark_file)
	if bufnr == nil or bufnr == 0 then
		bufnr = vim.api.nvim_get_current_buf()
	end
	if async == nil then
		async = true
	end
	local file_name = utils.standarize_path(vim.api.nvim_buf_get_name(bufnr))

	-- Don't send the request to LSP server if both are empty
	utils.clear_empty_tables(M.bookmarks)
	if vim.tbl_isempty(vim.fn.sign_getplaced(bufnr, { group = "lspmark" })) and M.bookmarks[file_name] == nil then
		return
	end

	local function helper(result)
		-- Calibrate each mark's information (mainly offset) using sign information.
		--
		-- If a sign has a corresponding mark, then calibrate the lsp/plain mark with the sign's info
		-- since the sign is always up-to-date (Such as when the buffer is modified).
		--
		-- If a sign doesn't have a corresponding mark, then create the lsp/plain mark.
		-- This relates to the case we create/paste the text with marks included.
		local extmarks = vim.fn.sign_getplaced(bufnr, { group = "lspmark" })
		for _, marks in ipairs(extmarks) do
			for _, sign in ipairs(marks.signs) do
				local matched = false
				if M.bookmarks[file_name] ~= nil then
					for kind, kind_symbols in pairs(M.bookmarks[file_name]) do
						-- First calibrate the plain mark which may not correct due to modified file
						if kind == M.plain_magic then
							for i = #kind_symbols, 1, -1 do
								local mark = kind_symbols[i]
								if mark.id == sign.id then
									matched = true
									mark.line = sign.lnum
									mark.text = vim.api.nvim_buf_get_lines(bufnr, sign.lnum - 1, sign.lnum, false)[1]
								end
							end
						else
							for _, name_symbols in pairs(kind_symbols) do
								for _, bookmarks in pairs(name_symbols) do
									-- We should iterate reversely since removing entry
									-- from the array will result in unexpected behavior
									for i = #bookmarks, 1, -1 do
										local mark = bookmarks[i]
										if mark.id == sign.id then
											for _, s in ipairs(result) do
												if s.location then -- SymbolInformation type
													s.range = s.location.range
												end
												local r = s.range
												if
													utils.is_position_in_range(
														sign.lnum - 1,
														r.start.line,
														r["end"].line
													)
												then
													matched = true
													local new_offset = sign.lnum - r.start.line - 1
													table.remove(bookmarks, i)
													local l3 = ensure_path_valid(file_name, s.kind, s.name, new_offset)
													-- Don't set the mark.id to sign.id, leave it since otherwise that may
													-- cause this mark be processed mutliple times. The mark.id will be set
													-- when displaying.
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
					end
				end
				-- Always keep the bookmarks in clean state
				utils.clear_empty_tables(M.bookmarks)
				-- This sign is created when pasting/creating, create a new bookmark for it
				-- Althrough after this sign is processed we won't hit the mark.id == sign.id case,
				-- we still shouldn't assign the mark.id with sign.id since we better to keep it consistent
				if not matched then
					-- true create a lsp mark, else create a plain mark
					local match_symbol = false
					-- Try best to create a lsp mark, fallback to a plain mark
					for _, s in ipairs(result) do
						if s.location then -- SymbolInformation type
							s.range = s.location.range
						end
						local r = s.range
						if utils.is_position_in_range(sign.lnum - 1, r.start.line, r["end"].line) then
							match_symbol = true
							local mark = create_bookmark(s, sign.lnum, 0, sign_info[tostring(sign.id)] or "")
							-- Fresh new bookmark, don't need to calibrate it again
							mark.calibrated = true
							-- The sign is created after creating/pasting, delete the sign info after
							-- the bookmark is created.
							sign_info[tostring(sign.id)] = nil
						end
					end

					-- Create plain mark
					if not match_symbol then
						local mark = create_bookmark(nil, sign.lnum, 0, sign_info[tostring(sign.id)] or "")
						-- Fresh new bookmark, don't need to calibrate it again
						mark.calibrated = true
						-- The sign is created after creating/pasting, delete the sign info after
						-- the bookmark is created.
						sign_info[tostring(sign.id)] = nil
					end
				end
			end
		end
		-- Fallback to calibrate each mark using LSP information.
		--
		-- Not all bookmarks will get calibrated in the first phase using signs,
		-- if we **format** a buffer then all the signs will get lost. thus we need to
		-- calibrate the bookmarks with the LSP information, we don't need to update
		-- the offset for each mark, we need to update the information related to the mark
		-- such as line text and symbol text.
		if M.bookmarks[file_name] ~= nil then
			for kind, kind_symbols in pairs(M.bookmarks[file_name]) do
				if kind ~= M.plain_magic then
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
								for i = #bookmarks, 1, -1 do
									local mark = bookmarks[i]
									if not mark.calibrated then
										local idx = match(same_name_symbols, mark)
										local symbol = same_name_symbols[idx]
										local r = symbol.range

										if tonumber(offset) > (r["end"].line - r.start.line) then
											table.remove(bookmarks, i)
										else
											-- This mark doesn't have a related sign, so set it to nil explicitly
											mark.id = nil
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
									end
									-- reset all lsp marks' calibrated to false,
									-- plain marks don't need this field
									mark.calibrated = false
								end
							end
						end
					end
				end
			end
		end
		utils.clear_empty_tables(M.bookmarks)
		M.display_bookmarks(bufnr)
		M.save_bookmarks(bookmark_file)
	end

	if async then
		local clients = vim.lsp.get_clients({ bufnr = bufnr })
		local request = false
		for _, client in ipairs(clients) do
			if client.server_capabilities.documentFormattingProvider then
				request = true
			end
		end
		if vim.tbl_isempty(clients) or not request then
			-- Only calibrate the plain bookmarks,
			-- this will delete all the lsp bookmarks.
			helper({})
		else
			local params = vim.lsp.util.make_position_params()
			vim.lsp.buf_request_all(bufnr, "textDocument/documentSymbol", params, function(result)
				-- When result arrive, we have moved to a new folder, so do nothing.
				--bookmark_file is nil at first time.
				if bookmark_file and bookmark_file ~= persistence.get_bookmark_file() then
					return
				end
				if not result or vim.tbl_isempty(result) then
					helper({})
					return
				end
				for _, res in pairs(result) do
					if res ~= nil and res.result ~= nil then
						helper(res.result)
						return
					end
				end
			end)
		end
	else
		local clients = vim.lsp.get_clients({ bufnr = bufnr })
		local request = false
		for _, client in ipairs(clients) do
			if client.server_capabilities.documentFormattingProvider then
				request = true
			end
		end

		if not request then
			helper({})
		else
			local result, err = vim.lsp.buf_request_sync(bufnr, "textDocument/documentSymbol", params, 1000)
			if err then
				helper({})
				return
			end
			if not result or vim.tbl_isempty(result) then
				helper({})
				return
			end

			-- calibrate
			for _, response in pairs(result) do
				if response.result ~= nil then
					helper(response.result)
					-- Currently 1 client is enough
					return
				end
			end
		end
	end
end

local function get_mark_from_id(id)
	local file_name = utils.standarize_path(vim.api.nvim_buf_get_name(0))
	if M.bookmarks[file_name] ~= nil then
		for kind, kind_symbols in pairs(M.bookmarks[file_name]) do
			if kind == M.plain_magic then
				for index, mark in ipairs(kind_symbols) do
					if mark.id == id then
						return { marks = kind_symbols, index = index }
					end
				end
			else
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
	end
end

local function delete_id(id)
	local res = get_mark_from_id(id)
	if res ~= nil then
		table.remove(res.marks, res.index)
	end
	utils.clear_empty_tables(M.bookmarks)
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
	ensure_sign_defined()
	vim.fn.sign_unplace(icon_group, { buffer = bufnr })
	vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)

	local file_name = utils.standarize_path(vim.api.nvim_buf_get_name(bufnr))

	if not M.bookmarks[file_name] then
		return
	end

	local line_count = vim.api.nvim_buf_line_count(bufnr)
	for kind, kind_symbols in pairs(M.bookmarks[file_name]) do
		if kind == M.plain_magic then
			for _, mark in ipairs(kind_symbols) do
				if mark.line <= line_count then
					local id = vim.fn.sign_place(0, icon_group, sign_name, bufnr, { lnum = mark.line, priority = 100 })
					mark.id = id

					local comment = utils.string_truncate(mark.comment, 15)
					local col = create_right_aligned_highlight(comment, -1)
					virt_text_opts.virt_text_win_col = col
					virt_text_opts.virt_text[1][1] = comment
					vim.api.nvim_buf_set_extmark(bufnr, ns_id, mark.line - 1, 0, virt_text_opts)
				end
			end
		else
			for _, name_symbols in pairs(kind_symbols) do
				for offset, marks in pairs(name_symbols) do
					for _, mark in ipairs(marks) do
						local start_line = mark.range[1] -- Convert to 1-based indexing

						local line = start_line + tonumber(offset)

						if line < line_count then
							local id =
								vim.fn.sign_place(0, icon_group, sign_name, bufnr, { lnum = line + 1, priority = 100 })
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
				vim.api.nvim_buf_clear_namespace(bufnr, ns_id, sign.lnum - 1, sign.lnum)
			end
		end
	end

	M.save_bookmarks()
	-- We don't need to calibrate here, since we change from a consistent state to another
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
		sign_info[tostring(id)] = input or ""

		-- Modify the comment of an existing mark
		if res ~= nil then
			res.marks[res.index].comment = input or ""
		end
	end)
end

function M.toggle_bookmark(opts)
	local bufnr = vim.api.nvim_get_current_buf()
	local with_comment = false
	if opts then
		with_comment = opts.with_comment
	end

	if vim.api.nvim_get_option_value("modified", { buf = bufnr }) then
		M.lsp_calibrate_bookmarks(nil, false, M.bookmark_file)
	end

	local line = vim.api.nvim_win_get_cursor(0)[1]
	local id = has_bookmark()
	if id ~= false then
		delete_bookmark()
	else
		ensure_sign_defined()
		id = vim.fn.sign_place(0, icon_group, sign_name, bufnr, { lnum = line, priority = 100 })
		if with_comment then
			modify_comment(id)
		end
		M.lsp_calibrate_bookmarks(nil, true, M.bookmark_file)
	end
end

function M.modify_comment()
	local bufnr = vim.api.nvim_get_current_buf()
	if vim.api.nvim_get_option_value("modified", { buf = bufnr }) then
		M.lsp_calibrate_bookmarks(nil, false, M.bookmark_file)
	end
	local id = has_bookmark()
	if id ~= false then
		modify_comment(id)
	else
		print("Couldn't find a bookmark under the cursor.")
	end

	M.lsp_calibrate_bookmarks(nil, true, M.bookmark_file)
end

function M.show_comment()
	-- Will include newly created/pasted signs
	local id = has_bookmark()
	if id ~= false then
		-- Newly created/pasted signs
		if sign_info[tostring(id)] ~= nil then
			print(sign_info[tostring(id)])
		else
			local res = get_mark_from_id(id)
			if res ~= nil then
				print(res.marks[res.index].comment)
			end
		end
	else
		print("Couldn't find a bookmark under the cursor.")
	end
end

local function on_dir_changed_pre()
	utils.clear_empty_tables(M.bookmarks)
	M.save_bookmarks()
end

local function on_lsp_attach(event)
	M.lsp_calibrate_bookmarks(event.buf, true, M.bookmark_file)
end

local function on_buf_enter(event)
	-- The reason why we calibrate the bookmarks after entering rather than before leaving
	-- a buffer is that we don't want to get the modified but not saved file calibrated too early,
	-- which may cause incorret calibration when we force exit neoivm without saving the modfied
	-- buffer back to the disk.
	if vim.api.nvim_get_option_value("modified", { buf = event.buf }) then
		M.lsp_calibrate_bookmarks(event.buf, false, M.bookmark_file)
	end
	M.display_bookmarks(event.buf)
end

local function on_buf_write_post(event)
	M.lsp_calibrate_bookmarks(event.buf, true, M.bookmark_file)
end

function M.load_bookmarks(dir)
	M.bookmarks, M.bookmark_file = persistence.load(dir)
end

function M.save_bookmarks(bookmark_file)
	persistence.save(M.bookmarks, bookmark_file)
end

-- Get the range of texts, delete the bookmarks inside, remove the comment
local function get_range_texts(start_line, end_line, start_c, end_c)
	-- get all bookmarks in the selection
	local bufnr = vim.api.nvim_get_current_buf()
	local extmarks = vim.fn.sign_getplaced(bufnr, { group = "lspmark" })

	for _, marks in ipairs(extmarks) do
		for _, sign in ipairs(marks.signs) do
			if utils.is_position_in_range(sign.lnum, start_line, end_line) then
				local comment
				-- Although we will calibrate each time when we creating/pasting
				-- so when deleting here we can ensure the signs are flushed to the bookmarks,
				-- we still need to be defensive to check if they are flushed not.
				if sign_info[tostring(sign.id)] ~= nil then
					comment = sign_info[tostring(sign.id)]
					sign_info[tostring(sign.id)] = nil
				else
					local mark = get_mark_from_id(sign.id)
					if mark then
						comment = mark.marks[mark.index].comment
					else
						comment = ""
					end
				end
				table.insert(M.marks_in_selection, { offset_in_selection = sign.lnum - start_line, comment = comment })
				delete_id(sign.id)
				-- The signs will be deleted automatically, so we only need to delete virtual text
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
			ensure_sign_defined()
			for _, mark in ipairs(M.marks_in_selection) do
				local line
				if M.mode == "l" then
					line = mark.offset_in_selection + cursor[1] + 1
				else
					line = mark.offset_in_selection + cursor[1]
				end

				local id = vim.fn.sign_place(0, icon_group, sign_name, bufnr, { lnum = line, priority = 100 })
				sign_info[tostring(id)] = mark.comment
			end

			M.lsp_calibrate_bookmarks(bufnr, true, M.bookmark_file)
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
		callback = on_dir_changed_pre,
		pattern = { "*" },
	})
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
