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

function M.get_text(start_line, end_line, start_c, end_c, bufnr)
	local n_lines = math.abs(end_line - start_line) + 1

	-- get all lines of text
	if not bufnr then
		bufnr = 0
	end
	local lines = vim.api.nvim_buf_get_lines(bufnr, start_line - 1, end_line, false)
	lines[1] = string.sub(lines[1], start_c, -1)
	if n_lines == 1 then
		lines[n_lines] = string.sub(lines[n_lines], 1, end_c - start_c + 1)
	else
		lines[n_lines] = string.sub(lines[n_lines], 1, end_c)
	end

	return lines
end

function M.remove_blanks(text)
	return text:gsub("[%c%s]", "")
end

function M.levenshtein(str1, str2)
	-- Initialize a matrix to store the distances between substrings
	local matrix = {}

	-- Initialize the first row and column of the matrix
	for i = 0, #str1 do
		matrix[i] = { [0] = i }
	end
	for j = 0, #str2 do
		matrix[0][j] = j
	end

	-- Loop through the strings and fill in the matrix
	for i = 1, #str1 do
		for j = 1, #str2 do
			local cost = (str1:sub(i, i) == str2:sub(j, j) and 0 or 1)
			matrix[i][j] = math.min(matrix[i - 1][j] + 1, matrix[i][j - 1] + 1, matrix[i - 1][j - 1] + cost)
		end
	end

	-- Return the final value in the matrix (the distance between the two strings)
	return matrix[#str1][#str2]
end

function M.string_truncate(s, len)
	-- -1 for placing other signs such as gitsigns
	if string.len(s) > len then
		return string.sub(s, 1, len - 2) .. ".."
	else
		return s
	end
end

function M.split_text(text)
	local sep = "\n"
	local t = {}
	for str in string.gmatch(text, "([^" .. sep .. "]+)") do
		table.insert(t, str)
	end
	return t
end

function M.clear_empty_tables(t)
	for k, v in pairs(t) do
		if type(v) == "table" then
			M.clear_empty_tables(v)
			if next(v) == nil then
				t[k] = nil
			end
		end
	end
end

-- Thanks for lualine.nvim
function M.get_git_head(path)
	local head_file = path .. "/.git/HEAD"
	local f_head = io.open(head_file)
	if f_head then
		local HEAD = f_head:read()
		f_head:close()
		local branch = HEAD:match("ref: refs/heads/(.+)$")
		if branch then
			return branch
		end
	end
	return ""
end

return M
