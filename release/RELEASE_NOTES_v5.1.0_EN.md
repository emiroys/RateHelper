# RateHelper v5.1.0

*(20 October 2026)*

## Highlights

- **ORLEN fuel hub:** a new hub with **30 ORLEN stations in Kraków**, **PB95 and LPG** prices, driver price submissions, **Google Maps / Waze** navigation and fuel receipts. Sort the list by **cheapest** or **nearest**.
- **Notification-shade controls:** optional **Reject +1** and **Accept +1** buttons plus the live acceptance rate in the overlay notification. You can also enable **shade-only mode** to hide the floating pill while the counter keeps working from the shade and the steering wheel.
- **Backup & restore:** export settings, counters, weekly archive and earnings to a local JSON file, with a preview before restoring, SHA-256 integrity checking and a crash-recovery journal. **The exported file is not encrypted** — treat it as sensitive data.
- **New five-step setup wizard:** welcome, overlay permission, battery reliability, optional features and a summary. **Turkish / Polish / English** can be selected from the first screen.
- **In-app bug reporting:** describe a problem and optionally attach a screenshot, device diagnostics and error logs. The description is sanitized; logs are off by default.
- **One-time pricing survey:** after updating (or after the wizard on a fresh install) the app asks three short questions about RateHelper's future. Answers are anonymous and submitted once; if the phone is offline they are stored locally and sent later. **The app stays free — the survey starts no subscription or payment.**
- **Reliability:** overlay-to-home counter sync, safer persistence of changes, weekly archive data (goal and thresholds stored per week, duplicate resets merged), earnings calculations and post-restart data recovery.
- **Settings:** grouped cards (driving & counters, pill, preferences, system & support), a **Contact developer** row, and **Check for updates** / **Setup guide** moved there.

## ORLEN fuel hub in detail

The **Fuel** button on the home screen opens the hub:

- **Stations:** 30 verified ORLEN stations inside Kraków city limits. Distance is calculated only when you pick the **Nearest** sort and grant location permission.
- **Prices:** PB95/LPG prices come from driver submissions approved by the maintainer and are fetched from a lightweight Cloudflare backend. Without a configured `ORLEN_API_URL` the stations, sorting, navigation and receipts still work; only remote prices and price submission are disabled.
- **Submitting a price:** pick a station and fuel, enter the price; it goes to the maintainer for approval and becomes public after it is accepted.
- **Navigation:** the directions button opens Google Maps or Waze.
- **Receipts:** the second tab records a fuel amount and can split it between co-drivers; receipts feed into the weekly earnings sheet.

> Not every station necessarily sells LPG. The data model supports an LPG price where the station sells it; a missing price does not automatically mean the station has no LPG.

## About the backup

- **Export:** Settings → **Back up data**. Store the JSON file somewhere safe.
- **Restore:** Settings → **Restore from backup**. A preview (version, counter week, entry count) is shown before you confirm.
- **Not encrypted:** anyone holding the file can read it. Do not send it over public channels.
- **Recovery:** if the app is killed during a restore, the next launch finishes it from the recovery journal.

## Survey and privacy

- The survey has **three questions** and cannot be skipped; it is shown **once per installation**.
- Answers contain no name, phone, email, GPS, trips or earnings. They carry only a random installation id, the survey version and the three selected answers.
- With no connection the answer is stored on the device and sent when the app is next in the foreground.
- Most driving and financial data stays on the phone. Only **fuel price submissions**, **bug reports** and **survey answers** go to the Cloudflare backend, and only when you use those features. A screenshot or description attached to a bug report may contain personal information; attach it deliberately.
- The app creates no account and uses no advertising identifiers or third-party analytics.

## Unchanged (not new in this release)

The floating overlay, basic counters and acceptance percentage, the 2000-trip counter, weekly goals and archive, the event radar, PDF export, the three-language UI (with device-language detection on first launch) and the GitHub update mechanism all continue to work as before.
