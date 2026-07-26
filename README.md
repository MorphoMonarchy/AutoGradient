> **AI-generated project:** The scripts in this repository were generated with AI assistance and should be reviewed and tested before use in important projects.

# AutoGradient

AutoGradient is a REAPER background script that automatically colors tracks from light to dark and optionally assigns track icons according to ordered, case-insensitive name rules.

For example, tracks containing `guitar` are grouped together and receive variations of the guitar base color according to their order in the track list. If a track matches multiple rules, the rule nearest the top of the priority list wins.

## Features

- Watches all tracks for renames, duplication, insertion, removal, and reordering.
- Matches track names without regard to letter case.
- Supports an ordered list of custom keywords, colors, and track icons.
- Generates a scalable light-to-dark gradient for each matching group.
- Leaves tracks that match no rule unchanged.
- Includes a ReaImGui configuration window with a color picker.
- Includes a searchable thumbnail browser for REAPER's track icons.
- Saves configuration persistently between REAPER sessions.

## Requirements

- REAPER
- [ReaPack](https://reapack.com/) for repository installation
- [ReaImGui](https://github.com/cfillion/reaimgui) 0.10 or newer for `AutoGradientConfig`

The background coloring script itself does not require ReaImGui.

## Install with ReaPack

Copy this repository URL:

```text
https://raw.githubusercontent.com/MorphoMonarchy/AutoGradient/master/index.xml
```

Then:

1. In REAPER, open **Extensions > ReaPack > Import repositories**.
2. Paste the URL and confirm.
3. Open **Extensions > ReaPack > Browse packages**.
4. Search for `AutoGradient`.
5. Select the package, choose **Install**, and apply the transaction.

ReaPack installs both `AutoGradient` and `AutoGradientConfig` in REAPER's main Action List.

## Usage

1. Open **Actions > Show action list**.
2. Run `AutoGradient` to start the background watcher.
3. Run `AutoGradientConfig` to add, delete, reorder, recolor, and assign track icons to rules.
4. Click **Save** in the configuration window to apply changes. A running watcher refreshes automatically.

`AutoGradient` is a deferred background action. Run it again through REAPER's running background scripts controls if you need to stop it.

To launch it automatically with REAPER, add the `AutoGradient` action to your existing startup action or startup-script workflow. The ReaPack package intentionally does not overwrite a user's global `__startup.lua`.

## Default rules

Rules are evaluated from top to bottom:

| Priority | Keyword | Base color | Track icon |
|---:|---|---|---|
| 1 | `best` | Pastel red `#CA8080` | None |
| 2 | `vox` | Pastel cyan `#76B4B4` | `mic.png` |
| 3 | `perc` | Pastel orange `#CB9D68` | `drums.png` |
| 4 | `guitar` | Pastel magenta `#BA7CAF` | `ac_guitar.png` |
| 5 | `bass` | Pastel green `#7FB48B` | `bass4.png` |
| 6 | `synth` | Light gray `#C4C4C4` | `drumbox.png` |

A track named `guitar_BEST` matches `best`, because `best` has the higher priority.

## Track icons

Each rule can optionally assign an icon from REAPER's `Data/track_icons` directory:

1. Run `AutoGradientConfig`.
2. Click **Choose...** in a rule's **Track icon** column.
3. Filter by filename if desired.
4. Click an icon thumbnail and save the rules.

Icon paths are stored relative to REAPER's `Data/track_icons` directory, so the built-in icon assignments remain portable across different REAPER installations.

Choosing **None** stops AutoGradient from managing the icon for that rule. Existing icons already applied to tracks are left unchanged.

## How the gradient works

- A group containing one matching track uses the exact base color.
- A group containing multiple tracks is colored from brighter to darker in track-list order.
- Larger groups receive a wider gradient, up to a safety limit that prevents colors from approaching pure white or black.

## Repository contents

- `AutoGradient/AutoGradient.lua` — background watcher and track-styling logic.
- `AutoGradient/AutoGradientConfig.lua` — ReaImGui rule editor.
- `AutoGradient/Settings.lua` — shared persistent settings module.
- `index.xml` — repository index imported by ReaPack.

## Feedback

Issues and suggestions can be submitted through the [GitHub issue tracker](https://github.com/MorphoMonarchy/AutoGradient/issues).
