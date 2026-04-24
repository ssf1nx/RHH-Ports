## Installation

This port accepts data from either **Sonic Origins** (recommended) or the **mobile Sonic The Hedgehog 2** Android APK. Drop the appropriate files into `ports/sonic.2/` and launch — the port patcher handles the rest on first run.

### Origins data (recommended)

Sonic 2 shares several audio cues with Sonic 1 that Origins only ships under the S1 pack, so the Origins path requires files from **both games' packs**. Copy these from your Sonic Origins install (`image/x64/raw/` path shown for the Steam version):

| File | Source | Notes |
|--|--|--|
| `Sonic2u.rsdk` | `image/x64/raw/retro/Sonic2u.rsdk` | Game data container |
| `STH2_music.acb` | `image/x64/raw/sound/STH2_music.acb` | S2 music pack |
| `STH2_music.awb` | `image/x64/raw/sound/STH2_music.awb` | |
| `STH2_sfx.acb` | `image/x64/raw/sound/STH2_sfx.acb` | S2 SFX pack |
| `HITE_sfx.acb` | `image/x64/raw/sound/HITE_sfx.acb` | SEGA chant + menu ding |
| `STH1_music.awb` | `image/x64/raw/sound/STH1_music.awb` | Drowning + 1Up jingle |
| `STH1_sfx.acb` | `image/x64/raw/sound/STH1_sfx.acb` | Score Add + Event sting |

On first launch the patcher will:

- Extract the RSDK container to loose data
- Transcode Origins CRIWARE audio to the engine-expected `.ogg` (Global)
  / `.wav` (Stage) layout
- Pull shared cues from the STH1 packs (Drowning music, 1Up jingle,
  Score Add / Event SFX)
- Synthesize the `_F` speed-shoes music variants by resampling zone
  tracks to 1.2x tempo (Origins doesn't ship these)
- Flip the GameConfig into Anniversary mode + unlock the full 7-slot
  Plus roster (Amy, Knuckles & Tails, etc. — requires a Plus-enabled
  RSDKv4 rebuild to actually play as them; see BUILDING.md)
- Delete the source files

The full patch takes around 30 seconds depending on device.

### Mobile Data.rsdk (legacy)

Drop a mobile-format `Data.rsdk` (from the Android APK) into `ports/sonic.2/` and launch. The engine loads it directly; no patching or extraction runs. Drop Dash and Plus-roster features are **not** available on this path.

Guidance for extracting `Data.rsdk` from a legal source is [here](https://github.com/RSDKModding/RSDKv4-Decompilation?tab=readme-ov-file#support-the-official-release-of-sonic-1--2).

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

### Sonic 2 Absolute (mobile data only)

The port ships a `sonic2absolute` binary — a custom RSDKv4 build by spec58 that's compatible with the [Sonic 2 Absolute](https://teamforeveronline.wixsite.com/home/sonic-2-absolute) mod — but **not** the mod itself. To use it:

1. You must be running on **mobile `Data.rsdk`** data. Origins data is not compatible with the Absolute binary.
2. Download the Sonic 2 Absolute `Mod Only` release from the project site above and drop the folder into `mods/`.
3. Set `Sonic2Absolute=true` under `[mods]` in `mods/modconfig.ini`.
4. Launch. The port automatically switches to the `sonic2absolute` binary when all three conditions are met, disables the MenuRecreation mod (Absolute brings its own menu), and sets `GameType=0` in settings.ini.

Turning the flag back off (or removing mobile Data.rsdk) returns to the standard `RSDKv4` binary + Menu Recreation automatically.

## Rebuilding

See [BUILDING.md](BUILDING.md) if you want to rebuild RSDKv4 with Plus-roster characters unlocked (Amy, Knuckles & Tails, etc.).

## Thanks

- christianhaitan — the original port
- [Rubberduckycooly](https://github.com/Rubberduckycooly/Sonic-1-2-2013-Decompilation)
  for the decompilation work that makes this possible
- Leonx254 — Menu Recreation mod
- Testers and Devs from the PortMaster Discord
