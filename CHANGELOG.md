# Changelog

## 0.9.0 — BookOrbit uploads

- Add native BookOrbit website sign-in, rotating sessions, and library selection.
- Stream completed downloads to BookOrbit in a background subprocess; preserve local files.
- Add a persistent queue, manual existing-book uploads, content-hash deduplication, bounded safe retries, and explicit review of interrupted transfers.
- Reuse the installed BookOrbit plugin’s server address without reusing or exporting its sync key.
- Add upload/session/queue regressions and document device setup and VPN requirements.

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
