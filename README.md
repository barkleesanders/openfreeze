# OpenFreeze

A free, open-source macOS virtual camera. Freeze your webcam, play a video
loop, or fake a bad connection — in Zoom, Google Meet, Teams, or any app that
uses the system camera picker.

MIT licensed. No accounts, no licensing server, no telemetry, no network
calls. Your video never leaves your machine.

## How it works

- **OpenFreeze.app** (SwiftUI): captures your real webcam with `AVCaptureSession`
  (or renders a synthetic test pattern when no camera is present), applies the
  selected effect, and pushes frames into the system extension.
- **OpenFreezeCameraExtension** (`CMIOExtension` system extension): exposes a
  virtual camera device named **"OpenFreeze"** with a source stream and a sink
  stream. The app discovers the sink stream via CoreMediaIO and enqueues
  `CMSampleBuffer`s; the extension relays them to the source stream that
  conferencing apps consume.

Effects (all applied app-side):

| Mode | Behavior |
| ---- | -------- |
| Live | Passes the webcam through untouched |
| Freeze | Re-enqueues the last frame on a ~1s timer — you appear frozen |
| Loop | Plays a user-picked `.mp4`/`.mov` on repeat via `AVAssetReader` |
| Bad connection | Low-fps frame hold with stutter, like a struggling uplink |

The app persists the selected mode to
`~/Library/Application Support/OpenFreeze/state.json`, polled twice a second,
so the mode can also be toggled headlessly or by scripts.

## Build

Requirements: macOS 14+, Xcode 16+ (built with Xcode 26.6), xcodegen
(`brew install xcodegen`).

```sh
git clone https://github.com/barkleesanders/openfreeze.git
cd openfreeze
xcodegen generate
xcodebuild -project OpenFreeze.xcodeproj -scheme OpenFreeze -configuration Release build
```

The project uses manual signing. After building, re-sign the app to attach the
system-extension entitlement (Xcode cannot attach it without a provisioning
profile — see below):

```sh
codesign --force --options runtime --sign "<Your Identity>" \
  --entitlements App/OpenFreeze.entitlements \
  ~/Library/Developer/Xcode/DerivedData/OpenFreeze-*/Build/Products/Release/OpenFreeze.app
```

## Install

1. Copy `OpenFreeze.app` to `/Applications` (required — system extensions can
   only be activated from apps in `/Applications`).
2. Launch the app once. It submits the system-extension activation request.
3. Approve it in **System Settings → General → Login Items & Extensions**
   under *System Extensions*: allow "OpenFreeze".
4. The camera **"OpenFreeze"** now appears in Zoom / Meet / Teams camera
   pickers. Pick it, then use the app window to freeze, loop, or degrade.

Headless activation (for scripts): `OpenFreeze.app/Contents/MacOS/OpenFreeze
--activate-extension`.

## Signing requirement (important)

The app needs the restricted entitlement
`com.apple.developer.system-extension.install` to activate its camera. On
current macOS, an app that carries this entitlement **and** embeds a system
extension is killed at launch (SIGKILL, no crash log) unless the signature is
backed by the right Apple-issued credential. Concretely, with only an "Apple
Distribution" (App Store) certificate and no provisioning profile:

- Xcode refuses to attach the entitlement at build time ("requires a
  provisioning profile with the System Extension feature"), and attaching it
  afterwards by re-signing makes launchd kill the app on launch. This is Apple
  platform policy, not a bug in this code. Verified empirically: the same
  binary runs fine with the sysex embedded but the entitlement removed — and
  `OSSystemExtensionManager` then fails with
  `OSSystemExtensionErrorDomain Code=2 "Missing entitlement
  com.apple.developer.system-extension.install"`.

To ship a working build for direct (DMG) distribution you need, from the
Apple Developer portal, a **Developer ID Application** certificate. That is
the standard credential for system extensions distributed outside the App
Store (no provisioning profile required for direct distribution). Then:

1. Import the Developer ID certificate into the build keychain.
2. Set `CODE_SIGN_IDENTITY` to it in `project.yml` and regenerate.
3. Build, then attach the entitlement via the documented re-sign step.

After that: install to `/Applications`, launch, approve once in System
Settings → General → Login Items & Extensions, and "OpenFreeze" appears as a
camera.

## Gatekeeper

Until the app is notarized, macOS Gatekeeper will block the first launch of
the DMG build. Right-click (or Control-click) `OpenFreeze.app` → **Open** →
confirm. After the first approval it launches normally.

## Project layout

```
project.yml              xcodegen source of truth (OpenFreeze.xcodeproj is generated)
App/                     SwiftUI app
  OpenFreezeApp.swift    entry point, --activate-extension flag
  CameraCapture.swift    AVCaptureSession / synthetic test pattern
  SinkPump.swift         CoreMediaIO sink discovery + frame enqueue
  EffectsEngine.swift    freeze / loop / bad-connection
  ExtensionInstaller.swift  OSSystemExtensionManager activation
  ContentView.swift      preview + controls
  StateStore.swift       mode persistence (~/Library/Application Support/OpenFreeze/state.json)
  OpenFreeze.entitlements       real entitlements (used for the manual re-sign)
  OpenFreeze.build.entitlements build-time entitlements (empty; profile adds the rest)
CameraExtension/         CMIOExtension system extension
  main.swift             CMIOExtensionProvider entry
  ProviderSource.swift   provider + device "OpenFreeze"
  StreamSource.swift     .source stream ("OpenFreeze Video")
  StreamSink.swift       .sink stream + Pump (sink → source relay)
```

## Status

Builds cleanly under Xcode 26.6 and passes `codesign --verify --deep --strict`.
End-to-end camera activation is blocked on the provisioning profile described
above; everything up to that point is implemented and verified.

## License

MIT — see [LICENSE](LICENSE).
