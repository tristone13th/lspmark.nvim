local M = {}
local config_dir = vim.fn.stdpath("data") .. "/lspmark"
local utils = require("lspmark.utils")
local magic = "-tRiStOnE13tH-"

function M.get_bookmark_file(dir)
	local cwd = dir or vim.fn.getcwd()
	local branch = utils.get_git_head(cwd)
	local sanitized_cwd = utils.sanitize_path(cwd)
	return config_dir .. "/" .. sanitized_cwd .. magic .. branch .. ".json"
end

function M.load(dir)
	local bookmark_file = M.get_bookmark_file(dir)

	if not utils.file_exists(bookmark_file) then
		return {}, bookmark_file
	end

	local file = io.open(bookmark_file, "r")

	if not file then
		return {}, bookmark_file
	end

	local content = file:read("*a")

	if not content then
		file:close()
		return {}, bookmark_file
	end

	file:close()

	return vim.fn.json_decode(content), bookmark_file
end

function M.save(bookmarks, bm_file)
	local bookmark_file = bm_file or M.get_bookmark_file()

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
