# Max Werba

iPhone movement diary for one English bulldog and one WHOOP 5.0 MG strap. The phone keeps distance, resting, and moving. The strap stays on the dog. There is no WHOOP account and no cloud sync.

Today shows three labeled circles: Rest out of 12 hours, Movement out of a 3 mile day, and Strain out of 21. The number sits inside each circle and the name sits under it. The app stays in dark mode. Max's photo is a separate circle above his name.

Export at the bottom writes a one-page dark PDF and opens the iOS share sheet. The bone at the top left, while he is resting, opens a short chat about today's distance.

<< and >> step through days. Tomorrow is a written exercise goal from today's totals. Pull to refresh reloads the day. Settings hold his name, breed, age, weight, and stride.

A daily note and one dinner stay closed until they are tapped. They are written when `App/OpenRouter.plist` is on the phone. That file is not in git. `App/OpenRouter.example.plist` shows the shape.

Open `VV00P.xcodeproj` in Xcode. The app target is VV00P, bundle id `com.jaredwerba.vv00p`.

WhoopBLE is a local Swift package, not a GitHub package URL:

```
../src/Asherlc__whoop-ble-swift
```

Clone [jaredwerba/Asherlc__whoop-ble-swift](https://github.com/jaredwerba/Asherlc__whoop-ble-swift) at that path before building. The diary calls `WhoopBleClient.buzz(seconds:)`.

The screen font is John Sauter's OCR-A (public domain, SourceForge project `ocr-a-font`), in `App/Fonts`.

`swift run pace-check` runs the motion and history checks.
