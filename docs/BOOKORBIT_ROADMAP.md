# BookOrbit integration

Version **0.9.0** implements a native BookOrbit client and persistent upload queue. Device sign-in and a destination library are required before files can be sent. Network/account availability still determines whether a live transfer succeeds.

## Dashboard search entry point

Kindle Fetch **0.9.1** adds an in-process search handoff consumed by an optional BookOrbit reader plugin **1.5.5** patch. The dashboard search dialog keeps BookOrbit library search and adds **Search Z-Library**, using Kindle Fetch’s existing account, filters, native networking, direct download, and upload queue. Closing the search returns to the underlying catalog. This changes the reader UI; it does not change BookOrbit web search or server APIs. See the [patch guide](https://github.com/seshakiran/bookorbit-reading-stack/blob/main/docs/PLUGINS.md#search-z-library-from-the-bookorbit-dashboard).

The originating reader now has the 0.9.1 handoff and compatible catalog patch installed; all 54 deployed files were verified by readback. The dashboard entry point still awaits an on-device user test after restarting KOReader.

## Implemented

- Reuse the server URL saved by the installed BookOrbit plugin; keep its sync credentials separate.
- Sign in using the BookOrbit website account with `POST /api/v1/auth/login`, `clientKind: native`, and refresh rotating native sessions through `/auth/refresh`.
- List book libraries through `GET /api/v1/libraries`.
- Stream a multipart `file` to `POST /api/v1/libraries/:id/upload` with the native bearer token. No curl dependency, credential redirects, or whole-book buffering.
- Queue only after a downloaded book passes the existing checks and is renamed to its final local path.
- Offer a local file browser for manually sending existing books.
- Persist destination/account binding, queue state, content hash, and returned book ID. Keep originals on the reader.
- Skip repeated content already recorded as uploaded to the same account/library on this reader.
- Retry safe preflight failures up to three times with backoff. Hold interrupted/ambiguous file POSTs until the user checks BookOrbit and explicitly retries.
- Resume pending work after startup, wake, and network reconnection. Treat jobs interrupted by restart as uncertain.

The direct upload API returns a book record before all asynchronous metadata work finishes. The plugin reports “Sent” after a confirmed book ID; it does not claim all metadata processing has finished.

## Authentication and deployment

BookOrbit's KOReader sync headers (`x-auth-user` / `x-auth-key`) are not accepted by the library-upload API. The upload client uses a separate native web-account session. Passwords remain transient; access and refresh tokens stay in the private device settings file. No tokens, personal server addresses, device reports, or books belong in this public repository.

A private Tailscale deployment needs Tailscale active during upload. The originating reader now accesses both services with Tailscale left connected: Exit node **None**, **Use Tailscale DNS** off on the reader, and Kindle Fetch **Encrypted DNS** enabled. The saved BookOrbit URL uses a numeric tailnet address. Keep KOReader included in Tailscale; both plugins run in that application. See the [working setup](../README.md#working-tailscale-setup), including hostname and retry limits.

HTTPS and private IPv4 HTTP deployments are supported. No server patch or watched-folder bridge is required for the supported API.

## Validation

Mocked tests cover native login and refresh rotation, response limits, origin restrictions, multipart framing/length, timeout restoration, offline retention, hash-based duplicate suppression, destination binding, bounded preflight retries, ambiguous POST handling, and failed persistence blocking transfers. CI runs these alongside Z-Library regressions on Lua 5.1 and 5.4.

On **October 20, 2026**, the user confirmed both a manual existing-book upload and a subsequent automatic upload after a new download on the originating **Viwoods AiPaper Mini**. After applying the Tailscale settings above, the downloaded book appeared in BookOrbit without a manual upload action or VPN toggle. The deployed plugin was version **0.9.0**; all 52 installed package files had been read back and matched the source package byte for byte.

This confirms the original device/server workflow, not fresh-install compatibility across all devices. A browser login alone does not provision the reader's separate upload session. Metadata completion, long-duration transfers, and every failure/recovery scenario have not been established by this live test.

## Remaining improvements

- [ ] Resumable chunk/session uploads for very large books, once compatibility with the deployed server is verified.
- [ ] Server-wide duplicate lookup and reconciliation for ambiguous transfers.
- [ ] Per-file byte progress and a detailed queue history screen.
- [ ] Explicit import-job/metadata-completion tracking if the server exposes a suitable API.
- [ ] OIDC-only account pairing where password login is disabled.

Companion deployment: [bookorbit-reading-stack](https://github.com/seshakiran/bookorbit-reading-stack). Protocol source: BookOrbit's [upload controller](https://github.com/bookorbit/bookorbit/blob/main/server/src/modules/upload/upload.controller.ts), [authentication controller](https://github.com/bookorbit/bookorbit/blob/main/server/src/modules/auth/auth.controller.ts), and [authentication service](https://github.com/bookorbit/bookorbit/blob/main/server/src/modules/auth/auth.service.ts).
