-- Written by kurashid from the theme (K49, K99). Do not edit: it is rewritten. In your wezterm.lua, before `return config`:
--   require('kurashi').apply(config)
local M = {}
M.colors = {
  foreground = '{{term.foreground.hex}}',
  background = '{{term.background.hex}}',
  cursor_bg = '{{term.cursor.hex}}',
  cursor_border = '{{term.cursor.hex}}',
  cursor_fg = '{{term.cursor_on.hex}}',
  selection_bg = '{{term.selection_background.hex}}',
  selection_fg = '{{term.selection_foreground.hex}}',
  ansi = {
    '{{term.color0.hex}}', '{{term.color1.hex}}', '{{term.color2.hex}}', '{{term.color3.hex}}',
    '{{term.color4.hex}}', '{{term.color5.hex}}', '{{term.color6.hex}}', '{{term.color7.hex}}',
  },
  brights = {
    '{{term.color8.hex}}', '{{term.color9.hex}}', '{{term.color10.hex}}', '{{term.color11.hex}}',
    '{{term.color12.hex}}', '{{term.color13.hex}}', '{{term.color14.hex}}', '{{term.color15.hex}}',
  },
}
-- The shell's material: a faint tile while it is on for the terminals, nil otherwise.
M.background = {{terminal.image}}
-- The shell's monospaced font while Monospaced font in apps is on (K104), nil otherwise.
M.font = {{wezterm.font}}
function M.apply(config)
  config.colors = M.colors
  if M.background then
    config.background = M.background
  end
  if M.font then
    config.font = M.font
  end
  return config
end
return M
