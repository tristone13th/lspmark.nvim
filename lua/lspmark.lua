local M = {}

---@param opts? lspmark.Options
function M.setup(opts)
	require("lspmark.config").setup(opts)
	require("lspmark.bookmarks").setup()
end

return M
