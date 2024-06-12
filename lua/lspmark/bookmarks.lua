local M = {}
local persistence = require("lspmark.persistence")
local utils = require("lspmark.utils")

M.bookmarks = {}

function M.setup()
	-- Attach to LSP client
	-- vim.lsp.handlers["textDocument/semanticTokens/full"] = M.handle_semantic_tokens
	-- vim.lsp.handlers["textDocument/semanticTokens/range"] = M.handle_semantic_tokens

	vim.api.nvim_create_autocmd({ "DirChangedPre" }, {
		callback = M.save_bookmarks,
		pattern = { "*" },
	})
	vim.api.nvim_create_autocmd({ "DirChanged" }, {
		callback = M.load_bookmarks,
		pattern = { "*" },
	})
	vim.api.nvim_create_autocmd({ "BufWinEnter" }, {
		callback = M.on_buf_win_enter,
		pattern = { "*" },
	})
	vim.api.nvim_create_autocmd({ "SessionLoadPost" }, {
		callback = function()
			M.calibrate_bookmarks(0)
		end,
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

	local sign_name = "SymbolIcon"
	local icon = "🚩"

	if vim.fn.sign_getdefined(sign_name) == nil or #vim.fn.sign_getdefined(sign_name) == 0 then
		vim.fn.sign_define(sign_name, { text = icon, texthl = "Error", numhl = "Error" })
	end

	for _, symbols in pairs(M.bookmarks[file_name]) do
		for _, range in pairs(symbols) do
			local start_line = range[1] + 1 -- Convert to 1-based indexing
			vim.fn.sign_place(0, icon_group, sign_name, bufnr, { lnum = start_line, priority = 10 })
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
				local r = symbol.range

				if
					utils.is_position_in_range(
						line,
						character,
						r.start.line,
						r["end"].line,
						r.start.character,
						r["end"].character
					)
				then
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

	if not M.bookmarks[file_name][tostring(symbol.kind)] then
		M.bookmarks[file_name][tostring(symbol.kind)] = {}
	end

	local r = symbol.range
	M.bookmarks[file_name][tostring(symbol.kind)][symbol.name] = {
		r.start.line,
		r["end"].line,
		r.start.character,
		r["end"].character,
	}

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

	if not M.bookmarks[file_name][tostring(symbol.kind)] then
		return
	end

	M.bookmarks[file_name][tostring(symbol.kind)][symbol.name] = nil

	M.save_bookmarks()
	M.display_bookmarks(0)
end

-- Do we have a bookmark in current cursor?
function M.has_bookmark(symbol)
	local file_path = vim.api.nvim_buf_get_name(0)
	-- We suppose all the boobmarks are up-to-date
	local bookmarks_file = M.bookmarks[file_path]

	if not bookmarks_file then
		return false
	end

	local bookmarks_kind = bookmarks_file[tostring(symbol.kind)]

	if not bookmarks_kind then
		return false
	end

	if bookmarks_kind[symbol.name] then
		return true
	end

	return false
end

function M.toggle_bookmark()
	local symbol = M.get_document_symbol()
	if M.has_bookmark(symbol) then
		M.delete_bookmark(symbol)
	else
		M.create_bookmark(symbol)
	end
end

function M.display_all_bookmarks()
	for file_name, _ in pairs(M.bookmarks) do
		local buffers = utils.get_buffers_for_file(file_name)
		for _, bufnr in ipairs(buffers) do
			M.display_bookmarks(bufnr)
		end
	end
end

function M.on_buf_win_enter(event)
	M.calibrate_bookmarks(event.buf)
end

function M.calibrate_bookmarks(bufnr)
	if bufnr == nil then
		bufnr = vim.api.nvim_get_current_buf()
	end
	local file_name = vim.api.nvim_buf_get_name(bufnr)
	local kinds = M.bookmarks[file_name]
	if not kinds then
		return
	end
	local new_kinds = {}

	-- flatten all the symbols in bookmarks[file_name]
	local symbols = {}
	for kind, symbol_table in pairs(kinds) do
		for name, range in pairs(symbol_table) do
			table.insert(symbols, { name = name, kind = kind, range = range })
		end
	end
	if vim.tbl_isempty(symbols) then
		return
	end

	-- request LSP server
	local params = vim.lsp.util.make_position_params()
	local result, err = vim.lsp.buf_request_sync(bufnr, "textDocument/documentSymbol", params, 1000)
	if err then
		print("Error getting semantic tokens: ", err)
		return
	end
	if not result or vim.tbl_isempty(result) then
		return
	end

	-- calibrate
	for client_id, response in pairs(result) do
		if response.result then
			for _, symbol in ipairs(response.result) do
				-- selection range is the same, all need to be modified is following:
				-- local sr = symbol.selectionRange
				for _, pre_symbol in ipairs(symbols) do
					if pre_symbol.name == symbol.name then
						if not new_kinds[tostring(symbol.kind)] then
							new_kinds[tostring(symbol.kind)] = {}
						end

						local r = symbol.range
						new_kinds[tostring(symbol.kind)][symbol.name] = {
							r.start.line,
							r["end"].line,
							r.start.character,
							r["end"].character,
						}
					end
				end
			end
		elseif response.error then
			print("Error from client ID: ", client_id, response.error)
		end
	end

	M.bookmarks[file_name] = new_kinds
	M.save_bookmarks()
	M.display_bookmarks(bufnr)
end

function M.load_bookmarks()
	M.bookmarks = persistence.load()
	-- M.display_all_bookmarks()
end

function M.save_bookmarks()
	persistence.save(M.bookmarks)
end

return M
