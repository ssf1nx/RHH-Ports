# Dusklight

This wrapper is made for linux handhelds to run Dusklight, an unofficial PC port of *The Legend of Zelda: Twilight Princess*. You must provide your own legally-obtained game files.

> Originally released upstream as "Dusk"; renamed to "Dusklight" in May 2026. Existing player saves migrate automatically on first launch of v1.0.2+.

## Hardware Requirements

Dusklight is built on the **Aurora** framework, which only ships **Vulkan, Metal, and D3D12** backends. **There is no OpenGL or OpenGL ES backend.** Your handheld must have a working Vulkan driver:

- **Likely to work:** RK3588 devices with Mali G610 (Panfork/Panfrost+Vulkan), Snapdragon devices with Adreno (Turnip), Apple Silicon (MoltenVK).
- **Will not work:** Older Mali G31/G52/Bifrost devices that only expose OpenGL ES, S922X devices using stock Mali drivers without Vulkan, anything restricted to GLES via `gl4es`/`box86` translation.

If `vulkaninfo` on your device fails or reports zero physical devices, this port cannot run.

## Installation

Drop your own legally-obtained Twilight Princess GameCube USA disc image directly into the `ports/zelda-dusklight/` folder. The launch script will auto-detect the first match.

## Thanks
Nintendo - The original game  
TwilitRealm - The Dusklight decomp/reimplementation  
encounter - The Aurora framework  
