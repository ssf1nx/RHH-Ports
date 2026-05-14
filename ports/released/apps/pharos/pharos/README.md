<div align=center>
<img width="320" height="317" alt="image" src="https://raw.githubusercontent.com/JeodC/RHH-Ports/refs/heads/main/ports/released/apps/pharos/pharos/cover.png" />
</div>

# Pharos
Named after the Lighthouse of Alexandria, **Pharos** is a browser application designed to provide an alternative interface for installing ports and wine-arm64 wrappers. Pharos follows GitHub repository links listed in a configurable file `.sources` and presents eligible items hosted on those repositories.

<div align=center>
<img width="400" height="300" alt="pharos2" src="https://raw.githubusercontent.com/JeodC/RHH-Ports/refs/heads/main/ports/released/apps/pharos/pharos/screenshot.png" />
</div>

## How It Works

1. Pharos reads a list of repository URLs from plaintext file `.sources`.
2. It parses each repository and displays eligible items in its GUI.
4. Downloaded files are placed in `pharos/autoinstall`.
5. Pharos installs the port or wine bottle to either `roms/ports` or `roms/windows` folders.
6. Pharos updates `gamelist.xml` with `gameinfo.xml` included with the download.

> **Important:** For Pharos to parse and display repositories correctly, participating repositories must follow a **compatible file structure** and have a valid `ports.json` or `winecask.json` file.

## Security
Pharos does **not perform validation** on downloaded files. Users are responsible for ensuring that all sources are trusted and safe.

## Hosting Your Own Repository
To host a repository compatible with Pharos, ensure it adheres to the expected structure and `ports.json` or `winecask.json` format. For guidance, see the [template repository](https://github.com/JeodC/Pharos-Template).

## Runtimes

This port requires the following runtimes in `PortMaster/libs`:

- **Python 3.11** — [python_3.11.squashfs](https://github.com/JeodC/RHH-Ports/raw/main/runtimes/python_3.11.squashfs)

[Pharos](https://github.com/JeodC/RHH-Ports/releases/download/ports-latest/pharos.zip) will fetch these automatically when installing the port. Otherwise download them manually from the [runtimes folder](https://github.com/JeodC/RHH-Ports/tree/main/runtimes) and drop them in `PortMaster/libs`.

## Thanks
Pharos is a python application inspired by RomM and PortMaster. Some code is based on existing functions from those applications, hence the AGPL license.
