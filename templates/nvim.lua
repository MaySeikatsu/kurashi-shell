-- Written by kurashid from the theme (K49). Do not edit: it is rewritten.
-- Use it from ~/.config/nvim/init.lua:   vim.cmd.colorscheme("kurashi")
vim.cmd("highlight clear")
if vim.fn.exists("syntax_on") == 1 then
  vim.cmd("syntax reset")
end
vim.o.background = "{{scheme}}"
vim.o.termguicolors = true
vim.g.colors_name = "kurashi"

local c = {
  bg = "{{colors.surface.default.hex}}",
  low = "{{colors.surface_container_low.default.hex}}",
  mid = "{{colors.surface_container.default.hex}}",
  high = "{{colors.surface_container_high.default.hex}}",
  fg = "{{colors.on_surface.default.hex}}",
  muted = "{{colors.on_surface_variant.default.hex}}",
  outline = "{{colors.outline.default.hex}}",
  faint = "{{colors.outline_variant.default.hex}}",
  accent = "{{colors.primary.default.hex}}",
  on_accent = "{{colors.on_primary.default.hex}}",
  accent_box = "{{colors.primary_container.default.hex}}",
  on_accent_box = "{{colors.on_primary_container.default.hex}}",
  secondary = "{{colors.secondary.default.hex}}",
  tertiary = "{{colors.tertiary.default.hex}}",
  success = "{{colors.success.default.hex}}",
  warning = "{{colors.warning.default.hex}}",
  error = "{{colors.error.default.hex}}",
}

local groups = {
  Normal = { fg = c.fg, bg = c.bg },
  NormalNC = { fg = c.fg, bg = c.bg },
  NormalFloat = { fg = c.fg, bg = c.mid },
  FloatBorder = { fg = c.outline, bg = c.mid },
  FloatTitle = { fg = c.accent, bg = c.mid, bold = true },
  Cursor = { fg = c.bg, bg = c.accent },
  CursorLine = { bg = c.low },
  CursorColumn = { bg = c.low },
  ColorColumn = { bg = c.low },
  CursorLineNr = { fg = c.accent, bold = true },
  LineNr = { fg = c.outline },
  SignColumn = { bg = c.bg },
  FoldColumn = { fg = c.outline, bg = c.bg },
  Folded = { fg = c.muted, bg = c.low },
  VertSplit = { fg = c.faint },
  WinSeparator = { fg = c.faint },
  StatusLine = { fg = c.fg, bg = c.mid },
  StatusLineNC = { fg = c.muted, bg = c.low },
  TabLine = { fg = c.muted, bg = c.low },
  TabLineFill = { bg = c.low },
  TabLineSel = { fg = c.fg, bg = c.bg, bold = true },
  WinBar = { fg = c.fg, bg = c.bg },
  WinBarNC = { fg = c.muted, bg = c.bg },
  Pmenu = { fg = c.fg, bg = c.mid },
  PmenuSel = { fg = c.on_accent_box, bg = c.accent_box },
  PmenuSbar = { bg = c.high },
  PmenuThumb = { bg = c.outline },
  Visual = { bg = c.high },
  Search = { fg = c.on_accent_box, bg = c.accent_box },
  IncSearch = { fg = c.on_accent, bg = c.accent },
  CurSearch = { fg = c.on_accent, bg = c.accent },
  MatchParen = { fg = c.accent, bold = true, underline = true },
  NonText = { fg = c.faint },
  Whitespace = { fg = c.faint },
  SpecialKey = { fg = c.faint },
  EndOfBuffer = { fg = c.bg },
  Directory = { fg = c.accent },
  Title = { fg = c.accent, bold = true },
  Question = { fg = c.secondary },
  MoreMsg = { fg = c.secondary },
  ModeMsg = { fg = c.muted },
  ErrorMsg = { fg = c.error },
  WarningMsg = { fg = c.warning },

  Comment = { fg = c.outline, italic = true },
  Constant = { fg = c.warning },
  String = { fg = c.success },
  Character = { fg = c.success },
  Number = { fg = c.warning },
  Boolean = { fg = c.warning },
  Identifier = { fg = c.fg },
  Function = { fg = c.secondary },
  Statement = { fg = c.accent },
  Keyword = { fg = c.accent },
  Operator = { fg = c.muted },
  PreProc = { fg = c.tertiary },
  Type = { fg = c.tertiary },
  Special = { fg = c.secondary },
  Delimiter = { fg = c.muted },
  Underlined = { underline = true },
  Error = { fg = c.error },
  Todo = { fg = c.on_accent_box, bg = c.accent_box, bold = true },

  ["@variable"] = { fg = c.fg },
  ["@variable.builtin"] = { fg = c.error },
  ["@variable.member"] = { fg = c.muted },
  ["@property"] = { fg = c.muted },
  ["@module"] = { fg = c.tertiary },
  ["@constructor"] = { fg = c.tertiary },
  ["@punctuation"] = { fg = c.muted },
  ["@tag"] = { fg = c.accent },
  ["@tag.attribute"] = { fg = c.tertiary },
  ["@markup.heading"] = { fg = c.accent, bold = true },
  ["@markup.link.url"] = { fg = c.secondary, underline = true },
  ["@markup.raw"] = { fg = c.success },

  DiagnosticError = { fg = c.error },
  DiagnosticWarn = { fg = c.warning },
  DiagnosticInfo = { fg = c.secondary },
  DiagnosticHint = { fg = c.outline },
  DiagnosticOk = { fg = c.success },
  DiagnosticUnderlineError = { undercurl = true, sp = c.error },
  DiagnosticUnderlineWarn = { undercurl = true, sp = c.warning },
  DiagnosticUnderlineInfo = { undercurl = true, sp = c.secondary },
  DiagnosticUnderlineHint = { undercurl = true, sp = c.outline },
  LspInlayHint = { fg = c.outline, bg = c.low },

  DiffAdd = { fg = c.success, bg = c.low },
  DiffChange = { fg = c.warning, bg = c.low },
  DiffDelete = { fg = c.error, bg = c.low },
  DiffText = { fg = c.on_accent_box, bg = c.accent_box },
  Added = { fg = c.success },
  Changed = { fg = c.warning },
  Removed = { fg = c.error },
}
for name, spec in pairs(groups) do
  vim.api.nvim_set_hl(0, name, spec)
end

local term = {
  c.bg, c.error, c.success, c.warning, c.accent, c.tertiary, c.secondary, c.fg,
  c.high, c.error, c.success, c.warning, c.accent, c.tertiary, c.secondary, c.muted,
}
for i, colour in ipairs(term) do
  vim.g["terminal_color_" .. (i - 1)] = colour
end
