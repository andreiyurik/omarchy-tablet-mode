import importlib.machinery
import importlib.util
import os
import tempfile
import unittest
from unittest import mock

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CLI_PATH = os.path.join(ROOT, "bin", "omarchy-tablet-mode")


def load_cli(home):
    """Import the CLI with its paths pointed into a throwaway HOME."""
    env = {"HOME": home, "XDG_CONFIG_HOME": "", "XDG_STATE_HOME": "",
           "HYPRLAND_INSTANCE_SIGNATURE": "sig-now"}
    with mock.patch.dict(os.environ, env):
        loader = importlib.machinery.SourceFileLoader("tablet_mode_cli", CLI_PATH)
        spec = importlib.util.spec_from_loader(loader.name, loader)
        module = importlib.util.module_from_spec(spec)
        loader.exec_module(module)
    return module


def kernel_device(name, switches=0, **props):
    return {"name": name, "switches": switches, "props": props}


class CliTestCase(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.home = self.tmp.name
        self.cli = load_cli(self.home)
        env = mock.patch.dict(os.environ, {"HYPRLAND_INSTANCE_SIGNATURE": "sig-now"})
        env.start()
        self.addCleanup(env.stop)
        self.addCleanup(self.tmp.cleanup)

    def write(self, path, text):
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w") as handle:
            handle.write(text)

    def read(self, path):
        with open(path) as handle:
            return handle.read()


class PositionsTest(CliTestCase):
    def test_named_and_relative_positions(self):
        resolve = self.cli.resolve_position
        self.assertEqual(resolve("left", 0), 3)
        self.assertEqual(resolve("next", 3), 0)
        self.assertEqual(resolve("prev", 0), 3)
        self.assertEqual(resolve("2", 0), 2)
        self.assertIsNone(resolve("4", 0))
        self.assertIsNone(resolve("sideways", 0))

    def test_every_mapping_is_a_permutation(self):
        for name, mapping in self.cli.MAPPINGS.items():
            self.assertEqual(sorted(mapping), sorted(self.cli.ORIENTATIONS), name)
            self.assertEqual(sorted(mapping.values()), [0, 1, 2, 3], name)


class MappingTest(CliTestCase):
    def setUp(self):
        super().setUp()
        known = mock.patch.dict(self.cli.KNOWN_MOUNTINGS, {"Odd Convertible 14": "rotated-180"})
        known.start()
        self.addCleanup(known.stop)

    def test_standard_turns_the_way_gnome_and_iio_hyprland_do(self):
        # mutter's meta_orientation_to_transform: left-up is 90 degrees, right-up 270.
        standard = self.cli.MAPPINGS["standard"]
        self.assertEqual((standard["left-up"], standard["right-up"]), (1, 3))

    def test_each_mounting_is_standard_with_its_named_mirror(self):
        m = self.cli.MAPPINGS
        s = m["standard"]
        self.assertEqual(m["portrait-swapped"], dict(s, **{"right-up": s["left-up"],
                                                          "left-up": s["right-up"]}))
        self.assertEqual(m["landscape-swapped"], dict(s, **{"normal": s["bottom-up"],
                                                           "bottom-up": s["normal"]}))
        self.assertEqual(m["rotated-180"], {k: (v + 2) % 4 for k, v in s.items()})

    def test_auto_uses_the_mounting_known_for_the_model(self):
        self.assertEqual(self.cli.resolve_mapping("auto", "Odd Convertible 14"), "rotated-180")

    def test_auto_falls_back_to_standard_for_an_unknown_model(self):
        self.assertEqual(self.cli.resolve_mapping("auto", "ThinkPad X1 Yoga Gen 6"), "standard")

    def test_a_chosen_mounting_wins_over_the_known_one(self):
        self.assertEqual(self.cli.resolve_mapping("portrait-swapped", "Odd Convertible 14"),
                         "portrait-swapped")

    def test_every_known_mounting_exists(self):
        for model, mounting in self.cli.KNOWN_MOUNTINGS.items():
            self.assertIn(mounting, self.cli.MAPPINGS, model)


class SettingsTest(CliTestCase):
    def test_settings_are_read_from_the_entry_in_the_bar_layout(self):
        self.write(self.cli.SHELL_JSON, """{"bar": {"layout": {"right": [
            {"id": "omarchy.tray"},
            {"id": "andreiyurik.tablet-mode", "mapping": "rotated-180"}]}}}""")
        self.assertEqual(self.cli.plugin_entry()["mapping"], "rotated-180")
        self.assertTrue(self.cli.plugin_enabled())

    def test_a_mention_elsewhere_does_not_count_as_enabled(self):
        self.write(self.cli.SHELL_JSON, '{"note": "andreiyurik.tablet-mode", "plugins": []}')
        self.assertFalse(self.cli.plugin_enabled())

    def test_a_broken_shell_json_means_disabled(self):
        self.write(self.cli.SHELL_JSON, "{not json")
        self.assertIsNone(self.cli.plugin_entry())


class DesiredTransformTest(CliTestCase):
    def desired(self, **kwargs):
        args = {"mapping": self.cli.MAPPINGS["standard"], "tablet_only": True,
                "is_locked": False, "is_folded": True, "orientation": "left-up",
                "recorded": 0}
        args.update(kwargs)
        return self.cli.desired_transform(**args)

    def test_folded_follows_the_sensor(self):
        self.assertEqual(self.desired(), 1)

    def test_open_stands_upright(self):
        self.assertEqual(self.desired(is_folded=False, recorded=1), 0)

    def test_open_follows_the_sensor_when_asked_to(self):
        self.assertEqual(self.desired(is_folded=False, tablet_only=False), 1)

    def test_a_lock_holds_what_was_recorded_even_after_a_reload_straightened_it(self):
        self.assertEqual(self.desired(is_locked=True, recorded=3), 3)

    def test_no_sensor_reading_holds_what_was_recorded(self):
        self.assertEqual(self.desired(orientation=None, recorded=2), 2)
        self.assertEqual(self.desired(orientation="undefined", recorded=2), 2)

    def test_a_machine_without_fold_sensor_follows_the_sensor(self):
        self.assertEqual(self.desired(is_folded=None), 1)


class ConfTest(CliTestCase):
    def test_round_trip(self):
        conf = {"panel": "eDP-1", "mode": "1920x1200@60.026", "transform": 1,
                "touch": ["wacom-finger", "wacom-pen"], "internal": ["kbd"]}
        self.assertTrue(self.cli.write_conf(conf))
        read = self.cli.read_conf()
        self.assertEqual(read["panel"], "eDP-1")
        self.assertEqual(read["mode"], "1920x1200@60.026")
        self.assertEqual(read["transform"], "1")
        self.assertEqual(read["touch"], ["wacom-finger", "wacom-pen"])

    def test_unchanged_conf_is_not_rewritten(self):
        conf = {"panel": "eDP-1", "touch": [], "internal": []}
        self.assertTrue(self.cli.write_conf(conf))
        self.assertFalse(self.cli.write_conf(conf))

    def test_a_newline_in_a_device_name_cannot_forge_a_line(self):
        self.cli.write_conf({"panel": "eDP-1", "touch": ["evil\npanel=HDMI-A-1"],
                             "internal": []})
        self.assertEqual(self.cli.read_conf()["panel"], "eDP-1")
        self.assertEqual(self.cli.read_conf()["touch"], [])

    def test_lua_string_escapes_quotes_and_backslashes(self):
        self.assertEqual(self.cli.lua_string('a"b\\c'), '"a\\"b\\\\c"')


class FoldTest(CliTestCase):
    def test_sysfs_wins_over_a_switch_event(self):
        sysfs = os.path.join(self.home, "tablet_mode")
        self.write(sysfs, "0\n")
        self.write(self.cli.FOLD_FILE, "sig-now 1\n")
        conf = {"tablet_sysfs": sysfs, "tablet_switch": ["Switch"]}
        self.assertIs(self.cli.folded(conf), False)

    def test_switch_event_from_this_session_counts(self):
        self.write(self.cli.FOLD_FILE, "sig-now 1\n")
        self.assertIs(self.cli.folded({"tablet_switch": ["Switch"]}), True)

    def test_switch_event_from_an_earlier_session_does_not(self):
        self.write(self.cli.FOLD_FILE, "sig-before 1\n")
        self.assertIs(self.cli.folded({"tablet_switch": ["Switch"]}), False)

    def test_no_sensor_at_all(self):
        with mock.patch.object(self.cli, "chassis_folds", return_value=False):
            self.assertIsNone(self.cli.folded({"touch": [], "internal": [], "tablet_switch": []}))

    def test_a_convertible_whose_switch_is_not_registered_yet_starts_open(self):
        # intel-hid registers its switch device only on the first fold.
        with mock.patch.object(self.cli, "chassis_folds", return_value=True):
            self.assertIs(self.cli.folded({"tablet_switch": []}), False)

    def test_an_event_from_a_switch_detection_never_saw_still_counts(self):
        self.write(self.cli.FOLD_FILE, "sig-now 1\n")
        with mock.patch.object(self.cli, "chassis_folds", return_value=False):
            self.assertIs(self.cli.folded({"tablet_switch": []}), True)

    def test_the_chassis_type_says_whether_a_machine_folds(self):
        for chassis, folds in (("31", True), ("32", True), ("10", False)):
            self.write(os.path.join(self.home, "chassis_type"), chassis + "\n")
            with mock.patch.object(self.cli, "CHASSIS_TYPE",
                                   os.path.join(self.home, "chassis_type")):
                self.assertIs(self.cli.chassis_folds(), folds, chassis)


class DetectionTest(CliTestCase):
    kernel = [
        kernel_device("AT Translated Set 2 keyboard",
                      ID_INTEGRATION="internal", ID_INPUT_KEYBOARD="1"),
        kernel_device("Power Button", ID_INTEGRATION="internal", ID_INPUT_KEY="1"),
        kernel_device("ThinkPad Extra Buttons", switches=0xa,
                      ID_INTEGRATION="internal", ID_INPUT_KEY="1", ID_INPUT_SWITCH="1"),
        kernel_device("Lid Switch", switches=0x1, ID_INTEGRATION="internal"),
        kernel_device("Intel HID switches", switches=0x2, ID_INTEGRATION="internal"),
        kernel_device("SYNA8008:00 06CB:CE58 Touchpad",
                      ID_INTEGRATION="internal", ID_INPUT_TOUCHPAD="1"),
        kernel_device("Wacom HID 5276 Finger",
                      ID_INTEGRATION="internal", ID_INPUT_TOUCHSCREEN="1"),
        kernel_device("Wacom Intuos Pro M Pen",
                      ID_INTEGRATION="external", ID_INPUT_TABLET="1"),
        kernel_device("Logitech MX Master 3",
                      ID_INTEGRATION="external", ID_INPUT_KEYBOARD="1", ID_INPUT_MOUSE="1"),
    ]
    devices = {
        "keyboards": [{"name": "at-translated-set-2-keyboard"}, {"name": "power-button"},
                      {"name": "thinkpad-extra-buttons"}, {"name": "logitech-mx-master-3"}],
        "mice": [{"name": "syna8008:00-06cb:ce58-touchpad"},
                 {"name": "logitech-mx-master-3-1"}],
        "touch": [{"name": "wacom-hid-5276-finger"}],
        "tablets": [{"name": "wacom-intuos-pro-m-pen"}, {"address": "0x1"}],
        "switches": [{"name": "Lid Switch"}, {"name": "ThinkPad Extra Buttons"},
                     {"name": "Intel HID switches"}],
    }

    def test_internal_input_is_the_builtin_keyboard_and_pointers_only(self):
        self.assertEqual(self.cli.detect_internal_devices(self.devices, self.kernel),
                         ["at-translated-set-2-keyboard", "syna8008:00-06cb:ce58-touchpad"])

    def test_an_external_drawing_tablet_does_not_turn_with_the_panel(self):
        self.assertEqual(self.cli.detect_touch_devices(self.devices, self.kernel),
                         ["wacom-hid-5276-finger"])

    def test_every_tablet_switch_is_found_by_its_capability_not_its_name(self):
        self.assertEqual(self.cli.detect_tablet_switches(self.devices, self.kernel),
                         ["ThinkPad Extra Buttons", "Intel HID switches"])

    def test_without_udev_names_are_the_fallback(self):
        kernel = [dict(d, props={}) for d in self.kernel]
        self.assertEqual(self.cli.detect_internal_devices(self.devices, kernel),
                         ["at-translated-set-2-keyboard", "syna8008:00-06cb:ce58-touchpad"])


class PanelTest(CliTestCase):
    edp = {"name": "eDP-1", "width": 1920, "height": 1200, "refreshRate": 60.0,
           "x": 0, "y": 0, "scale": 1.25, "transform": 0, "disabled": False}
    hdmi = {"name": "HDMI-A-1", "width": 2560, "height": 1440, "refreshRate": 60.0,
            "x": 0, "y": 0, "scale": 1, "transform": 0, "disabled": False}

    def monitors(self, *monitors):
        return mock.patch.object(self.cli, "hyprctl", return_value=list(monitors))

    def test_an_external_monitor_is_never_taken_for_the_panel(self):
        with self.monitors(self.hdmi):
            self.assertIsNone(self.cli.detect_panel())

    def test_a_panel_switched_off_is_still_found(self):
        with self.monitors(self.hdmi, dict(self.edp, disabled=True)):
            self.assertEqual(self.cli.detect_panel()["name"], "eDP-1")

    def rotate_with(self, panel):
        with self.monitors(self.hdmi, panel), mock.patch.object(self.cli, "log"), \
                mock.patch.object(self.cli, "refresh_conf",
                                  side_effect=lambda updates=None: (dict(updates or {}), False)), \
                mock.patch.object(self.cli, "hypr_eval", return_value=True) as hypr_eval:
            self.assertEqual(self.cli.apply_rotation(1), 0)
        return hypr_eval

    def test_a_panel_the_compositor_has_off_is_not_turned(self):
        self.assertFalse(self.rotate_with(dict(self.edp, disabled=True)).called)

    def test_a_panel_omarchy_holds_off_is_not_turned(self):
        self.write(os.path.join(self.cli.OMARCHY_TOGGLES, "internal-monitor-clamshell.lua"),
                   'hl.monitor({ output = "eDP-1", disabled = true })\n')
        self.assertFalse(self.rotate_with(self.edp).called)

    def test_an_enabled_panel_is_turned(self):
        with mock.patch.object(self.cli, "relayout", return_value=0), \
                mock.patch.object(self.cli.time, "sleep"):
            self.assertTrue(self.rotate_with(self.edp).called)


class InputTest(CliTestCase):
    def test_unfolding_leaves_omarchys_disabled_touchpad_alone(self):
        self.write(self.cli.OMARCHY_DISABLED_INPUT[0], "touchpad\n")
        with mock.patch.object(self.cli, "hypr_eval", return_value=True) as hypr_eval:
            self.cli.apply_input(False, {"internal": ["keyboard", "touchpad"]})
        self.assertEqual(hypr_eval.call_args[0][0],
                         ['hl.device({ name = "keyboard", enabled = true })'])

    def test_folding_switches_everything_off(self):
        self.write(self.cli.OMARCHY_DISABLED_INPUT[0], "touchpad\n")
        with mock.patch.object(self.cli, "hypr_eval", return_value=True) as hypr_eval:
            self.cli.apply_input(True, {"internal": ["keyboard", "touchpad"]})
        self.assertEqual(len(hypr_eval.call_args[0][0]), 2)
        self.assertTrue(all("enabled = false" in s for s in hypr_eval.call_args[0][0]))


class RelayoutTest(CliTestCase):
    def run_relayout(self, clients, layout="dwindle", transform=1):
        panel = {"name": "eDP-1", "width": 1920, "height": 1200, "transform": transform,
                 "activeWorkspace": {"id": 1}}
        dispatched = []

        def hyprctl(*args, parse_json=True):
            if args[0] == "monitors":
                return [panel]
            if args[0] == "workspaces":
                return [{"id": 1, "tiledLayout": layout}]
            if args[0] == "clients":
                return clients
            if args[0] == "activewindow":
                return {"address": "0xa"}
            dispatched.append(args[1])
            return ""

        with mock.patch.object(self.cli, "hyprctl", side_effect=hyprctl):
            return self.cli.relayout(), dispatched

    def client(self, address, at, size):
        return {"address": address, "at": at, "size": size, "mapped": True,
                "floating": False, "fullscreen": False, "workspace": {"id": 1}}

    def test_two_columns_on_a_tall_screen_become_rows(self):
        clients = [self.client("0xa", [0, 0], [590, 1900]),
                   self.client("0xb", [600, 0], [590, 1900])]
        flipped, dispatched = self.run_relayout(clients)
        self.assertEqual(flipped, 1)
        self.assertIn('hl.dsp.layout("togglesplit")', dispatched)

    def test_rows_on_a_tall_screen_are_left_alone(self):
        clients = [self.client("0xa", [0, 0], [1190, 950]),
                   self.client("0xb", [0, 960], [1190, 950])]
        self.assertEqual(self.run_relayout(clients)[0], 0)

    def test_three_windows_are_not_guessed_at(self):
        clients = [self.client("0xa", [0, 0], [390, 1900]),
                   self.client("0xb", [400, 0], [390, 1900]),
                   self.client("0xc", [800, 0], [390, 1900])]
        self.assertEqual(self.run_relayout(clients)[0], 0)

    def test_other_layouts_are_not_touched(self):
        clients = [self.client("0xa", [0, 0], [590, 1900]),
                   self.client("0xb", [600, 0], [590, 1900])]
        self.assertEqual(self.run_relayout(clients, layout="scrolling")[0], 0)


class BindsTest(CliTestCase):
    def test_every_switch_and_the_lazily_registered_intel_ones_are_bound(self):
        lua = "\n".join(self.cli.bind_statements({"tablet_switch": ["ThinkPad Extra Buttons"]}))
        for name in ("ThinkPad Extra Buttons", "Intel HID switches", "Intel Virtual Switches"):
            for state in ("on", "off"):
                self.assertIn('"switch:%s:%s"' % (state, name), lua)
        self.assertEqual(lua.count("hl.bind("), 6)
        self.assertIn("{ locked = true }", lua)

    def test_a_switch_named_twice_is_bound_once(self):
        lua = "\n".join(self.cli.bind_statements({"tablet_switch": ["Intel HID switches"]}))
        self.assertEqual(lua.count('"switch:on:Intel HID switches"'), 1)

    def test_the_binds_of_an_earlier_daemon_come_down_first(self):
        statements = self.cli.bind_statements({"tablet_switch": []})
        unbind = next(i for i, s in enumerate(statements) if ":unbind()" in s)
        first_bind = next(i for i, s in enumerate(statements) if "hl.bind(" in s)
        self.assertLess(unbind, first_bind)

    def test_unbinding_alone_binds_nothing(self):
        lua = "\n".join(self.cli.bind_statements({"tablet_switch": ["X"]}, bind=False))
        self.assertIn(":unbind()", lua)
        self.assertNotIn("hl.bind(", lua)

    def test_the_cli_path_is_quoted_for_the_shell_and_for_lua(self):
        with mock.patch.object(self.cli, "CLI", "/home/o'neil/bin/tablet mode"):
            lua = "\n".join(self.cli.bind_statements({"tablet_switch": []}))
        self.assertIn('hl.dsp.exec_cmd("\'/home/o\'\\\\\'\'neil/bin/tablet mode\' fold on")', lua)

    def test_a_quote_in_a_switch_name_stays_inside_the_string(self):
        lua = "\n".join(self.cli.bind_statements({"tablet_switch": ['Odd "Switch"']}))
        self.assertIn('"switch:on:Odd \\"Switch\\""', lua)


class KeyboardTest(CliTestCase):
    def enable(self, *ids):
        entries = ", ".join('{"id": "%s"}' % i for i in ids)
        self.write(self.cli.SHELL_JSON, '{"bar": {"layout": {"right": [%s]}}}' % entries)

    def test_no_keyboard_plugin_means_none(self):
        self.enable("andreiyurik.tablet-mode")
        self.assertIsNone(self.cli.find_keyboard())
        self.assertFalse(self.cli.run_keyboard("show"))

    def test_the_first_known_keyboard_enabled_is_used(self):
        self.enable("io.github.frostmute.tablet-keyboard", "io.github.abdxdev.onscreen-keyboard")
        self.assertEqual(self.cli.find_keyboard()[0], "io.github.abdxdev.onscreen-keyboard")

    def test_a_panel_keyboard_is_summoned_and_hidden_through_the_shell(self):
        keyboard = next(k for k in self.cli.KEYBOARDS if k[0].endswith("abdxdev.onscreen-keyboard"))
        self.assertEqual(self.cli.keyboard_command(keyboard, "show"),
                         ["omarchy-shell", "shell", "summon", keyboard[0], "{}"])
        self.assertEqual(self.cli.keyboard_command(keyboard, "hide"),
                         ["omarchy-shell", "shell", "hide", keyboard[0]])

    def test_a_keyboard_with_its_own_ipc_target_is_asked_directly(self):
        keyboard = next(k for k in self.cli.KEYBOARDS if k[0].endswith("mtolhuys.onscreen-keyboard"))
        self.assertEqual(self.cli.keyboard_command(keyboard, "toggle"),
                         ["omarchy-shell", "onscreen-keyboard", "toggle"])

    def run_with_monitors(self, monitors, **kwargs):
        self.enable("io.github.abdxdev.onscreen-keyboard")
        calls = []

        def hyprctl(*args, parse_json=True):
            calls.append(args)
            return monitors if args[0] == "monitors" else ""

        with mock.patch.object(self.cli, "hyprctl", side_effect=hyprctl), \
                mock.patch.object(self.cli.subprocess, "Popen") as popen:
            self.assertTrue(self.cli.run_keyboard("show", **kwargs))
        self.assertEqual(popen.call_args[0][0][:3], ["omarchy-shell", "shell", "summon"])
        return [c for c in calls if c[0] == "dispatch"]

    def test_a_fold_moves_the_focus_to_the_panel_before_the_keyboard_opens(self):
        monitors = [{"name": "HDMI-A-1", "focused": True},
                    {"name": "eDP-1", "focused": False, "disabled": False}]
        self.assertEqual(self.run_with_monitors(monitors, on_panel=True),
                         [("dispatch", 'hl.dsp.focus({ monitor = "eDP-1" })')])

    def test_a_focused_panel_is_left_as_it_is(self):
        monitors = [{"name": "eDP-1", "focused": True, "disabled": False}]
        self.assertEqual(self.run_with_monitors(monitors, on_panel=True), [])

    def test_opening_by_hand_does_not_move_the_focus(self):
        monitors = [{"name": "HDMI-A-1", "focused": True}, {"name": "eDP-1", "focused": False}]
        self.assertEqual(self.run_with_monitors(monitors), [])

    def run_command(self, action, is_folded):
        with mock.patch.object(self.cli, "folded", return_value=is_folded), \
                mock.patch.object(self.cli, "run_keyboard", return_value=True) as run, \
                mock.patch.object(self.cli.sys, "argv", ["omarchy-tablet-mode", "keyboard", action]):
            self.assertEqual(self.cli.main(), 0)
        return run.call_args.kwargs["on_panel"]

    def test_the_keyboard_button_opens_on_the_panel_while_folded(self):
        self.assertTrue(self.run_command("toggle", True))
        self.assertTrue(self.run_command("show", True))

    def test_the_keyboard_button_opens_where_the_focus_is_as_a_laptop(self):
        self.assertFalse(self.run_command("toggle", False))
        self.assertFalse(self.run_command("toggle", None))

    def test_hiding_the_keyboard_moves_no_focus(self):
        self.assertFalse(self.run_command("hide", True))

    def test_folding_brings_the_keyboard_up_and_opening_puts_it_away(self):
        on_lid = self.cli.keyboard_on_lid
        self.assertEqual(on_lid(False, True, wanted=True, shown=False), "show")
        self.assertEqual(on_lid(True, False, wanted=True, shown=True), "hide")

    def test_nothing_happens_without_a_change_of_the_lid(self):
        on_lid = self.cli.keyboard_on_lid
        self.assertIsNone(on_lid(None, True, wanted=True, shown=False))  # first reading
        self.assertIsNone(on_lid(True, True, wanted=True, shown=True))

    def test_a_keyboard_opened_by_hand_stays_when_the_machine_opens(self):
        self.assertIsNone(self.cli.keyboard_on_lid(True, False, wanted=True, shown=False))

    def test_folding_leaves_the_keyboard_alone_when_not_wanted(self):
        self.assertIsNone(self.cli.keyboard_on_lid(False, True, wanted=False, shown=False))

    def test_status_names_the_keyboard(self):
        self.enable("io.github.frostmute.tablet-keyboard")
        with mock.patch.object(self.cli, "hyprctl", return_value=[]):
            self.assertEqual(self.cli.status({})["keyboard"], "Omaqwerty")


class SensorProxyTest(CliTestCase):
    def test_status_says_whether_iio_sensor_proxy_is_installed(self):
        policy = os.path.join(self.home, "net.hadess.SensorProxy.conf")
        with mock.patch.object(self.cli, "SENSOR_PROXY_POLICY", policy), \
                mock.patch.object(self.cli, "hyprctl", return_value=[]):
            self.assertIs(self.cli.status({})["sensorInstalled"], False)
            self.write(policy, "<busconfig/>\n")
            self.assertIs(self.cli.status({})["sensorInstalled"], True)


class SetupTest(CliTestCase):
    user_config = 'require("hypr.monitors")\n\n-- a line of their own\n'

    def setUp(self):
        super().setUp()
        self.lua = self.cli.HYPRLAND_LUA
        self.write(self.lua, self.user_config)
        for name, value in (("refresh_conf", mock.Mock(return_value=({}, False))),
                            ("subprocess", mock.Mock()), ("log", mock.Mock())):
            patcher = mock.patch.object(self.cli, name, value)
            patcher.start()
            self.addCleanup(patcher.stop)

    def old_block(self):
        return ("%s\ndo local path = \"/x/rotation.lua\"; dofile(path) end\n%s\n"
                % (self.cli.MARKER_BEGIN, self.cli.MARKER_END))

    def test_leaves_a_config_without_the_old_block_untouched(self):
        self.cli.setup()
        self.assertEqual(self.read(self.lua), self.user_config)
        self.assertFalse(self.cli.subprocess.run.called)

    def test_takes_out_the_block_earlier_versions_added_and_nothing_else(self):
        later = "\n-- [key-visualizer] a later tool\ndofile(\"/y.lua\")\n"
        self.write(self.lua, self.user_config + "\n\n" + self.old_block() + later)
        self.cli.setup()
        text = self.read(self.lua)
        self.assertNotIn(self.cli.MARKER_BEGIN, text)
        self.assertNotIn("rotation.lua", text)
        self.assertIn("-- a line of their own", text)
        self.assertIn('dofile("/y.lua")', text)
        self.assertTrue(self.cli.subprocess.run.called)

    def test_a_symlinked_hyprland_lua_stays_a_link(self):
        dotfiles = os.path.join(self.home, "dotfiles", "hyprland.lua")
        self.write(dotfiles, self.user_config + "\n" + self.old_block())
        os.remove(self.lua)
        os.symlink(dotfiles, self.lua)
        self.cli.setup()
        self.assertTrue(os.path.islink(self.lua))
        self.assertNotIn(self.cli.MARKER_BEGIN, self.read(dotfiles))

    def test_a_missing_hyprland_lua_is_not_an_error(self):
        os.remove(self.lua)
        self.assertEqual(self.cli.setup(), 0)
        self.assertFalse(os.path.exists(self.lua))


if __name__ == "__main__":
    unittest.main()
