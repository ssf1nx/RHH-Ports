## Installation
Add your game data from your Steam or Itch.io installation to `ports/iosas/assets`. First-time run will handle sorting data.

## Default Gameplay Controls
| Button | Action |
|--|--|
|START|Menus|
|SELECT|Map|
|D-PAD / Analog|Move|
|L1|Undo|
|R1|Reset room|

## Config
The patch enables `saves/config.ini`, which has some performance options that affect certain rooms in the game. Testing found that `FrameSkip=40` works pretty well for the H700 chip. For no stuttering at all, you can set `IdolSFX=0` to turn off the special effect that bogs down the cpu.

## Importing / Exporting Save Data
Steam saves are located at `\AppData\Local\IslesOfSeaAndSky` on Windows. Copy `save_v1_000.dat` or similar to `ports/iosas/saves` to use it. To export save data to your Steam or Itch.io install, do the reverse.

## Thanks
Cicada Games -- The game and [press kit materials](https://islesofseaandsky.com/press-kit) used to create the splash screen  
Cyril "kotzebuedog" Delétré -- The phenomenal audio patch that makes this port possible  
JohnnyOnFlame -- GMLoaderNext  
Jeod, Ganimoth -- Port creator and maintainer  
Testers and Devs from the PortMaster Discord  
