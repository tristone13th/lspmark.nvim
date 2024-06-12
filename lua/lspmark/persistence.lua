local M = {}
local config_dir = vim.fn.stdpath("data") .. "/lspmark"
local utils = require("lspmark.utils")

function M.get_bookmark_file()
	local cwd = vim.fn.getcwd()
	local sanitized_cwd = utils.sanitize_path(cwd)
	return config_dir .. "/" .. sanitized_cwd .. ".json"
end

function M.load()
	local bookmark_file = M.get_bookmark_file()

	if not utils.file_exists(bookmark_file) then
		return {}
	end

	local file = io.open(bookmark_file, "r")

	if not file then
		return {}
	end

	local content = file:read("*a")

	if not content then
		return {}
	end

	file:close()

	return vim.fn.json_decode(content)
end

function M.save(bookmarks)
	local bookmark_file = M.get_bookmark_file()

	if not utils.directory_exists(config_dir) then
		vim.fn.mkdir(config_dir, "p")
	end

	local file = io.open(bookmark_file, "w")

	if not file then
		print("Failed to save the bookmarks to file.")
		return
	end

	file:write(vim.fn.json_encode(bookmarks))
	file:close()
end

return M
