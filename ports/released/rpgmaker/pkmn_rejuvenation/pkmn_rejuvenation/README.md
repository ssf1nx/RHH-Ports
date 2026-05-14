# Installation

Download the Windows version from https://www.rebornevo.com/rejuvdown/. Install the game (the bundle is a self-extracting `.exe`) and copy all assets from the resulting `Pokemon Rejuvenation` folder into the `pkmn_rejuvenation` port folder. Version 13.5.0 is known to work; future updates may be incompatible.

On first launch the splash GIF is automatically re-encoded at a lower framerate to reduce a startup RAM spike (this takes ~1 minute).

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

Pokémon Rejuvenation is RAM-heavy. Save often. The handheld build runs through mkxp-z.

## Runtimes

This port requires the following runtimes in `PortMaster/libs`:

- **MKXP-Z** — [mkxp-z.squashfs](https://github.com/JeodC/RHH-Ports/raw/main/runtimes/mkxp-z.squashfs)

[Pharos](https://github.com/JeodC/RHH-Ports/releases/download/ports-latest/pharos.zip) will fetch these automatically when installing the port. Otherwise download them manually from the [runtimes folder](https://github.com/JeodC/RHH-Ports/tree/main/runtimes) and drop them in `PortMaster/libs`.

## Thanks
Jan and the Rejuvenation Team for the original game  
[Dokoma](https://github.com/dokoma) for compiling mkxp-z 
JanTrueno for the upstream PortMaster Rejuvenation port this is based on  
