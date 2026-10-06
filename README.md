# Max Werba

iPhone movement diary for one English bulldog and one WHOOP 5.0 MG strap. The phone keeps distance, resting, and moving. The strap stays on the dog. There is no WHOOP account and no cloud sync.

Today shows three rings: distance out of 1 mile, resting as a share of recorded time, and moving out of a 30-minute day. The card under the rings is today's walking still left, plus this week's saved totals.

Open `VV00P.xcodeproj` in Xcode. The app target is VV00P, bundle id `com.jaredwerba.vv00p`.

WhoopBLE is a local Swift package, not a GitHub package URL:

```
../src/Asherlc__whoop-ble-swift
```

Clone [jaredwerba/Asherlc__whoop-ble-swift](https://github.com/jaredwerba/Asherlc__whoop-ble-swift) at that path before building. The diary calls `WhoopBleClient.buzz(seconds:)`.

The screen font is John Sauter's OCR-A (public domain, SourceForge project `ocr-a-font`), in `App/Fonts`.

`swift run pace-check` runs the motion and history checks.
