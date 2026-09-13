-- Loads hypr/rotation.lua against a stubbed `hl` and a throwaway HOME, and
-- checks the rules it emits. Run from the repository root: lua tests/fragment_test.lua

local fragment = "hypr/rotation.lua"
local tmp = os.tmpname()
os.remove(tmp)
os.execute("mkdir -p '" .. tmp .. "'")

local home = tmp
local state_dir = home .. "/.local/state/omarchy/tablet-mode"
local toggles_dir = home .. "/.local/state/omarchy/toggles/hypr"
local signature = os.getenv("HYPRLAND_INSTANCE_SIGNATURE")

package.preload["default.hypr.paths"] = function()
  return {
    home = home,
    config_home = home .. "/.config",
    state_home = home .. "/.local/state",
    omarchy_path = "/usr/share/omarchy",
  }
end

local function write(path, text)
  os.execute("mkdir -p '" .. path:match("^(.*)/") .. "'")
  local file = assert(io.open(path, "w"))
  file:write(text)
  file:close()
end

local function reset()
  os.execute("rm -rf '" .. home .. "/.config' '" .. home .. "/.local'")
end

local calls
hl = {
  monitor = function(rule) table.insert(calls, { "monitor", rule }) end,
  device = function(rule) table.insert(calls, { "device", rule }) end,
  bind = function(keys, dispatcher) table.insert(calls, { "bind", keys, dispatcher }) end,
  dsp = { exec_cmd = function(command) return command end },
}

local function load()
  calls = {}
  dofile(fragment)
  return calls
end

local function find(kind, predicate)
  for _, call in ipairs(calls) do
    if call[1] == kind and predicate(call) then
      return call
    end
  end
end

local failures = 0
local function test(name, body)
  reset()
  local ok, err = pcall(body)
  if ok then
    print("ok   " .. name)
  else
    failures = failures + 1
    print("FAIL " .. name .. ": " .. tostring(err))
  end
end

local function enable()
  write(home .. "/.config/omarchy/shell.json", '{"plugins": [{"id": "andreiyurik.tablet-mode"}]}')
end

local base_conf = table.concat({
  "cli=/plugins/it's here/bin/omarchy-tablet-mode",
  "panel=eDP-1",
  "mode=1920x1200@60.026",
  "position=256x1152",
  "scale=1.25",
  "touch=wacom-finger",
  "internal=keyboard",
  "internal=touchpad",
  "tablet_switch=ThinkPad Extra Buttons",
}, "\n") .. "\n"

test("a disabled plugin emits nothing", function()
  write(state_dir .. "/devices.conf", base_conf .. "transform=1\n")
  assert(#load() == 0, "expected no rules")
end)

test("a turned panel keeps its mode, position and scale", function()
  enable()
  write(state_dir .. "/devices.conf", base_conf .. "transform=1\n")
  load()
  local rule = assert(find("monitor", function() return true end), "no monitor rule")[2]
  assert(rule.output == "eDP-1" and rule.transform == 1)
  assert(rule.mode == "1920x1200@60.026" and rule.position == "256x1152" and rule.scale == 1.25)
  assert(find("device", function(c) return c[2].name == "wacom-finger" and c[2].transform == 1 end))
end)

test("an upright panel is handed back to monitors.lua", function()
  enable()
  write(state_dir .. "/devices.conf", base_conf .. "transform=0\n")
  load()
  assert(not find("monitor", function() return true end), "unexpected monitor rule")
  assert(find("device", function(c) return c[2].name == "wacom-finger" and c[2].transform == 0 end))
end)

test("a panel Omarchy switched off for clamshell is not switched back on", function()
  enable()
  write(state_dir .. "/devices.conf", base_conf .. "transform=1\n")
  write(toggles_dir .. "/internal-monitor-clamshell.lua", 'hl.monitor({ output = "eDP-1", disabled = true })\n')
  load()
  assert(not find("monitor", function() return true end), "unexpected monitor rule")
  assert(find("device", function(c) return c[2].name == "wacom-finger" end), "touch rule missing")
end)

test("open, Omarchy's disabled touchpad is not re-enabled", function()
  enable()
  write(state_dir .. "/devices.conf", base_conf)
  write(toggles_dir .. "/touchpad-disabled-name", "touchpad\n")
  load()
  assert(find("device", function(c) return c[2].name == "keyboard" and c[2].enabled == true end))
  assert(not find("device", function(c) return c[2].name == "touchpad" end), "touchpad touched")
end)

test("folded by a switch event from this session, input goes off", function()
  enable()
  write(state_dir .. "/devices.conf", base_conf)
  write(state_dir .. "/folded", signature .. " 1\n")
  load()
  assert(find("device", function(c) return c[2].name == "keyboard" and c[2].enabled == false end))
  assert(find("device", function(c) return c[2].name == "touchpad" and c[2].enabled == false end))
end)

test("a switch event from an earlier session is ignored", function()
  enable()
  write(state_dir .. "/devices.conf", base_conf)
  write(state_dir .. "/folded", "an-old-session 1\n")
  load()
  assert(find("device", function(c) return c[2].name == "keyboard" and c[2].enabled == true end))
end)

test("the fold switch is bound, with the CLI path quoted", function()
  enable()
  write(state_dir .. "/devices.conf", base_conf)
  load()
  local on = assert(find("bind", function(c) return c[2] == "switch:on:ThinkPad Extra Buttons" end))
  assert(on[3] == "'/plugins/it'\\''s here/bin/omarchy-tablet-mode' fold on", on[3])
  assert(find("bind", function(c) return c[2] == "switch:off:ThinkPad Extra Buttons" end))
end)

os.execute("rm -rf '" .. tmp .. "'")
if failures > 0 then
  os.exit(1)
end
