#!/usr/bin/env python3
"""Package an already notarized app with the Refs drag-to-Applications layout."""

import argparse
from pathlib import Path
import plistlib
import subprocess

import dmgbuild


def main():
    root = Path(__file__).resolve().parent.parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path, default=root / "build/Refs-notarized/Refs.app")
    parser.add_argument("--output", type=Path, default=root / "build/Refs-macOS.dmg")
    args = parser.parse_args()
    app = args.app.resolve()
    output = args.output.resolve()
    if not (app / "Contents/Info.plist").is_file():
        parser.error(f"App bundle not found: {app}")

    # Require the app's existing signature and offline notarization ticket.
    subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)
    subprocess.run(["xcrun", "stapler", "validate", str(app)], check=True)
    signature = subprocess.run(
        ["codesign", "--display", "--verbose=4", str(app)],
        text=True, capture_output=True, check=True,
    )
    identity = next(
        (line.removeprefix("Authority=")
         for line in (signature.stdout + signature.stderr).splitlines()
         if line.startswith("Authority=Developer ID Application:")),
        None,
    )
    if identity is None:
        parser.error("The app must be signed with a Developer ID Application certificate.")
    with (app / "Contents/Info.plist").open("rb") as info_file:
        info = plistlib.load(info_file)
    output.parent.mkdir(parents=True, exist_ok=True)
    background = output.parent / "Refs-DMG-background.tiff"
    subprocess.run(
        ["swift", str(root / "Resources/DMG/background.swift"), str(background)],
        check=True,
    )
    dmgbuild.build_dmg(
        str(output),
        "Refs",
        settings={
            "format": "UDZO",
            "files": [str(app)],
            "symlinks": {"Applications": "/Applications"},
            "icon": str(app / "Contents/Resources/Refs.icns"),
            "background": str(background),
            "icon_locations": {app.name: (166, 232), "Applications": (474, 232)},
            "window_rect": ((240, 180), (640, 440)),
            "default_view": "icon-view",
            "icon_size": 100,
            "text_size": 13,
            "label_pos": "bottom",
            "hide_extension": [app.name],
            "grid_spacing": 84,
            "show_status_bar": False,
            "show_tab_view": False,
            "show_toolbar": False,
            "show_pathbar": False,
            "show_sidebar": False,
        },
    )
    subprocess.run(
        ["codesign", "--force", "--timestamp", "--identifier",
         info["CFBundleIdentifier"] + ".diskimage", "--sign", identity, str(output)],
        check=True,
    )
    print(f"Packaged {output}")


if __name__ == "__main__":
    main()
