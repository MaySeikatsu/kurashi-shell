-- Written by kurashid from the theme (K49, K99). Do not edit: it is rewritten. In your wezterm.lua, before `return config`:
--   require('kurashi').apply(config)
local M = {}
M.colors = {
  foreground = '{{colors.on_surface.default.hex}}',
  background = '{{colors.surface.default.hex}}',
  cursor_bg = '{{colors.primary.default.hex}}',
  cursor_border = '{{colors.primary.default.hex}}',
  cursor_fg = '{{colors.on_primary.default.hex}}',
  selection_bg = '{{colors.primary_container.default.hex}}',
  selection_fg = '{{colors.on_primary_container.default.hex}}',
  ansi = {
    '{{colors.surface.default.hex}}', '{{colors.error.default.hex}}', '{{colors.tertiary.default.hex}}', '{{colors.secondary.default.hex}}',
    '{{colors.primary.default.hex}}', '{{colors.tertiary.default.hex}}', '{{colors.secondary.default.hex}}', '{{colors.on_surface.default.hex}}',
  },
  brights = {
    '{{colors.surface_container_high.default.hex}}', '{{colors.error_container.default.hex}}', '{{colors.tertiary_container.default.hex}}', '{{colors.secondary_container.default.hex}}',
    '{{colors.primary_container.default.hex}}', '{{colors.on_tertiary_container.default.hex}}', '{{colors.on_secondary_container.default.hex}}', '{{colors.on_surface_variant.default.hex}}',
  },
}
-- The shell's material: a faint tile while it is on for the terminals, nil otherwise.
M.background = {{terminal.image}}
function M.apply(config)
  config.colors = M.colors
  if M.background then
    config.background = M.background
  end
  return config
end
return M
