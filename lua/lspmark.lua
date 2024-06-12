local M = {}

require("lspmark.bookmarks").setup()
require("telescope").load_extension("lspmark")

return M
