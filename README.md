# Autorotate

Rotates a 2-in-1's screen from its accelerometer on [Omarchy](https://omarchy.org/),
with the touchscreen and pen following, and a rotation lock in the bar.

By default it rotates only once the lid is folded back past the keyboard, the
way a tablet does — so tilting the screen, or working with the laptop on your
knees, never flips the display. While folded, the built-in keyboard and pointers
are disabled: the keys face the table and otherwise press themselves against it.

## Requirements

- Omarchy with the Hyprland Lua config (`~/.config/hypr/hyprland.lua`)
- `iio-sensor-proxy` — `sudo pacman -S --needed iio-sensor-proxy`
- A machine with an accelerometer. Without one, manual rotation still works.

## Install

```bash
omarchy plugin add https://github.com/andreiyurik/omarchy-tablet-mode --enable
```

The plugin adds a marked block to `~/.config/hypr/hyprland.lua` that loads its
rotation fragment. The original file is backed up once, to
`hyprland.lua.tablet-mode-backup`.

## Settings

Right-click the bar widget to open its settings.

| Setting | What it does |
|---|---|
| **Which way the screen turns** | How the accelerometer is mounted relative to the panel |
| **Rotate in laptop mode too** | Follow the sensor in every position, not only when folded |
| **Hide the icon in laptop mode** | Keep the lock out of the bar until it has something to do |

### If the screen rotates the wrong way

This is the one thing the plugin cannot detect: the sensor reports which way is
up, but not how it was screwed into the chassis. Turn the machine, see which
positions come out mirrored, and pick the matching entry:

| Symptom | Setting |
|---|---|
| Only the two upright positions are mirrored | `portrait-swapped` |
| Only the two flat positions are mirrored | `landscape-swapped` |
| Everything is upside down | `rotated-180` |

If your machine needs something other than `standard`, please open an issue with
its model — a table of known machines would let this be detected instead.

## The bar widget

Click to lock the current orientation, the way a tablet's rotation lock works.
Middle-click rotates by hand. The icon shows whether the sensor is being
followed or the orientation is frozen.

## A keybinding, if you want one

The plugin does not claim a key. To add one, in `~/.config/hypr/bindings.lua`:

```lua
o.bind(
  "SUPER + ALT + O",
  "Rotate screen",
  os.getenv("HOME") .. "/.config/omarchy/plugins/andreiyurik.tablet-mode/bin/omarchy-tablet-mode rotate next"
)
```

`SUPER + CTRL + O` is Omarchy's "Toggle menu", so pick something else.

## Command line

```bash
omarchy-tablet-mode rotate normal|right|inverted|left|next
omarchy-tablet-mode lock on|off|toggle
omarchy-tablet-mode status      # JSON, what the widget reads
omarchy-tablet-mode detect      # what it found on your machine — include this in issues
```

## How it works, and why it works that way

**Rotation goes through the config, not `hyprctl`.** On a Lua config Hyprland
refuses `hyprctl keyword monitor` with *"keyword can't work with non-legacy
parsers"*. So the orientation is written to
`~/.local/state/omarchy/tablet-mode/devices.conf` and a Hyprland fragment reads
it on reload.

**The touchscreen needs its own transform.** Binding a digitizer to an output
maps its coordinates into that monitor's area but does *not* rotate its axes.
Without a matching device transform, taps land in the wrong place and a swipe
scrolls sideways.

**Device settings are always written, including the neutral ones.** Hyprland
does not reset `enabled` or `transform` when the config is reloaded — it keeps
the last value. Omitting a rule therefore leaves a device disabled, or stuck in
a stale orientation, forever after it has been set once.

**The fold state is read from sysfs at config load**, not from a state file, so
a reload while the machine sits open can never leave the keyboard dead. sysfs is
also world-readable, which avoids putting the user in the `input` group — that
would let every process on the session read all keystrokes.

Fold sensors are read from `thinkpad_acpi`, `asus-nb-wmi` or `hp-wmi`. On a
machine with none, the plugin degrades to rotating in every position.

## Uninstall

```bash
omarchy plugin remove andreiyurik.tablet-mode
```

Remove the Hyprland block first, while the plugin is still installed:

```bash
~/.config/omarchy/plugins/andreiyurik.tablet-mode/bin/omarchy-tablet-mode setup --remove
```

## License

MIT
