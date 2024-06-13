local M = {}

function M.file_exists(path)
	local f = io.open(path, "r")
	if f then
		f:close()
	end
	return f ~= nil
end

function M.directory_exists(path)
	local ok, _, code = os.rename(path, path)
	if not ok then
		if code == 13 then
			-- Permission denied, but it exists
			return true
		end
	end
	return ok
end

function M.is_position_in_range(line, start_line, end_line)
	if line >= start_line and line <= end_line then
		return true
	end
	return false
end

function M.sanitize_path(path)
	return path:gsub("[/\\]", "%%")
end

function M.get_buffers_for_file(file_path)
	local matching_buffers = {}
	local buffers = vim.api.nvim_list_bufs()

	for _, buf in ipairs(buffers) do
		local buf_name = vim.api.nvim_buf_get_name(buf)
		if buf_name == file_path then
			table.insert(matching_buffers, buf)
		end
	end

	return matching_buffers
end

function M.get_sign_from_id(bufnr, id)
	local signs = vim.fn.sign_getplaced(bufnr, { group = "lspmark", id = id })
	if #signs == 0 or #signs[1].signs == 0 then
		return nil
	end
	return signs[1].signs[1]
end

return M
