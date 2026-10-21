<div align="center">

# Kindle Fetch

**Find a book. Bring it to your reader. Keep reading.**

A Z-Library-only plugin for KOReader, with direct downloads and native networking fixes for Android readers.

[![Checks](https://github.com/seshakiran/kindlefetch.koplugin/actions/workflows/checks.yml/badge.svg)](https://github.com/seshakiran/kindlefetch.koplugin/actions/workflows/checks.yml)
![Version](https://img.shields.io/badge/version-0.8.1-blue)
![KOReader](https://img.shields.io/badge/reader-KOReader-333333)
[![License: MIT](https://img.shields.io/badge/license-MIT-green)](LICENSE)

[Install](#install) · [Use](#use) · [Troubleshooting](#troubleshooting) · [BookOrbit roadmap](docs/BOOKORBIT_ROADMAP.md)

</div>

## What works today

| Feature | Current behavior |
| --- | --- |
| One source | Searches **[z-library.sk](https://z-library.sk/)**. The Sites menu explicitly says **Z-Library**. |
| Account access | Sign in from the plugin and use the account's download access. |
| Search | Search by text, including author names; apply available language and file-format filters. |
| Direct downloads | Fetch a selected book's download link and save the file to the configured reader folder. |
| Native networking | DNS-over-HTTPS support works through KOReader's HTTP client, including devices without `curl`. |
| Connection recovery | A native search interrupted by a connection-abort error gets one retry with refreshed DNS and a fresh request. |
| Diagnostics | Save a report to help investigate DNS, HTTP-client, and connection failures. |
| BookOrbit uploads | **Planned.** No upload or website integration is implemented yet. |

Other providers are no longer registered or offered in search. Some unused provider modules remain from upstream; they are not active sources. Old saved “All” selections resolve to Z-Library only.

```mermaid
flowchart LR
    A[Search in KOReader] --> B[Z-Library]
    B --> C[Download to reader]
    C --> D[Read in KOReader]
    C -. Planned: authenticated upload .-> E[Your BookOrbit website]
```

## Install

Requires an existing KOReader installation and an internet connection. This branch was developed and deployed on a **Viwoods AiPaper Mini running Android**. Other KOReader devices have not been verified with this fork.

1. Clone this repository and build the source-only installation package:

   ```sh
   git clone https://github.com/seshakiran/kindlefetch.koplugin.git
   cd kindlefetch.koplugin
   python3 scripts/package.py
   ```

2. Extract `dist/kindlefetch.koplugin.zip`. Copy its `kindlefetch.koplugin` folder into your device's `koreader/plugins/` directory.
3. Confirm the resulting path is `koreader/plugins/kindlefetch.koplugin/main.lua`, with no extra enclosing folder.
4. Fully restart KOReader, then open **Kindle Fetch** from its menu.

**Transferring with OpenMTP:** wake and unlock the reader, connect USB, and explicitly select **File Transfer / MTP** on the device. Refresh OpenMTP, copy the plugin folder, and keep the reader awake until the transfer finishes. Quit KOReader before replacing its plugin files and restart afterward.

The plugin updater now points to this repository. It requires a GitHub Release tagged `v<version>` with an asset named `kindlefetch.koplugin.zip`; ordinary source commits do not become in-app updates. Build from source until a release is published.

## Use

1. Connect the reader to Wi-Fi and open Kindle Fetch.
2. Sign in to Z-Library through the plugin.
3. Enter a title or author name in the search box. Author names use the normal text search; there is no separate author-only filter.
4. Choose a result and download an available format into your configured download folder.
5. Open the downloaded file in KOReader.

Account limits and service availability still apply. Account identifiers and the session key are saved in the reader's local settings; keep device settings private. The login password is not persisted by the account code.

## Troubleshooting

| Symptom | What to check |
| --- | --- |
| “Could not resolve z-library.sk” | Check Wi-Fi and try **Encrypted DNS** in Kindle Fetch settings. Z-Library requests also enable DNS fallback. |
| “curl is not found” | Native HTTP and encrypted DNS support do not require curl. Confirm that this version is installed and KOReader was restarted. |
| TLS/SSL connection failed | Check the device clock, network, and VPN routing; try the same site in the reader's browser. Save diagnostics if it persists. |
| “Software caused connection abort” | Native search retries once. If both attempts fail, check network reachability and save diagnostics. |
| Works with Tailscale off | Compare the reader's DNS and routing with Tailscale enabled and disabled. Turning it off helped during development, but a search abort also occurred with it off. |
| OpenMTP cannot open storage | Unlock the reader, reselect USB File Transfer, reconnect, and refresh OpenMTP. |

Use **Kindle Fetch → Diagnostics → Save** after reproducing a problem. The report is saved as `kindlefetch-diagnostics.txt` in KOReader's data directory. Review reports before sharing; do not publish credentials, session keys, or personal search history.

Network recovery is bounded: the connection-abort retry applies to search, not login or file downloads. DNS fallback preserves the requested hostname and existing TLS configuration. It does not make an unreachable service reachable on every network.

## Development

```sh
# Lua and luac must be installed.
sh scripts/check.sh

# Build the installable ZIP; no accounts, diagnostics, or books are packaged.
python3 scripts/package.py
```

The regression suite uses mocked network and account dependencies. It covers native DNS bootstrap, DNS response validation and caching, timeout restoration, bounded search-abort recovery, optional curl DNS fallback, and the fixed Z-Library source/account behavior. CI runs syntax and regression checks on **Lua 5.1 and 5.4** and builds the plugin package.

Local live HTTP checks were also exercised during development. Those checks and the device deployment do not guarantee future Z-Library availability or API compatibility. See [CHANGELOG.md](CHANGELOG.md) for this fork's changes.

## Next: BookOrbit

The next milestone is sending downloaded books to **BookOrbit on your personal website**, with visible upload status and duplicate protection.

- [x] Restrict active search to Z-Library.
- [x] Add native encrypted DNS and bounded search recovery.
- [x] Prepare source packaging and regression checks.
- [ ] Verify the deployed BookOrbit version, authentication, and supported import mechanism.
- [ ] Add a manual **Send to BookOrbit** action for a completed download.
- [ ] Persist an upload queue, handle failures, and prevent duplicate imports.
- [ ] Offer optional automatic upload after manual uploads are reliable.

The [implementation roadmap](docs/BOOKORBIT_ROADMAP.md) records the proposed flow, open decisions, and acceptance checks. The companion deployment project is [bookorbit-reading-stack](https://github.com/seshakiran/bookorbit-reading-stack).

## Credits & license

This fork builds on [william-spongberg/KindleFetch.koplugin](https://github.com/william-spongberg/KindleFetch.koplugin), itself derived from [justrals/KindleFetch](https://github.com/justrals/KindleFetch), and runs inside [KOReader](https://github.com/koreader/koreader).

Distributed under the [MIT license](LICENSE), preserving the upstream copyright notice.
