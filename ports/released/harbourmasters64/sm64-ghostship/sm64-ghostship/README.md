## Information
Ghostship binaries were built from GitHub Actions at the [HM64 Autobuild Factory](https://github.com/JeodC/hm64-builder).

## Installation
You must generate your `sm64.o2r` file with a rom that has one of the following SHAs:

```
9bef1128717f958171a4afac3ed78ee2bb4e86ce - N64 US
8a20a5c83d6ceb0f0506cfc9fa20d8f438cafe51 - N64 JP
```

You can verify your rom at https://www.romhacking.net/hash.

Legally obtain your rom and place it in `ports/ghostship/baseroms`, then start the port. Texture pack files can be added to the `ports/ghostship/mods` folder.

Logs are recorded automatically as `ports/ghostship/log.txt`. Please provide a log if you report an issue. HarbourMasters is not affiliated with PortMaster or RHH-Ports and this distribution is not officially supported by them. *Please report an issue to the RHH-Ports repository before going to HarbourMasters!*

## Graphics Adjustments
You can open `ghostship.cfg.json` in a text editor and modify the values as you wish. If you mess up the syntax, the game will regenerate this file and your settings will be reverted to default. Please create a backup before modification.

## Menu Navigation
Ghostship has built-in controller navigation for the imgui menu. Press `SELECT` to open the menu and use the `D-PAD` to choose a submenu, then press `A` to switch focus to it. Press `B` to back out of a submenu.

## Default Gameplay Controls
The port uses SDL controller mapping and controls can be remapped from the menu bar.

## Suggested Mods
Find mods at the [Gamebanana page](https://gamebanana.com/mods/games/24131), and [SM64-Reloaded](https://github.com/GhostlyDark/SM64-Reloaded-GS).

Add the mod packs to `ghostship/mods`, and either have the line `"gAltAssets": 1,` in your json or assign `TAB` to a button in the `soh2.gptk` file (default R3).

## Thanks
- Nintendo for the game  
- HarbourMasters for the native pc port  




