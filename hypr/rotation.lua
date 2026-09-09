-- Screen rotation and tablet-mode input handling for omarchy-tablet-mode.
--
-- Loaded from hyprland.lua via a marked `dofile` block that `omarchy-tablet-mode
-- setup` maintains. It reads state written by the CLI, because a Lua config
-- refuses `hyprctl keyword monitor` ("keyword can't work with non-legacy
-- parsers") -- the monitor can only be moved through the config itself.
--
-- Loaded last so it wins over monitors.lua and over any plugin that rewrites
-- the monitor layout.

local state_home = os.getenv("XDG_STATE_HOME")
if state_home == nil or state_home == "" then
  state_home = os.getenv("HOME") .. "/.local/state"
end

local conf = { touch = {}, internal = {} }

do
  local file = io.open(state_home .. "/omarchy/tablet-mode/devices.conf", "r")
  if not file then
    return
  end

  for line in file:lines() do
    local key, value = line:match("^([%w_]+)=(.*)$")
    if key and value ~= "" then
      if key == "touch" or key == "internal" then
        table.insert(conf[key], value)
      else
        conf[key] = value
      end
    end
  end
  file:close()
end

if not conf.panel then
  return
end

local transform = tonumber(conf.transform) or 0
if transform < 0 or transform > 7 then
  transform = 0
end

-- A per-output rule replaces the wildcard rule in monitors.lua outright, so the
-- scale has to be repeated or Hyprland falls back to auto -- which is a
-- different number than the user configured. At transform 0 no rule is emitted,
-- handing the panel back to monitors.lua untouched.
if transform ~= 0 then
  hl.monitor({
    output = conf.panel,
    mode = "preferred",
    position = "auto",
    scale = tonumber(conf.scale) or 1,
    transform = transform,
  })
end

-- Binding a digitizer to the output maps its coordinates into the panel's area
-- but does NOT rotate its axes: without a matching device transform, taps land
-- in the wrong place and a swipe scrolls sideways.
--
-- Written on every load, transform 0 included. Hyprland keeps the last device
-- transform across a reload, so omitting it would strand touch input in
-- whatever orientation it was last rotated to.
for _, name in ipairs(conf.touch) do
  hl.device({ name = name, output = conf.panel, transform = transform })
end

-- The fold state is read from the hardware here rather than from a state file,
-- so a reload while the machine sits open can never leave the keyboard dead.
local folded = false
if conf.tablet_switch then
  local file = io.open(conf.tablet_switch, "r")
  if file then
    folded = file:read("*l") == "1"
    file:close()
  end
end

-- Both states written explicitly, for the same reason as the transform above:
-- Hyprland does not reset `enabled` on reload, so merely omitting the rule
-- leaves a device disabled forever once it has been disabled one time.
for _, name in ipairs(conf.internal) do
  hl.device({ name = name, enabled = not folded })
end
