# League of Legends Fast Multi-Threaded Updater & Downloader

A high-performance command-line patcher and clean installer for **League of Legends**, bypassing client download throttling, dead IPv6 routing timeouts, and slow disk verification by streaming directly from Riot's Cloudflare CDN over 16 parallel threads.

---

## Features

- **Blazing Fast (16 Threads):** Directly streams game chunks from Riot's high-speed Cloudflare CDN (`riotcdn.net`), fully saturating modern internet connections (200+ Mbps).
- **Zero-Stall Fast Patching:** Compares local files against the manifest in under 0.2 seconds and updates **only the modified files** (e.g. ~35 files instead of 200+), eliminating 15–20 minutes of single-threaded disk chunk hashing.
- **Auto-Patch Detection:** Pings Riot's official Sieve API (`sieve.services.riotcdn.net`) to automatically fetch new patch manifests (Patch 16.20, 16.21, etc.) whenever Riot pushes an update.
- **Multi-Region Support:** Built-in server selector for `SG2` (Default), `NA1`, `EUW1`, `EUN1`, `KR`, `JP1`, `TW2`, `VN2`, `OC1`, `BR1`, or custom server codes.
- **Fresh / Clean Install Mode:** Allows downloading the entire ~25 GB game client from scratch for new PCs or fresh installations without needing the Riot Client installed first.
- **Real-Time Speed & Progress:** Displays live network throughput in `MB/s`, animated progress bar, percentage, and current file name.
- **100% Portable:** Uses relative paths (`%~dp0`, `$PSScriptRoot`). Can be copied to a USB drive or shared with friends out of the box.

---

## How to Use

1. Download or clone this repository.
2. Double-click **`Update_LoL.bat`**.
3. Select an option from the menu:
   - **`[1] Fast Patch / Update Existing Game`** *(Default: Press Enter)* — Automatically detects outdated files and patches them at maximum speed.
   - **`[2] Full / Clean Game Download`** — Downloads the full game client for new users.
   - **`[3] Change Server Region`** — Switch between SG2, NA, EUW, KR, etc.
   - **`[4] Change Installation Directory`** — Custom game folder path.
   - **`[5] Exit`**

---

## Requirements

- **Operating System:** Windows 10 / 11 (64-bit)
- **PowerShell:** Version 5.1 or later (pre-installed on Windows)
- **Permissions:** Standard user privileges (Admin only required if your Riot Games folder is in a protected system directory).

---

## Acknowledgements

- Powered by [Morilli/ManifestDownloader](https://github.com/Morilli/ManifestDownloader) for Riot Games manifest parsing and chunk extraction.
- Game assets and manifests are property of © Riot Games.
