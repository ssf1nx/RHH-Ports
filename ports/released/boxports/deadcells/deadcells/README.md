# Dead Cells - Retro Handhelds Port

## Requirements
Hashlink engine requires OpenGL 3.3 minimum. GL4ES does not support this minimum version. Since Dead Cells doesn't use geometry shaders, the launch script spoofs OpenGL 3.3 so the game runs. However!

This port is tested and verified functional for Rocknix on Retroid Pocket systems. On the RG353V, it hit a vram memory limit on loading a save file. Other devices are untested.

## Installation
You *MUST* use GOG Linux data!

The `deadcells/gamedata` folder already contains two files necessary to help the game run. Copy the following game assets to `deadcells/gamedata` to complete the setup:

```
deadcells/gamedata
│   deadcells
│   detect.hl
│   fmt.hdll
│   hlboot.dat
│   libhl.so
│   libmbedcrypto.so.1
│   libmbedtls.so.10
│   libmbedx509.so.0
│   libopenal.so.1
│   libSDL2-2.0.so.0
│   libsndio.so.6.1
│   libturbojpeg.so.0
│   libuv.so.1
│   mysql.hdll
│   openal.hdll
│   res.pak
│   ssl.hdll
│   ui.hdll
│   uv.hdll
```

DO *NOT* REPLACE THE EXISTING `sdl.hdll` FILE!!!

DLC content should work.

## Thanks
Motion Twin -- The game  
Apprentice-Alchemist  -- The subtle hashlink sdl change that allows dynamic loading libGL  
ptitseb -- Box64  