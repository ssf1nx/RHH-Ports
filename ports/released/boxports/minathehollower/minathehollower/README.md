## Installation
Add your game assets to `minathehollower/data`. If you have a GOG installer .sh file, copy it to `minathehollower/data` and a first-run will unpack the assets for you.

If using Steam, you can get the Linux version from https://steamdb.info/app/1875580/depots/ where you will need to download two:

- https://steamdb.info/depot/1875581 (this is also on Windows, the data/*.pak files)
- https://steamdb.info/depot/1875583/ (the Linux launcher and specific Linux files)

## Requirements
Mina the Hollower is a **Vulkan-only** game. Your device needs a working Vulkan driver and a native X11/Xwayland display.

## Notes on graphics flags
Mina runs through Box64 against the device's native Vulkan driver. On Adreno **6xx** GPUs (e.g. the Retroid Pocket Mini's Adreno 650) the driver's default tiled rendering path misbehaves under Box64, so the launcher forces a more conservative Mesa/Turnip path via:

```bash
export TU_DEBUG=sysmem,nolrz,flushall
```

What each flag fixes:
- **sysmem** — renders straight to system memory instead of the GMEM tile path. Without it the screen goes black on level load (a crash in `vkCmdPipelineBarrier`).
- **nolrz** — disables low-resolution Z. Without it the GPU faults during gameplay (kernel logs `a6xx_irq … hangcheck recover`), which shows up as the game freezing a few seconds after you start moving.
- **flushall** — forces full cache flushes, clearing the remaining intermittent GPU faults.

If you're tuning for a different device, edit that line in `Mina the Hollower.sh`:
- **Still freezing / faulting?** Add `noubwc` and/or `syncdraw`, e.g. `TU_DEBUG=sysmem,nolrz,flushall,noubwc`.
- **On a stronger GPU (Adreno 7xx / a740 class)** the default tiled path works fine — you can drop some or all of these flags for better performance, or remove the `export TU_DEBUG` line entirely.
- To check whether the GPU is still faulting on your device, run `dmesg | grep -c hangcheck` after a play session — if the count keeps climbing, add more flags.

## Thanks
- **Yacht Club Games** — for *Mina the Hollower* itself  
- **ptitSeb** — [Box64](https://github.com/ptitSeb/box64)  
- **Gabriel Huber (Yepoleb)** — [gogextract](https://github.com/Yepoleb/gogextract), used to unpack the GOG/Humble installer on-device.  
