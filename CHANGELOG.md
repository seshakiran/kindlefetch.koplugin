# Changelog

## 0.10.0 — Import into BookOrbit before opening

- Distinguish BookOrbit dashboard imports from standalone Kindle Fetch downloads.
- Stage an explicit BookOrbit import, upload once, and open only after the confirmed server book ID is persisted.
- Link the existing local copy to BookOrbit's book/file records so Open/Continue does not request a second transfer.
- Reuse known pending/completed imports, including compatible older upload records; retain uncertain jobs for review.
- Preserve standalone download prompts and the user's existing auto-upload setting.
- Add a capability check and a hash-guarded upgrade from the previous BookOrbit dashboard patch.
- Add importer, transfer-entry, completion-notification, context, and local-file linking regressions.

## 0.9.1 — Search from the BookOrbit reader dashboard

- Expose an optional in-process search handoff for the BookOrbit reader search dialog.
- Reuse the existing Z-Library-only search, download, preferences, and automatic upload behavior.
- Validate queries and remove only the current reader instance’s handoff during teardown.
- Publish a compatible BookOrbit 1.5.5 catalog patch in the companion deployment repository.

## 0.9.0 — BookOrbit uploads

- Add native BookOrbit website sign-in, rotating sessions, and library selection.
- Stream completed downloads to BookOrbit in a background subprocess; preserve local files.
- Add a persistent queue, manual existing-book uploads, content-hash deduplication, bounded safe retries, and explicit review of interrupted transfers.
- Reuse the installed BookOrbit plugin’s server address without reusing or exporting its sync key.
- Add upload/session/queue regressions and document device setup and VPN requirements.
- Record user-confirmed manual and automatic uploads on Viwoods AiPaper Mini (October 20, 2026), with Tailscale left connected, no exit node, Tailscale DNS disabled, and Kindle Fetch encrypted DNS enabled.

## 0.8.1 — Z-Library-only fork

- Restrict active source registration and saved source selections to Z-Library; label the Sites menu accordingly.
- Pin the service base URL to `https://z-library.sk` and remove mirror discovery from the active request path.
- Use bounded account-request timeouts and clearer connection errors.
- Add native DNS-over-HTTPS bootstrap, response validation, TTL caching, and temporary TCP address mapping while retaining the requested hostname and TLS configuration.
- Support encrypted DNS without curl, including the Viwoods Android networking path and native downloads.
- Retry an aborted native search once with refreshed DNS and a fresh request; avoid replaying login and file-download operations through this retry.
- Update diagnostics for the active source and native DNS support.
- Point future release updates to `seshakiran/kindlefetch.koplugin`.
- Add source-only packaging, mocked network regressions, CI, installation documentation, and a BookOrbit upload roadmap.

BookOrbit uploads remain planned. This version does not implement a BookOrbit client.
