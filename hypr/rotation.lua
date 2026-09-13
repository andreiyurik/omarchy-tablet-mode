-- Screen rotation and tablet-mode input handling for omarchy-tablet-mode.
--
-- Loaded from hyprland.lua through a marked block that `omarchy-tablet-mode
-- setup` maintains. The CLI turns the panel live with `hyprctl eval`; this
-- fragment replays that state whenever the config reloads, since a reload
-- rebuilds monitor and device rules from the files. It reads plain data written
-- by the CLI and never loads generated code.

local paths = require("default.hypr.paths")

local plugin_id = "andreiyurik.tablet-mode"
local state_dir = paths.state_home .. "/omarchy/tablet-mode"

local function read_file(path)
  local file = io.open(path, "r")
  if not file then
    return nil
  end
  local text = file:read("*a")
  file:close()
  return text
end

local function first_line(path)
  local text = read_file(path)
  return text and text:match("^[^\n]*")
end

-- A third-party plugin is enabled exactly when its id appears in shell.json.
-- The block in hyprland.lua outlives a disable, so without this check a
-- disabled plugin would go on turning the screen and muting the keyboard.
local shell_json = read_file(paths.config_home .. "/omarchy/shell.json")
if not shell_json or not shell_json:find('"' .. plugin_id .. '"', 1, true) then
  return
end

local conf = { touch = {}, internal = {} }

do
  local text = read_file(state_dir .. "/devices.conf")
  if not text then
    return
  end

  for line in text:gmatch("[^\n]+") do
    local key, value = line:match("^([%w_]+)=(.*)$")
    if key and value ~= "" then
      if conf[key] and type(conf[key]) == "table" then
        table.insert(conf[key], value)
      else
        conf[key] = value
      end
    end
  end
end

if not conf.panel then
  return
end

local transform = tonumber(conf.transform) or 0
if transform < 0 or transform > 7 then
  transform = 0
end

-- A per-output rule replaces the wildcard rule in monitors.lua outright, so
-- mode, position and scale are repeated as they were when the panel turned. At
-- transform 0 no rule is emitted, handing the panel back to monitors.lua.
if transform ~= 0 then
  hl.monitor({
    output = conf.panel,
    mode = conf.mode or "preferred",
    position = conf.position or "auto",
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

-- Where the lid stands. A sysfs sensor reports the current state and wins. A
-- switch event only reports a change, so it is trusted only from the Hyprland
-- instance that delivered it; one left over from before a logout says nothing.
local folded = false
local sysfs_state = conf.tablet_sysfs and first_line(conf.tablet_sysfs)
if sysfs_state then
  folded = sysfs_state == "1"
elseif conf.tablet_switch then
  local signature, value = (first_line(state_dir .. "/folded") or ""):match("^(%S+) ([01])$")
  folded = signature ~= nil
    and signature == os.getenv("HYPRLAND_INSTANCE_SIGNATURE")
    and value == "1"
end

-- Devices Omarchy's own touchpad and touchscreen toggles hold off. Those
-- toggles load before this fragment, so re-enabling everything here would
-- quietly undo them.
local held_off = {}
for _, kind in ipairs({ "touchpad", "touchscreen" }) do
  local name = first_line(paths.home .. "/.local/state/omarchy/toggles/hypr/" .. kind .. "-disabled-name")
  if name and name ~= "" then
    held_off[name] = true
  end
end

-- Both states written explicitly: Hyprland does not reset `enabled` on reload,
-- so merely omitting the rule leaves a device disabled forever once it has
-- been disabled one time.
for _, name in ipairs(conf.internal) do
  if folded or not held_off[name] then
    hl.device({ name = name, enabled = not folded })
  end
end

-- Hyprland receives SW_TABLET_MODE from libinput with no extra permissions, on
-- every vendor that reports it. The binds hand each change to the CLI, which
-- switches input at once and wakes the daemon to rotate.
if conf.tablet_switch and conf.cli then
  local cli = "'" .. conf.cli:gsub("'", "'\\''") .. "'"
  hl.bind("switch:on:" .. conf.tablet_switch, hl.dsp.exec_cmd(cli .. " fold on"), { locked = true })
  hl.bind("switch:off:" .. conf.tablet_switch, hl.dsp.exec_cmd(cli .. " fold off"), { locked = true })
end
