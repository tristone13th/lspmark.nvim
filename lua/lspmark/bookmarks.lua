local M = {}
local persistence = require("lspmark.persistence")
local utils = require("lspmark.utils")

M.bookmarks = {}
M.text = nil
M.yanked = false
M.marks_in_selection = {}
M.mode = "c"
M.process_selection = false

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
		callback = M.on_buf_enter,
		pattern = { "*" },
	})
	-- When jumping from telescope to a buffer, LspAttach
	-- and BufEnter will be triggered simultaneously and make
	-- a chaos, so comment this.
	-- vim.api.nvim_create_autocmd({ "BufEnter" }, {
	-- 	callback = M.on_buf_enter,
	-- 	pattern = { "*" },
	-- })
	vim.api.nvim_create_autocmd({ "BufWritePost" }, {
		callback = M.on_buf_write_post,
		pattern = { "*" },
	})
	vim.api.nvim_create_autocmd({ "TextYankPost" }, {
		callback = function()
			print("func")
			M.yanked = true
		end,
		pattern = { "*" },
	})
end

function M.display_bookmarks(bufnr)
	if bufnr == 0 then
		bufnr = vim.api.nvim_get_current_buf()
	end

	local icon_group = "lspmark"

	vim.fn.sign_unplace(icon_group, { buffer = bufnr })

	local file_name = vim.api.nvim_buf_get_name(bufnr)

	if not M.bookmarks[file_name] then
		return
	end

	local sign_name = "lspmark_symbol"
	local icon = "🚩"

	if vim.fn.sign_getdefined(sign_name) == nil or #vim.fn.sign_getdefined(sign_name) == 0 then
		vim.fn.sign_define(sign_name, { text = icon, texthl = "Error", numhl = "Error" })
	end

	for _, symbols in pairs(M.bookmarks[file_name]) do
		for _, symbol in pairs(symbols) do
			local start_line = symbol.range[1] -- Convert to 1-based indexing
			for offset, mark in pairs(symbol.marks) do
				local id = vim.fn.sign_place(
					0,
					icon_group,
					sign_name,
					bufnr,
					{ lnum = start_line + tonumber(offset) + 1, priority = 10 }
				)
				mark.id = id
			end
		end
	end
end

-- function M.get_workspace_token()
-- 	local bufnr = vim.api.nvim_get_current_buf()
-- 	-- local params = { query = symbol.name }
-- 	local params = { query = "get_workspace_token" }
-- 	local result, err = vim.lsp.buf_request_sync(bufnr, "workspace/symbol", params, 1000)
--
-- 	if err then
-- 		print("Error getting workspace/symbol")
-- 		return
-- 	end
--
--
-- 	if not result or vim.tbl_isempty(result) then
-- 		print("No symbols found")
-- 		return
-- 	end
--
-- 	for _, response in pairs(result) do
-- 		if response.result then
-- 			for _, symbol_result in ipairs(response.result) do
-- 				-- if symbol_result.name == symbol.name then
-- 					local res = {}
-- 					print(vim.inspect(symbol_result))
-- 					res.file_path = string.gsub(symbol_result.location.uri, "^[^:]+://", "")
-- 					res.name = symbol_result.name
-- 					res.kind = symbol_result.kind
-- 					return res
-- 				-- end
-- 			end
-- 		end
-- 	end
--
-- 	return nil
-- end
--

function M.get_document_symbol(bufnr)
	if bufnr == nil then
		bufnr = vim.api.nvim_get_current_buf()
	end

	local cursor = vim.api.nvim_win_get_cursor(0)
	local line, character = cursor[1] - 1, cursor[2]
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

function M.create_bookmark(symbol)
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
		local r = symbol.range
		l2[symbol.name] = {
			range = {
				r.start.line,
				r["end"].line,
				r.start.character,
				r["end"].character,
			},
			marks = {},
		}
	end

	local l3 = l2[symbol.name]
	local cursor = vim.api.nvim_win_get_cursor(0)
	local offset, character = cursor[1] - l3.range[1] - 1, cursor[2]
	l3.marks[tostring(offset)] = { col = character, text = vim.api.nvim_get_current_line() }

	M.save_bookmarks()
	M.display_bookmarks(0)
end

function M.delete_bookmark(symbol)
	if not symbol then
		return
	end

	local file_name = vim.api.nvim_buf_get_name(0)

	if not M.bookmarks[file_name] then
		return
	end

	local l1 = M.bookmarks[file_name]
	if not l1[tostring(symbol.kind)] then
		return
	end

	local l2 = l1[tostring(symbol.kind)]
	if not l2[symbol.name] then
		return
	end

	local l3 = l2[symbol.name]
	local cursor = vim.api.nvim_win_get_cursor(0)
	local offset = cursor[1] - l3.range[1] - 1
	l3.marks[tostring(offset)] = nil
	if vim.tbl_isempty(l3.marks) then
		l2[symbol.name] = nil
	end

	M.save_bookmarks()
	M.display_bookmarks(0)
end

-- Do we have a bookmark in current cursor?
function M.has_bookmark(symbol)
	local bufnr = vim.api.nvim_get_current_buf()
	local file_path = vim.api.nvim_buf_get_name(bufnr)
	-- We suppose all the boobmarks are up-to-date
	local l1 = M.bookmarks[file_path]
	if not l1 then
		return false
	end

	local l2 = l1[tostring(symbol.kind)]
	if not l2 then
		return false
	end

	local l3 = l2[symbol.name]
	if not l3 then
		return false
	end

	local cursor = vim.api.nvim_win_get_cursor(0)
	-- The following cover the case when we want to toggle a bookmark
	-- and the buffer is modified, it is a corner case, so comment this.
	-- local extmarks = vim.fn.sign_getplaced(bufnr, { group = "lspmark" })
	--
	-- for _, marks in ipairs(extmarks) do
	-- 	for _, sign in ipairs(marks.signs) do
	-- 		if sign.lnum == cursor[1] then
	-- 			return true
	-- 		end
	-- 	end
	-- end
	--
	local offset = cursor[1] - l3.range[1] - 1
	if not l3.marks[tostring(offset)] then
		return false
	end

	return true
end

function M.toggle_bookmark()
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

	if M.has_bookmark(symbol) then
		M.delete_bookmark(symbol)
	else
		M.create_bookmark(symbol)
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

function M.on_buf_enter(event)
	M.lsp_calibrate_bookmarks(event.buf, true)
end

function M.on_buf_write_post(event)
	M.lsp_calibrate_bookmarks(event.buf, true)
end

-- We store each mark in a relative way, so we don't need
-- to modify the offset value. What we need is updated the
-- text information and the start line of each LSP symbol.
-- Also delete the marks if their symbol is deleted.
-- lsp.format() can only affect the marks in the formated symbols,
-- Let's hope we do format frequently so each time the file is not huge-changed.
function M.lsp_calibrate_bookmarks(bufnr, async)
	if bufnr == nil then
		bufnr = vim.api.nvim_get_current_buf()
	end
	local file_name = vim.api.nvim_buf_get_name(bufnr)
	local kinds = M.bookmarks[file_name]
	if not kinds then
		return
	end

	-- flatten all the symbols in bookmarks[file_name]
	local symbols = {}
	for _, symbol_table in pairs(kinds) do
		for name, symbol in pairs(symbol_table) do
			table.insert(symbols, { name = name, marks = symbol.marks, range = symbol.range })
		end
	end
	if not vim.tbl_isempty(symbols) or M.process_selection then
		local function operate_on_symbols(all_symbols)
			local new_kinds = {}
			-- calibrate
			for _, symbol in ipairs(all_symbols) do
				-- selection range is the same, all need to be modified is following:
				-- local sr = symbol.selectionRange
				if symbol.location then -- SymbolInformation type
					symbol.range = symbol.location.range
				end
				local r = symbol.range

				-- first process the marks in selection
				if M.process_selection then
					for _, mark in ipairs(M.marks_in_selection) do
						if utils.is_position_in_range(mark.line, r.start.line, r["end"].line) then
							if not new_kinds[tostring(symbol.kind)] then
								new_kinds[tostring(symbol.kind)] = {}
							end
							local new_symbols = new_kinds[tostring(symbol.kind)]
							if not new_symbols[symbol.name] then
								new_symbols[symbol.name] = { marks = {} }
							end

							local new_marks = new_symbols[symbol.name]
							new_marks.range = {
								r.start.line,
								r["end"].line,
								r.start.character,
								r["end"].character,
							}

							local new_offset = mark.line - r.start.line - 1
							local text = vim.api.nvim_buf_get_lines(bufnr, mark.line - 1, mark.line, false)[1]
							new_marks.marks[tostring(new_offset)] = { col = 0, text = text }
						end
					end
				end

				for _, pre_symbol in ipairs(symbols) do
					if pre_symbol.name == symbol.name then
						if not new_kinds[tostring(symbol.kind)] then
							new_kinds[tostring(symbol.kind)] = {}
						end

						local new_symbols = new_kinds[tostring(symbol.kind)]
						if not new_symbols[symbol.name] then
							new_symbols[symbol.name] = { marks = {} }
						end

						local new_marks = new_symbols[symbol.name]
						new_marks.range = {
							r.start.line,
							r["end"].line,
							r.start.character,
							r["end"].character,
						}

						-- calibrate offset based on new start line and the sign
						for offset, mark in pairs(pre_symbol.marks) do
							local sign = utils.get_sign_from_id(bufnr, mark.id)
							-- may because lsp.format(), let's use old offset
							local new_offset, line
							-- r.start and r.end are start from 0, so plus 1
							-- sign == nil when formatting
							if not sign then
								line = math.max(math.min(tonumber(offset) + r.start.line, r["end"].line), r.start.line)
									+ 1
							else
								line = math.max(math.min(sign.lnum, r["end"].line + 1), r.start.line + 1)
							end
							new_offset = line - r.start.line - 1
							local text = vim.api.nvim_buf_get_lines(bufnr, line - 1, line, false)[1]
							new_marks.marks[tostring(new_offset)] = { col = mark.character, text = text }
						end
					end
				end
			end
			M.marks_in_selection = {}
			M.process_selection = false
			return new_kinds
		end

		local params = vim.lsp.util.make_position_params()
		if async then
			vim.lsp.buf_request(bufnr, "textDocument/documentSymbol", params, function(err, result)
				if err then
					vim.api.nvim_err_writeln("Error getting semantic tokens: " .. err.message)
					return
				end
				if not result or vim.tbl_isempty(result) then
					print("Empty LSP result.")
					return
				end

				M.bookmarks[file_name] = operate_on_symbols(result)
				M.save_bookmarks()
				M.display_bookmarks(bufnr)
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
					local new_kinds = operate_on_symbols(response.result)
					M.bookmarks[file_name] = new_kinds
					M.save_bookmarks()
					M.display_bookmarks(bufnr)
				elseif response.error then
					print("Error from client ID: ", client_id, response.error)
				end
			end
		end
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

local function delete_id(bufnr, id)
	local file_name = vim.api.nvim_buf_get_name(bufnr)

	for _, symbols in pairs(M.bookmarks[file_name]) do
		for name, symbol in pairs(symbols) do
			for offset, mark in pairs(symbol.marks) do
				if mark.id == id then
					symbol.marks[offset] = nil
					if vim.tbl_isempty(symbol.marks) then
						symbols[name] = nil
					end
				end
			end
		end
	end
end

function M.delete_line()
	-- get all bookmarks in the selection
	local bufnr = vim.api.nvim_get_current_buf()
	local extmarks = vim.fn.sign_getplaced(bufnr, { group = "lspmark" })
	local cursor = vim.api.nvim_win_get_cursor(0)
	for _, marks in ipairs(extmarks) do
		for _, sign in ipairs(marks.signs) do
			if utils.is_position_in_range(sign.lnum, cursor[1], cursor[1]) then
				table.insert(M.marks_in_selection, { offset_in_selection = 0 })
				delete_id(bufnr, sign.id)
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
				delete_id(bufnr, sign.id)
			end
		end
	end
	local n_lines = math.abs(end_line - start_line) + 1

	-- get all lines of text
	local lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)
	lines[1] = string.sub(lines[1], start_c, -1)
	if n_lines == 1 then
		lines[n_lines] = string.sub(lines[n_lines], 1, end_c - start_c + 1)
	else
		lines[n_lines] = string.sub(lines[n_lines], 1, end_c)
	end

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
		local cursor = vim.api.nvim_win_get_cursor(0)
		vim.api.nvim_put(split_text(M.text), M.mode, true, true)
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
	else
		vim.cmd("normal! p")
	end
end

function M.delete_visual_selection()
	M.text = get_visual_selection()
	vim.cmd('normal! gv"') -- Re-select the last selected text
	vim.cmd('normal! "_d') -- Delete the selected text without affecting registers
	M.yanked = false
end

return M
