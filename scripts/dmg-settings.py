"""Finder presentation only; no app signing, notarization, or publication."""
from pathlib import Path

application = Path(defines["app"]).resolve()  # supplied by dmgbuild
root = Path(defines["root"]).resolve()
files = [str(application), str(root / "LICENSE")]
symlinks = {"Applications": "/Applications"}
hide = ["LICENSE"]  # retained at root for license compliance; not a third install target
# SetFile -a E writes FinderInfo onto the signed bundle and breaks strict verification.
hide_extensions = []
icon = str(application / "Contents/Resources/AppIcon.icns")
background = defines["background"]
format = "UDZO"
filesystem = "HFS+"
# Finder's titlebar consumes 32 points on macOS 26; keep all 440 artwork points visible.
window_rect = ((160, 160), (720, 472))
show_toolbar = False
show_status_bar = False
show_sidebar = False
show_pathbar = False
show_tab_view = False
default_view = "icon-view"
include_icon_view_settings = True
include_list_view_settings = False
arrange_by = None
grid_spacing = 80
icon_size = 96
text_size = 14
label_pos = "bottom"
icon_locations = {"Lens.app": (192, 214), "Applications": (528, 214)}
