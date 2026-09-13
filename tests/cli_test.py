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
    def test_auto_uses_the_mounting_known_for_the_model(self):
        self.assertEqual(self.cli.resolve_mapping("auto", "ThinkPad X1 Yoga Gen 6"),
                         "portrait-swapped")

    def test_auto_falls_back_to_standard_for_an_unknown_model(self):
        self.assertEqual(self.cli.resolve_mapping("auto", "Some Convertible 13"), "standard")

    def test_a_chosen_mounting_wins_over_the_known_one(self):
        self.assertEqual(self.cli.resolve_mapping("rotated-180", "ThinkPad X1 Yoga Gen 6"),
                         "rotated-180")

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
                "is_locked": False, "is_folded": True, "orientation": "right-up",
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
        conf = {"tablet_sysfs": sysfs, "tablet_switch": "Switch"}
        self.assertIs(self.cli.folded(conf), False)

    def test_switch_event_from_this_session_counts(self):
        self.write(self.cli.FOLD_FILE, "sig-now 1\n")
        self.assertIs(self.cli.folded({"tablet_switch": "Switch"}), True)

    def test_switch_event_from_an_earlier_session_does_not(self):
        self.write(self.cli.FOLD_FILE, "sig-before 1\n")
        self.assertIs(self.cli.folded({"tablet_switch": "Switch"}), False)

    def test_no_sensor_at_all(self):
        self.assertIsNone(self.cli.folded({"touch": [], "internal": []}))


class DetectionTest(CliTestCase):
    kernel = [
        kernel_device("AT Translated Set 2 keyboard",
                      ID_INTEGRATION="internal", ID_INPUT_KEYBOARD="1"),
        kernel_device("Power Button", ID_INTEGRATION="internal", ID_INPUT_KEY="1"),
        kernel_device("ThinkPad Extra Buttons", switches=0xa,
                      ID_INTEGRATION="internal", ID_INPUT_KEY="1", ID_INPUT_SWITCH="1"),
        kernel_device("Lid Switch", switches=0x1, ID_INTEGRATION="internal"),
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
        "switches": [{"name": "Lid Switch"}, {"name": "ThinkPad Extra Buttons"}],
    }

    def test_internal_input_is_the_builtin_keyboard_and_pointers_only(self):
        self.assertEqual(self.cli.detect_internal_devices(self.devices, self.kernel),
                         ["at-translated-set-2-keyboard", "syna8008:00-06cb:ce58-touchpad"])

    def test_an_external_drawing_tablet_does_not_turn_with_the_panel(self):
        self.assertEqual(self.cli.detect_touch_devices(self.devices, self.kernel),
                         ["wacom-hid-5276-finger"])

    def test_tablet_switch_is_found_by_its_capability_not_its_name(self):
        self.assertEqual(self.cli.detect_tablet_switch(self.devices, self.kernel),
                         "ThinkPad Extra Buttons")

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


class SetupTest(CliTestCase):
    def setUp(self):
        super().setUp()
        self.lua = self.cli.HYPRLAND_LUA
        self.write(self.lua, 'require("hypr.monitors")\n')
        for name, value in (("refresh_conf", mock.Mock(return_value=({}, False))),
                            ("subprocess", mock.Mock())):
            patcher = mock.patch.object(self.cli, name, value)
            patcher.start()
            self.addCleanup(patcher.stop)

    def test_adds_a_guarded_block_once(self):
        self.cli.setup()
        self.cli.setup()
        text = self.read(self.lua)
        self.assertEqual(text.count(self.cli.MARKER_BEGIN), 1)
        self.assertIn("io.open(path", text)
        self.assertTrue(os.path.exists(self.lua + ".tablet-mode-backup"))

    def test_replaces_the_old_unguarded_block(self):
        self.write(self.lua, 'require("hypr.monitors")\n\n%s\ndofile("/x/rotation.lua")\n%s\n'
                   % (self.cli.MARKER_BEGIN, self.cli.MARKER_END))
        self.cli.setup()
        text = self.read(self.lua)
        self.assertNotIn('dofile("/x/rotation.lua")', text)
        self.assertEqual(text.count(self.cli.MARKER_BEGIN), 1)

    def test_leaves_a_wired_block_where_it_is(self):
        self.cli.setup()
        with open(self.lua, "a") as handle:
            handle.write("-- a later tool's block\n")
        before = self.read(self.lua)
        self.cli.setup()
        self.assertEqual(self.read(self.lua), before)

    def test_remove_restores_the_file(self):
        self.cli.setup()
        self.cli.setup(remove=True)
        self.assertEqual(self.read(self.lua), 'require("hypr.monitors")\n')


if __name__ == "__main__":
    unittest.main()
