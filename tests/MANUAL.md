# Checking a release on real hardware

`tests/run` covers the decisions; this covers the hardware, the compositor and
Omarchy around them. Go through it on a 2-in-1 before tagging a release, with
`journalctl --user -f | grep tablet-mode` open on the side. Note the machine
and anything that failed in the PR.

## Folding

- [ ] Fold into a tablet: the keyboard and touchpad stop after about two
      seconds, the screen follows the machine in all four directions.
- [ ] Open back into a laptop: the keyboard works at once, the screen stands
      upright, a held rotation lock is let go, an open on-screen keyboard goes.
- [ ] Open and close the lid quickly, and type right after opening: no key
      is lost.
- [ ] Tent and stand: the screen turns the right way up.

## Touch and pen

- [ ] Folded, in each direction, a tap lands under the finger and the pen
      draws under its tip.
- [ ] The panel's Keyboard button opens the on-screen keyboard on the panel.

## The bar panel

- [ ] Left and Right turn the screen and take the lock; Unlock follows the
      sensor again.
- [ ] Middle-click on the bar button turns the screen.

## Config reloads

- [ ] Toggle a workspace's layout (Super+L) a few times, upright and turned:
      the screen does not flip, or flips back within half a second.
- [ ] With a turned panel, `hyprctl reload`: it stays turned.
- [ ] Put `transform = 2` in a monitor rule for the panel in
      `~/.config/hypr/monitors.lua`: a notification names that file and line,
      and `omarchy-tablet-mode detect` lists it under `panel_turned_by`.
      Take it out again.

## Monitors

- [ ] Plug in an external monitor upright and turned: the panel turns only
      once the monitors have settled, and never covers the other display.
- [ ] Unplug it again, folded and open.
- [ ] Lid shut with a monitor attached: the panel stays off whatever the
      sensor says.

## Sleep and lock

- [ ] Suspend folded, resume: the keyboard stays off, the screen is turned.
- [ ] Lock the screen (Super+Ctrl+L) open and folded, unlock: nothing turns
      by itself.

## Lifecycle

- [ ] `omarchy-restart-shell`: one daemon (`pgrep -af "tablet-mode daemon"`),
      state as before.
- [ ] Disable the plugin while turned and folded: the screen stands upright
      and the keyboard works.
