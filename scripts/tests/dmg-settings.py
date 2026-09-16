"""No Finder, signing, mounted volumes, or third-party Python packages required."""
import runpy
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


class InstallerSettingsTests(unittest.TestCase):
    def setUp(self):
        self.app = "/private/tmp/Lens fixture with spaces/Lens.app"
        self.background = str(ROOT / "Packaging/background.tiff")
        self.settings = runpy.run_path(str(ROOT / "scripts/dmg-settings.py"), init_globals={
            "defines": {"root": str(ROOT), "app": self.app, "background": self.background}
        })

    def test_real_app_and_applications_are_the_only_install_targets(self):
        self.assertEqual(self.settings["files"], [self.app, str(ROOT / "LICENSE")])
        self.assertEqual(self.settings["symlinks"], {"Applications": "/Applications"})
        self.assertEqual(self.settings["hide"], ["LICENSE"])
        self.assertEqual(set(self.settings["icon_locations"]), {"Lens.app", "Applications"})

    def test_icons_are_aligned_and_centered_with_space_for_labels(self):
        source, target = (self.settings["icon_locations"][name] for name in ["Lens.app", "Applications"])
        self.assertEqual(source[1], target[1])
        self.assertEqual(source[0] + target[0], 720)
        self.assertLess(self.settings["icon_size"], target[0] - source[0])
        self.assertEqual(self.settings["window_rect"][1], (720, 472))
        self.assertLess(source[1] + self.settings["icon_size"] / 2 + self.settings["text_size"] * 2, 300)

    def test_finder_uses_fixed_icon_view_without_unrelated_chrome(self):
        self.assertEqual(self.settings["default_view"], "icon-view")
        self.assertIsNone(self.settings["arrange_by"])
        for key in ["show_toolbar", "show_status_bar", "show_sidebar", "show_pathbar", "show_tab_view"]:
            self.assertFalse(self.settings[key])
        self.assertLess(self.settings["grid_spacing"], 100)

    def test_artwork_and_original_icon_are_used_without_modifying_app(self):
        self.assertEqual(self.settings["hide_extensions"], [])
        self.assertNotIn("Lens.app", self.settings["hide"])
        self.assertEqual(self.settings["background"], self.background)
        self.assertTrue(Path(self.background).is_file())
        self.assertEqual(self.settings["icon"], self.app + "/Contents/Resources/AppIcon.icns")
        self.assertEqual(self.settings["format"], "UDZO")


if __name__ == "__main__":
    unittest.main()
