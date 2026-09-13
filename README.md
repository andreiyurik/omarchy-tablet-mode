# Tablet Mode

Makes tablet mode work on a 2-in-1 running [Omarchy](https://omarchy.org/).
The screen follows the accelerometer, the touchscreen and pen follow the screen,
and the bar gets a rotation lock.

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
Hyprland fragment. The original file is backed up once, to
`hyprland.lua.tablet-mode-backup`.

## Settings

Right-click the bar widget to open its settings.

| Setting | What it does |
|---|---|
| **Which way the screen turns** | How the accelerometer is mounted relative to the panel |
| **Rotate in laptop mode too** | Follow the sensor in every position, not only when folded |
| **Hide the icon in laptop mode** | Keep the lock out of the bar until it has something to do |

### If the screen rotates the wrong way

The sensor reports which way is up, but not how it was screwed into the
chassis. Turn the machine, see which positions come out mirrored, and pick the
matching entry:

| Symptom | Setting |
|---|---|
| Only the two upright positions are mirrored | `portrait-swapped` |
| Only the two flat positions are mirrored | `landscape-swapped` |
| Everything is upside down | `rotated-180` |

That setting is a workaround. The lasting fix belongs in systemd: its
[`60-sensor.hwdb`](https://github.com/systemd/systemd/blob/main/hwdb.d/60-sensor.hwdb)
carries an `ACCEL_MOUNT_MATRIX` per model, and iio-sensor-proxy applies it for
every desktop, not just this one. A machine that needs anything other than
`standard` here is a machine missing from that file. `monitor-sensor`, which
ships with iio-sensor-proxy, shows what the sensor reports while you try a
matrix.

### Known machines

| Machine | Setting | Fold sensor | In systemd's hwdb |
|---|---|---|---|
| ThinkPad X1 Yoga Gen 6 | `portrait-swapped` | `thinkpad_acpi` | no |

**If yours needs anything other than `standard`, please open an issue** with the
output of:

```bash
~/.config/omarchy/plugins/andreiyurik.tablet-mode/bin/omarchy-tablet-mode detect
```

It prints the model as DMI reports it, along with the panel, digitizer and fold
sensor that were found. Each entry here is a draft for the hwdb, and once it is
upstream the setting can go back to `standard`.

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

The CLI lives inside the plugin and is not on your `PATH`:

```bash
cli=~/.config/omarchy/plugins/andreiyurik.tablet-mode/bin/omarchy-tablet-mode

$cli rotate normal|right|inverted|left|next|prev
$cli lock on|off|toggle
$cli status      # JSON, what the widget reads
$cli relayout    # re-tile two windows on the panel for the current orientation
$cli detect      # what it found on your machine — include this in issues
```

## Limitations

**Only a workspace of exactly two tiled windows is re-tiled.** Hyprland
recalculates window geometry when the screen turns, but leaves the dwindle
split tree as it was: two windows side by side on a wide screen stay side by
side on a tall one, as a pair of narrow columns. With two windows the fix is
one certain `togglesplit`. With more, which windows share a split cannot be
read reliably from where they sit, and a wrong guess makes things worse — so
they are left for `SUPER + J` (Omarchy's toggle split) by hand. Only the
workspace showing on the panel is touched, and only in the dwindle layout.

**A rotated panel's monitor rule replaces the one in `monitors.lua`.** Mode,
position and scale are carried over, but anything else set on that output
(such as VRR) is not, while the panel is turned.

**A window that ignores resize requests stays the size it was.** Nothing here
can help a hung application; it will sit at its old geometry until it responds.

## How it works, and why it works that way

**Rotation is applied live with `hyprctl eval`.** On a Lua config Hyprland
refuses `hyprctl keyword monitor`, but `eval` changes the running compositor
directly — the same way Omarchy's own monitor scaling does — so turning the
screen needs no config reload. The orientation is also recorded in
`~/.local/state/omarchy/tablet-mode/devices.conf`, and the Hyprland fragment
replays it whenever the config does reload.

**The fold comes from Hyprland's switch events.** Hyprland receives
`SW_TABLET_MODE` from libinput, which works on every vendor that reports it
(`intel-vbtn`, `intel-hid`, `thinkpad_acpi`, `asus-nb-wmi`, `hp-wmi`, …) and
needs no permissions. The fragment binds `switch:on` and `switch:off` for the
device that has that switch, and the CLI switches input off or on at once. On
ThinkPad, ASUS and HP machines the current state is also readable from sysfs,
and there it wins: an event only says what changed.

**Built-in devices are told apart by udev, not by name.** udev tags every input
device `ID_INTEGRATION=internal` or `external`, which is what keeps a USB
keyboard live in tent mode and a drawing tablet on the desk from turning with
the panel. The power button and hotkeys are keys but not a keyboard, so they
keep working while folded.

**The touchscreen needs its own transform.** Binding a digitizer to an output
maps its coordinates into that monitor's area but does *not* rotate its axes.
Without a matching device transform, taps land in the wrong place and a swipe
scrolls sideways.

**Device settings are always written, including the neutral ones.** Hyprland
does not reset `enabled` or `transform` when the config is reloaded — it keeps
the last value. The one exception is a device Omarchy's own touchpad toggle has
switched off: unfolding leaves it off.

**The daemon reports; the widget does not poll.** It prints its state as a line
of JSON whenever something changes, and reacts to the lock and to switch events
through file notifications. A sysfs fold sensor, which raises no events, is the
only thing read on a timer.

**Disabled means inert.** A third-party plugin is enabled exactly when its id is
in `shell.json`; the fragment checks that and does nothing otherwise. When the
daemon is stopped because the plugin was disabled or removed, it turns the
panel upright and gives the keyboard back first.

## Development

```bash
tests/run
```

The suites work in a temporary `HOME` with `hyprctl` and `hl` stubbed out, so
they never touch the running compositor or your config.

## Uninstall

```bash
omarchy plugin remove andreiyurik.tablet-mode
```

That is enough on its own: the block in `hyprland.lua` checks that the plugin is
still there before loading anything. To remove the block too, run this first,
while the plugin is still installed:

```bash
~/.config/omarchy/plugins/andreiyurik.tablet-mode/bin/omarchy-tablet-mode setup --remove
```

## License

MIT
