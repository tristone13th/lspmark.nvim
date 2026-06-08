local M = {}

local valid_entry_fields = {
	"file",
	"kind",
	"symbol",
	"text",
	"comment",
}

---@alias lspmark.TelescopeEntryField
---| '"file"'
---| '"kind"'
---| '"symbol"'
---| '"text"'
---| '"comment"'

---@class lspmark.TelescopeOptions
---@field entry_fields? lspmark.TelescopeEntryFieldsOptions

---@class lspmark.TelescopeEntryFieldsOptions
---@field order? lspmark.TelescopeEntryField[] Display order for Telescope entry fields; omit fields to hide them.
---@field max_widths? lspmark.TelescopeEntryFieldMaxWidths Maximum calculated width as a fraction of the Telescope results width; configured fields should sum to 1 or less.

---@class lspmark.TelescopeEntryFieldMaxWidths
---@field file? number
---@field kind? number
---@field symbol? number
---@field text? number
---@field comment? number

---@class lspmark.Options
---@field telescope? lspmark.TelescopeOptions

---@type lspmark.Options
M.defaults = {
	telescope = {
		entry_fields = {
			order = { "file", "kind", "symbol", "text", "comment" },
			max_widths = {
				file = 0.15,
				kind = 0.1,
				symbol = 0.15,
				text = 0.3,
				comment = 0.3,
			},
		},
	},
}

---@type lspmark.Options
M.options = vim.deepcopy(M.defaults)

local function fail(path, message)
	error("lspmark: invalid setup option `" .. path .. "`: " .. message, 3)
end

local function validate_keys(tbl, path, allowed_keys)
	vim.iter(tbl):each(function(key)
		if not vim.tbl_contains(allowed_keys, key) then
			fail(path .. "." .. tostring(key), "unknown option")
		end
	end)
end

local function validate_table(value, path)
	if type(value) ~= "table" or vim.islist(value) then
		fail(path, "expected a table")
	end
end

local function validate_entry_fields_order(order)
	if type(order) ~= "table" or not vim.islist(order) then
		fail("telescope.entry_fields.order", "expected a list")
	end

	if #order == 0 then
		fail("telescope.entry_fields.order", "expected at least one field")
	end

	local seen = {}
	vim.iter(order):each(function(field)
		if not vim.tbl_contains(valid_entry_fields, field) then
			fail("telescope.entry_fields.order", "unknown field `" .. tostring(field) .. "`")
		end

		if seen[field] then
			fail("telescope.entry_fields.order", "duplicate field `" .. field .. "`")
		end

		seen[field] = true
	end)
end

local function validate_entry_fields_max_widths(order, max_widths)
	validate_table(max_widths, "telescope.entry_fields.max_widths")
	validate_keys(max_widths, "telescope.entry_fields.max_widths", valid_entry_fields)

	local total = vim.iter(order):fold(0, function(acc, field)
		local width = max_widths[field]

		if type(width) ~= "number" then
			fail("telescope.entry_fields.max_widths." .. field, "expected a number")
		end

		if width <= 0 or width > 1 then
			fail(
				"telescope.entry_fields.max_widths." .. field,
				"expected a number greater than 0 and less than or equal to 1"
			)
		end

		return acc + width
	end)

	if total > 1 then
		fail("telescope.entry_fields.max_widths", "widths for displayed fields must sum to 1 or less")
	end
end

local function validate_options(opts)
	validate_table(opts, "opts")
	validate_keys(opts, "opts", { "telescope" })

	validate_table(opts.telescope, "telescope")
	validate_keys(opts.telescope, "telescope", { "entry_fields" })

	validate_table(opts.telescope.entry_fields, "telescope.entry_fields")
	validate_keys(opts.telescope.entry_fields, "telescope.entry_fields", { "order", "max_widths" })

	validate_entry_fields_order(opts.telescope.entry_fields.order)
	validate_entry_fields_max_widths(opts.telescope.entry_fields.order, opts.telescope.entry_fields.max_widths)
end

---@param opts? lspmark.Options
function M.setup(opts)
	M.options = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})
	validate_options(M.options)
end

return M
