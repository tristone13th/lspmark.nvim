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

function M.is_position_in_range(line, character, start_line, end_line, start_character, end_character)
	if line > start_line and line < end_line then
		return true
	elseif line == start_line and line == end_line and character >= start_character and character < end_character then
		return true
	elseif line == start_line and character >= start_character then
		return true
	elseif line == end_line and character < end_character then
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

return M
