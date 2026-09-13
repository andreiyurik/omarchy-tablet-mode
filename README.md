# Tablet Mode for Omarchy

Makes tablet mode work on a 2-in-1 convertible laptop running
[Omarchy](https://omarchy.org/) and Hyprland: automatic screen rotation from the
accelerometer, a touchscreen and pen that follow the screen, and a rotation lock
in the bar. Built for 360° laptops such as the ThinkPad X1 Yoga, HP Spectre x360
and Dell XPS 13 2-in-1.

By default it rotates only once the lid is folded back past the keyboard, the
way a tablet does — so tilting the screen, or working with the laptop on your
knees, never flips the display. While folded, the built-in keyboard and pointers
are disabled: the keys face the table and otherwise press themselves against it.

## Who this is for

Anyone running Omarchy on a **convertible** — a laptop whose screen folds back
360° into tent, stand or tablet position — who wants it to behave like a tablet
when folded and like a laptop when open, without configuring anything.

It is not for a regular clamshell laptop, which has nothing to rotate, and it
does not turn a detachable's keyboard cover or a dual-screen laptop into
anything; see [Laptops](#laptops).

## Laptops

What a machine needs is two things the kernel reports on its own: an
**accelerometer** that iio-sensor-proxy can read, and a **tablet mode switch**
(`SW_TABLET_MODE`) that fires when the screen folds back. Nearly every 360°
convertible from the last several years has both.

| Family | Fold sensor | Status |
|---|---|---|
| Lenovo ThinkPad X1 Yoga Gen 6 | `thinkpad_acpi` | **Tested** |
| Other ThinkPad Yoga (X1 Yoga, X13 Yoga, L13 Yoga) | `thinkpad_acpi` | Expected to work |
| Lenovo Yoga 2-in-1 | `lenovo-ymc` or `intel-vbtn` | Expected to work |
| HP Spectre x360, Envy x360, EliteBook x360 | `hp-wmi` or `intel-vbtn` | Expected to work |
| Dell XPS 13 2-in-1, Latitude and Inspiron 2-in-1 | `intel-vbtn` | Expected to work |
| ASUS Zenbook Flip, Vivobook Flip | `asus-nb-wmi` | Expected to work |
| Microsoft Surface and other detachables | varies, often needs the linux-surface kernel | Untested |
| Dual-screen laptops (Yoga Book 9i and the like) | — | Not supported: one internal panel only |

"Expected to work" means the machine reports what the plugin reads, not that
anyone has tried it yet. On ThinkPad, ASUS and HP machines the fold is read from
sysfs, which is the tested path; elsewhere it arrives through Hyprland's switch
events, which are implemented but still waiting for a report from real
hardware. Either way the accelerometer may be mounted differently on your model
— see [If the screen rotates the wrong way](#if-the-screen-rotates-the-wrong-way).

### Checking your machine in a minute

```bash
monitor-sensor --accel
```

Turn the machine on its side: a line saying the accelerometer orientation
changed means the sensor works. Then, with the plugin installed:

```bash
~/.config/omarchy/plugins/andreiyurik.tablet-mode/bin/omarchy-tablet-mode detect
```

`tablet_switch` or `tablet_sysfs` should name something, `touch` should list
your touchscreen and pen, and `internal` only the built-in keyboard and
pointers. If any of that is wrong, or your machine works and is not in the
table, please file a
[machine report](https://github.com/andreiyurik/omarchy-tablet-mode/issues/new?template=machine-report.yml)
— it asks for that output and a few ticks, and takes two minutes.

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
| **Which way the screen turns** | How the accelerometer is mounted relative to the panel. `auto` uses the mounting known for your model, and `standard` for any other |
| **Rotate in laptop mode too** | Follow the sensor in every position, not only when folded |
| **Hide the icon in laptop mode** | Keep the lock out of the bar until it has something to do |

### If the screen rotates the wrong way

The sensor reports which way is up, but not how it was screwed into the
chassis. The default, `auto`, knows the mounting of every model in
[Known machines](#known-machines) and assumes `standard` for the rest. If yours
comes out wrong, turn the machine, see which positions come out mirrored, and
pick the matching entry:

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

Models whose sensor needs anything other than `standard`. None is known yet:
every machine tried so far, the ThinkPad X1 Yoga Gen 6 included, turns
correctly with it.

> **Upgrading from 1.2 or earlier?** Those versions had `standard` mirrored in
> the upright positions, so machines with a correctly mounted sensor needed
> `portrait-swapped` to turn right. If you picked that setting, set it back to
> `auto`.

**If yours needs anything other than `standard`, please file a
[machine report](https://github.com/andreiyurik/omarchy-tablet-mode/issues/new?template=machine-report.yml)**
with the output of:

```bash
~/.config/omarchy/plugins/andreiyurik.tablet-mode/bin/omarchy-tablet-mode detect
```

It prints the model as DMI reports it, along with the panel, digitizer and fold
sensor that were found, and the mounting `auto` picks. A model reported here is
added to `auto`, so the next person with it needs no setting at all. Each entry
is also a draft for the hwdb; once a model is fixed upstream, it can leave the
table.

## The bar widget

Click to lock the current orientation, the way a tablet's rotation lock works.
Middle-click rotates by hand. The icon shows whether the sensor is being
followed or the orientation is frozen.

## The pen

The plugin binds the built-in pen and touchscreen to the laptop's own panel and
turns them with it. That alone fixes the most common complaint: left unbound,
Hyprland spreads the pen across every monitor, so with an external display
connected the cursor lands far from the tip.

Everything else about the pen is a preference, and belongs in your
`~/.config/hypr/input.lua` rather than in a plugin:

- **Eraser button and pressure range** are the `input.tablettool` options
  (`eraser_button_mode`, `eraser_button_override`, `pressure_range_min`,
  `pressure_range_max`), described in the
  [Hyprland wiki](https://wiki.hypr.land/Configuring/Basics/Variables/). They
  apply to every tablet, not per device, which is why the plugin leaves them
  alone. libinput offers no pressure curve.
- **Taps and buttons reach only apps that speak the Wayland tablet protocol.**
  Elsewhere the pen just moves the cursor, and Hyprland does not turn the
  stylus buttons into mouse clicks. For writing and drawing, use apps built for
  it: Xournal++ and Rnote (`sudo pacman -S xournalpp rnote`) or Krita.
- **Remapping the stylus buttons** to keys takes
  [input-remapper](https://github.com/sezanzeb/input-remapper), which runs as a
  root service — something a plugin should not install for you.
- **Touch dying after using the pen** is a known driver bug on some Wacom AES
  machines ([input-wacom#310](https://github.com/linuxwacom/input-wacom/issues/310));
  `sudo rmmod wacom && sudo modprobe wacom` brings it back until it is fixed.

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

**A machine that locks while folded has to be opened to type the password.**
The built-in keyboard is off in tablet position, and Omarchy has no on-screen
keyboard. Opening the lid switches the keyboard back on at once; an on-screen
keyboard is a job for its own plugin, not this one.

**A window that ignores resize requests stays the size it was.** Nothing here
can help a hung application; it will sit at its old geometry until it responds.

## How it works, and why it works that way

**Rotation is applied live with `hyprctl eval`.** On a Lua config Hyprland
refuses `hyprctl keyword monitor`, but `eval` changes the running compositor
directly — the same way Omarchy's own monitor scaling does — so turning the
screen needs no config reload. The orientation is also recorded in
`~/.local/state/omarchy/tablet-mode/devices.conf`, and the Hyprland fragment
replays it whenever the config does reload.

**A reload cannot leave the screen straightened.** Another tool's monitor rules
may load after the fragment — hyprmoncfg's do, by design — and undo the turn
while the touchscreen stays turned. Rather than fight such tools for the last
line of `hyprland.lua`, the daemon listens on Hyprland's event socket and, the
moment a reload finishes, turns the panel back. You may see it straighten for
a fraction of a second.

**Settings are read from `shell.json`.** Omarchy stores a widget's settings on
its entry there, and the daemon reads them from that entry and follows the file,
so a change applies at once and does not depend on the widget and its service
being loaded together.

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
