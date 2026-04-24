## Installation

This port accepts data from either **Sonic Origins** (recommended) or the **mobile Sonic The Hedgehog** Android APK. Drop the appropriate files into `ports/sonic.1/` and launch — the port patcher handles the rest on first run.

### Origins data (recommended)

Copy these files from your Sonic Origins install (`image/x64/raw/` path:

| File | Source |
|--|--|
| `Sonic1u.rsdk` | `image/x64/raw/retro/Sonic1u.rsdk` |
| `STH1_music.acb` | `image/x64/raw/sound/STH1_music.acb` |
| `STH1_music.awb` | `image/x64/raw/sound/STH1_music.awb` |
| `STH1_sfx.acb` | `image/x64/raw/sound/STH1_sfx.acb` |
| `HITE_sfx.acb` | `image/x64/raw/sound/HITE_sfx.acb` |

On first launch the patcher will extract the RSDK container, transcode the Origins CRIWARE audio to the engine-expected `.wav` / `.ogg` layout, flip the GameConfig into Anniversary mode (Drop Dash enabled), and delete the source files. Takes a few seconds.

### Mobile Data.rsdk (legacy)

Drop a mobile-format `Data.rsdk` (from the Android APK) into
`ports/sonic.1/` and launch. The engine loads it directly; no patching or
extraction runs. Drop Dash and Plus-roster features are **not** available
on this path (they require Origins scripts + Anniversary GameConfig).

Guidance for extracting `Data.rsdk` from a legal source is
[here](https://github.com/RSDKModding/RSDKv4-Decompilation?tab=readme-ov-file#support-the-official-release-of-sonic-1--2).

## Default Controls
| Button | Action |
|--|--|
| START | Pause / Accept |
| SELECT | Dev menu |
| D-PAD | Move |
| LEFT ANALOG | Move |
| ABXY | Jump |
| DOWN + ABXY | Spindash |

## Using mods

The port ships with the Menu Recreation mod enabled by default so the full mobile-style menu (character select, save slots, options) is available. Open the dev menu with SELECT to toggle mods or access stage select.

To add more mods, drop them into the `mods/` folder. Enable/disable from the dev menu.

### Sonic Forever (mobile data only)

The port ships a `sonicforever` binary — a custom RSDKv4 build by spec58 that's compatible with the [Sonic Forever](https://teamforeveronline.wixsite.com/home) mod — but **not** the mod itself. To use it:

1. You must be running on **mobile `Data.rsdk`** data. Origins data is not compatible with the Forever binary.
2. Download the Sonic Forever `Mod Only` release from the project site above and drop the folder into `mods/`.
3. Set `SonicForeverMod=true` under `[mods]` in `mods/modconfig.ini`.
4. Launch. The port automatically switches to the `sonicforever` binary when all three conditions are met, disables the Menu Recreation mod (Forever brings its own menu), and sets `GameType=0` in settings.ini.

Turning the flag back off (or removing mobile Data.rsdk) returns to the standard `RSDKv4` binary + Menu Recreation automatically.

## Rebuilding

See [BUILDING.md](BUILDING.md) if you want to rebuild RSDKv4 with Plus-roster characters unlocked (Amy, Knuckles & Tails, etc.).

## Thanks

- christianhaitan — the original port
- [Rubberduckycooly](https://github.com/Rubberduckycooly/Sonic-1-2-2013-Decompilation)
  for the decompilation work that makes this possible
- Leonx254 — Menu Recreation mod
- spec58 — custom RSDKv4 binary for Sonic Forever compatibility
- Testers and Devs from the PortMaster Discord
