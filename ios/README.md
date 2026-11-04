# Find Me! — iOS app

Native SwiftUI app (iOS 17+, Swift 6 language mode) for live treasure hunts. Vietnamese is the
source language and English is the second language. One app covers both roles: you can host one hunt
and play in another.

All game rules live in the Go server (`server/`, [FindMe-Go](https://github.com/t0dida00/FindMe-Go)).
The app only:
- calls the server's `/v1/...` endpoints through `GoAPI` (`Core/GameAPI.swift`, `Core/HostAPI.swift`),
  with the Supabase access token,
- signs in with Supabase Auth (the only direct Supabase use),
- uploads and shows photos through Storage URLs the server signs (`/v1/uploads`, `/v1/file-url`),
- follows the game's Server-Sent Events stream (`/v1/games/{id}/stream`) and refetches state on each
  event, on `resync`, when the app returns to the foreground and when the network reconnects.

The player's GPS is never sent to the server. The device location is only shown on the journey map,
and permission is requested only when that map opens.

## Requirements

- Xcode 16+ (tested with Xcode 27.2 / Swift 6.4)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) 2.46+ (`brew install xcodegen`)
- A Supabase project with every migration applied (Auth + Storage), and the Go server running
  (`server/scripts/dev.sh` on your Mac for development)

SPM dependency: `supabase-swift` pinned to exactly **2.55.6**.

## 1. Secrets and signing

```sh
cd ios
cp Config/Secrets.example.xcconfig Config/Secrets.xcconfig   # gitignored
```

Edit `Config/Secrets.xcconfig`:

```xcconfig
// "//" starts a comment in xcconfig files, so put $() between the slashes:
SUPABASE_URL = https:/$()/YOUR-PROJECT-REF.supabase.co
SUPABASE_ANON_KEY = eyJ...            // anon / publishable key (never the service_role key)
GO_API_URL = http:/$()/Your-Mac-Name.local:8080   // the game server (scutil --get LocalHostName)

DEVELOPMENT_TEAM = ABCDE12345
PRODUCT_BUNDLE_IDENTIFIER = com.findme.app
FREE_TEAM = NO
```

`Config/App.xcconfig` holds the defaults and includes `Secrets.xcconfig` last, so your values win.
The values are exposed to the app through the Info.plist keys `SUPABASE_URL`, `SUPABASE_ANON_KEY`,
`GO_API_URL` and `FINDME_FREE_TEAM`. If one is missing, the app shows a "Chưa cấu hình máy chủ" screen
instead of crashing.

### Paid Apple Developer Program (full setup)

With `FREE_TEAM = NO`, the target signs with `FindMe/Resources/FindMe.entitlements`, which contains
`aps-environment = development` and Sign in with Apple. Enable the **Push Notifications** and
**Sign in with Apple** capabilities for your App ID in the developer portal.

### Free Personal Team (install on your own iPhone)

A free Apple ID team cannot sign Push Notifications or Sign in with Apple. Set:

```xcconfig
DEVELOPMENT_TEAM = ABCDE12345
PRODUCT_BUNDLE_IDENTIFIER = com.yourname.findme   // must be globally unique, not com.findme.app
FREE_TEAM = YES
```

With `FREE_TEAM = YES`:
- the build uses `FindMe/Resources/FindMe-FreeTeam.entitlements` (an empty file), and
- at runtime the app hides the Sign in with Apple button and skips APNs registration.

Google sign-in and email OTP work as usual.

Steps:
1. `xcodegen generate`, then `open FindMe.xcodeproj`.
2. Plug in the iPhone and select it as the run destination. On iOS 16+, enable
   **Settings → Privacy & Security → Developer Mode** on the phone.
3. Press Run (⌘R). Xcode creates the free provisioning profile automatically.
4. The first time, trust the developer on the phone:
   **Settings → General → VPN & Device Management → your Apple ID → Trust**.
5. After the first install, `bash ios/scripts/install-device.sh` rebuilds, reinstalls and launches the
   app on the paired iPhone without opening Xcode.
6. Free-team builds expire after 7 days, so reinstall (Xcode or the script above). A free team can have at
   most 3 apps installed this way.

## 2. Supabase dashboard setup

**Auth → URL Configuration → Redirect URLs**: add `findme://login-callback`.

**Auth → Providers**
- **Apple** (native sign-in through `signInWithIdToken` with a nonce): enable it and add your bundle id
  (for example `com.findme.app`) to *Client IDs*. You don't need a Services ID or secret for native-only use.
- **Google** (`signInWithOAuth` + `ASWebAuthenticationSession`): enable it with a Google Cloud *Web*
  OAuth client ID and secret. The authorized redirect URI in Google Cloud is
  `https://<ref>.supabase.co/auth/v1/callback`. The app returns through `findme://login-callback`.
- **Email**: enable it for development OTP sign-in. Make sure the email template contains the
  `{{ .Token }}` code, because the app asks the user to type the 6-digit code.

**Realtime** comes from the Go server (Server-Sent Events), not Supabase Realtime.

**Storage**: the migrations create the private buckets `proofs` and `hint-media` and the public bucket
`avatars`. There are no Storage policies: the server decides who may upload or see a photo and signs
the URL (it needs `SUPABASE_SERVICE_ROLE_KEY` in `server/.env`).

## 3. Push notifications (APNs)

The app asks for notification permission when you join or create a hunt. It then registers for remote
notifications and sends the hex APNs token to `POST /v1/me/device-tokens`.

Sending is done by the Go server's push worker (`PUSH_ENABLED=true` in `server/.env`).
- Create an APNs **Auth Key (.p8)** in Certificates, Identifiers & Profiles → Keys. Put the Key ID,
  Team ID and the .p8 contents in `server/.env` (`APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_KEY_FILE`).
- Debug builds use the **sandbox** APNs host (`aps-environment = development`).
- Put `"game_id": "<uuid>"` at the top level of the push payload. Tapping the notification then opens
  that game.

## 4. Build and run

```sh
cd ios
xcodegen generate
open FindMe.xcodeproj           # or build from the CLI:
xcodebuild -project FindMe.xcodeproj -scheme FindMe \
  -destination 'generic/platform=iOS Simulator' -configuration Debug build CODE_SIGNING_ALLOWED=NO
```

The Simulator has no camera. On the proof screen, a **"Dùng ảnh thử (Simulator)"** button uploads a
generated test image so you can test the whole proof flow. This button exists only in simulator builds.

Deep links:
- `findme://join/ABC123` opens the join sheet with the code filled in.
- `findme://game/<uuid>` opens a game.

Test from a terminal with `xcrun simctl openurl booted findme://join/ABC123`.

## Project structure

```
ios/
  project.yml                      XcodeGen spec (target settings come from Config/App.xcconfig)
  Config/App.xcconfig              defaults + FREE_TEAM switch, includes Secrets.xcconfig
  Config/Secrets.example.xcconfig
  FindMe/
    App/        FindMeApp (root, URL handling), AppDelegate (APNs, notification taps), AppRouter (deep links)
    Core/       GoAPI (server client), API + HostAPI (every server call), Supa (sign-in + JSON coding),
                Models, AppError (server error code → message), ImageCompressor, SignedURLCache,
                PushManager, ConnectivityMonitor, Formatters, AppConfig
    Features/
      Auth/     AuthStore (Apple nonce, Google OAuth, email OTP), SignInView
      Home/     HomeView (my games with role, Join, Create), JoinGameSheet, CreateGameView + GameFormFields
      Game/     GameViewModel (state, realtime, refresh), GameScreen (player/staff tabs), HintTab
                (hint blocks, countdown, code entry, proof status, lobby, player info/leave)
      Proof/    CameraController (AVFoundation), ProofCaptureView (countdown, compress, upload retry, attach)
      Map/      JourneyMapView (solved pins + polyline, winner photo, on-device user location)
      Leaderboard/, Results/ (share card via ImageRenderer + ShareLink), Profile/ (name, delete account)
      Host/     ManageTab (lobby, start/schedule/cancel, hints list, settings, participants/co-host),
                HintEditorView (create/edit hint, items editor, new code, F-07 preview), PinPickerMap,
                ProofSheetView (printable code PDF), ReviewTab (review queue + detail, activity timeline, rewards payout)
    Shared/     Components (countdown, chips, signed images, banner, error alert)
    Resources/  Info.plist (generated by XcodeGen), entitlements (full + free team),
                Localizable.xcstrings (vi source + en), InfoPlist.xcstrings, Assets
```

## Localization

`Localizable.xcstrings` uses Vietnamese (`vi`) as the source language and has English translations.
UI strings are written in Vietnamese in code, as `Text("...")` or `String(localized:)`. When you add
new strings, open the catalog in Xcode and add the English translation (with plural variations if the
string contains a count). Users switch language in iOS Settings → Find Me! → Language.

Check coverage with `bash scripts/check-strings.sh`. It builds the app and fails if a string in code
is missing from the catalog, has no English translation, or is no longer used.

Push notifications are localized on the device too. The server's push worker sends APNs `loc-key` /
`loc-args`, and iOS resolves them from the `push.*` entries in `Localizable.xcstrings`.
