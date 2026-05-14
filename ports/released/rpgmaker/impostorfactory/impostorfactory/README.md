# Installation

Copy the entire contents of your Steam install directory into the `impostorfactory` folder. On Windows that's typically:

```
SteamLibrary/steamapps/common/Impostor Factory/Impostor Factory/*
```

The Windows binaries (`ImpostorFactory*.exe`, `steam_api*.dll`, `steamshim_*.exe`) are unused but harmless. The launcher only needs:

- `Game.rgssad`
- `Game.ini`
- `Audio/`
- `Fonts/`
- `preload/`

# Controls

| Button | Action |
|--------|--------|
| D-Pad / Left Stick | Move cursor |
| Right Stick | Mouse (WASD emulation) |
| A / Start | Confirm |
| B / Select | Cancel |
| Select + Start | Quit |

# Saves

Saves persist under `impostorfactory/config/freebirdgames/impostorfactory/Saves/` on the SD card.

## Runtimes

This port requires the following runtimes in `PortMaster/libs`:

- **MKXP-Z** — [mkxp-z.squashfs](https://github.com/JeodC/RHH-Ports/raw/main/runtimes/mkxp-z.squashfs)

[Pharos](https://github.com/JeodC/RHH-Ports/releases/download/ports-latest/pharos.zip) will fetch these automatically when installing the port. Otherwise download them manually from the [runtimes folder](https://github.com/JeodC/RHH-Ports/tree/main/runtimes) and drop them in `PortMaster/libs`.

## Thanks
Freebird Games for the original game  
[Dokoma](https://github.com/dokoma) for compiling mkxp-z 
