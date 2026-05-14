# Installation

Download the legacy Windows version from https://www.rebornevo.com/pr/download/. Install the game (the bundle is a self-extracting `.exe`) and copy all assets from the resulting `Pokemon Reborn` folder into the `pkmn_reborn` port folder. Version 19.16 or 19.17 is required.

# Controls

Buttons follow Xbox-style labeling: **A** = bottom, **B** = right, **X** = top, **Y** = left.

| Button | Action |
|--------|--------|
| D-Pad | Move |
| A | Use / Interact |
| B | Back / Menu |
| X | Run (hold) |
| Y | Registered Item / Quicksave |
| Start | Open Menu |
| Select + Start | Quit |
| L1 | Save / Sort Bag |
| R1 | Speed Up (dialogue) |
| L2 | Scroll Up (Pokédex etc.) |
| R2 | Scroll Down |

# Notes

Pokémon Reborn is RAM-heavy. Save often. The handheld build runs through mkxp-z and includes a compatibility shim for engine API differences between the upstream mkxp fork and modern mkxp-z.

## Runtimes

This port requires the following runtimes in `PortMaster/libs`:

- **MKXP-Z** — [mkxp-z.squashfs](https://github.com/JeodC/RHH-Ports/raw/main/runtimes/mkxp-z.squashfs)

[Pharos](https://github.com/JeodC/RHH-Ports/releases/download/ports-latest/pharos.zip) will fetch these automatically when installing the port. Otherwise download them manually from the [runtimes folder](https://github.com/JeodC/RHH-Ports/tree/main/runtimes) and drop them in `PortMaster/libs`.

## Thanks
Reborn Team for the original game  
[Dokoma](https://github.com/dokoma) for compiling mkxp-z  
JanTrueno for the upstream PortMaster Reborn port this is based on  
