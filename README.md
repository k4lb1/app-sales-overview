# App Sales Overview

All your apps at a glance, on your iPhone: downloads, proceeds, how often your apps are seen in the App Store,
what's waiting for review, and new reviews. Read straight from App Store Connect with your own API key.

Apple is retiring Sales and Trends in App Store Connect, and its new Analytics shows one app at a time.
App Sales Overview puts every app of your account on one screen again.

## What it shows

- **Overview:** downloads and proceeds of yesterday, the last 7 or 30 days, over all apps and per app, with the
  countries they come from. Proceeds are converted to one currency with the European Central Bank's daily rates.
- **Store:** the discovery funnel from Apple's analytics (impressions, product page views, downloads, conversion,
  and where people found the app), every version waiting at Apple, and the newest reviews of all apps.
- **Explore:** a chart you put together yourself: downloads, proceeds, updates, re-downloads, refunds, impressions
  or page views over 7 to 180 days, split by app, country, device or store source, exported as CSV. With the average
  day per weekday, and per country what a download brings in.
- **Releases** in the exports: on the day a version first shows up in Apple's reports, its number is in the Release column.
- **Monthly statement:** a month's proceeds per app, country and currency, and Apple's financial report, as PDF and CSV.
- **Notifications** for review status, new reviews, yesterday's numbers and download milestones.
- **Widgets** for the Home Screen and the Lock Screen. They fetch on their own, so yesterday's numbers are there
  in the morning without opening the app.

## Your key stays with you

There is no server. The app talks to Apple directly:

- Your API key is stored in the iPhone's Keychain, on this device only (not in iCloud Keychain, not in backups).
  It is sent nowhere but to `api.appstoreconnect.apple.com`.
- Reports are kept on the device, in the app's own container.
- The only other requests are public files without anything about you: the ECB's exchange rates and the
  App Store icons of your apps (`itunes.apple.com/lookup`).
- No analytics, no tracking, no account.

This repository is the whole app's source, so you can check every line of that.

## Setting it up

1. In App Store Connect, open **Users and Access › Integrations › Team Keys** and generate a key.
   The **Admin** role is needed for the store analytics (the app asks Apple to produce them once);
   **Finance** is enough for downloads and proceeds.
2. Download the key (`AuthKey_<KeyID>.p8`, possible only once) and put it in the Files app.
3. Note the **Issuer ID** (above the list of keys) and your **vendor number** (Payments and Financial Reports, top left).
4. Open the app, enter both, choose the `.p8` file, and tap **Connect**.

Apple publishes each day's sales report the next morning (Pacific time) and the store analytics a day or two later.
The first analytics arrive one to two days after the first launch.

## Building it yourself

Requirements: Xcode 27, iOS 26, an Apple developer account.

```sh
open AppSales.xcodeproj
```

Set your own team and bundle identifiers in the project (the app, the widget and the App Group
`group.<your bundle ID>`), then build the `AppSales` scheme.

The App Store Connect client lives in `Sources/ASCKit` and is also a Swift package. `asc-peek` is a small
command-line tool on top of it that prints what Apple returns for your key:

```sh
mkdir -p ~/.appstoreconnect
# config.json: {"issuer": "…", "keyID": "…", "vendorNumber": "…"}, next to AuthKey_<keyID>.p8
swift run asc-peek            # apps and their version states
swift run asc-peek sales      # yesterday's sales report
swift run asc-peek discovery  # store analytics per app
```

## Layout

| Folder | What's in it |
|---|---|
| `Sources/ASCKit` | App Store Connect API: token, apps and versions, sales reports, analytics reports, reviews |
| `Shared` | Code for the app and the widget: Keychain, report cache, figures, exchange rates, theme |
| `App` | The iPhone app |
| `Widget` | Home Screen and Lock Screen widgets |
| `Sources/asc-peek` | Command-line tool for trying the API |

## License

The source is available under the [PolyForm Noncommercial License 1.0.0](LICENSE): you may read it, check it,
build the app for yourself and change it for any noncommercial purpose. Selling it or using it commercially is not
permitted. The name "App Sales Overview" and the app icon are not licensed: please use your own if you share a
version you built.

Made by [0xdeploy.studio](https://0xdeploy.studio).
