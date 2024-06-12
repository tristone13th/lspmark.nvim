local M = {}

M.symbol_colors = {
	[vim.lsp.protocol.SymbolKind.File] = "Identifier",
	[vim.lsp.protocol.SymbolKind.Module] = "Function",
	[vim.lsp.protocol.SymbolKind.Namespace] = "Function",
	[vim.lsp.protocol.SymbolKind.Package] = "Special",
	[vim.lsp.protocol.SymbolKind.Class] = "Type",
	[vim.lsp.protocol.SymbolKind.Method] = "Function",
	[vim.lsp.protocol.SymbolKind.Property] = "Identifier",
	[vim.lsp.protocol.SymbolKind.Field] = "Identifier",
	[vim.lsp.protocol.SymbolKind.Constructor] = "Function",
	[vim.lsp.protocol.SymbolKind.Enum] = "Type",
	[vim.lsp.protocol.SymbolKind.Interface] = "Type",
	[vim.lsp.protocol.SymbolKind.Function] = "Function",
	[vim.lsp.protocol.SymbolKind.Variable] = "Identifier",
	[vim.lsp.protocol.SymbolKind.Constant] = "Constant",
	[vim.lsp.protocol.SymbolKind.String] = "String",
	[vim.lsp.protocol.SymbolKind.Number] = "Number",
	[vim.lsp.protocol.SymbolKind.Boolean] = "Boolean",
	[vim.lsp.protocol.SymbolKind.Array] = "Identifier",
	[vim.lsp.protocol.SymbolKind.Object] = "Identifier",
	[vim.lsp.protocol.SymbolKind.Key] = "Identifier",
	[vim.lsp.protocol.SymbolKind.Null] = "Identifier",
	[vim.lsp.protocol.SymbolKind.EnumMember] = "Identifier",
	[vim.lsp.protocol.SymbolKind.Struct] = "Type",
	[vim.lsp.protocol.SymbolKind.Event] = "Function",
	[vim.lsp.protocol.SymbolKind.Operator] = "Operator",
	[vim.lsp.protocol.SymbolKind.TypeParameter] = "Type",
}

return M
