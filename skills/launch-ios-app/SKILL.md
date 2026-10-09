---
name: launch-ios-app
description: Select a specific iPhone by stable UDID, launch “아주대학교 프린터,” run one complete opening-ad and print-icon ad test cycle including App Store-link checks, then force-quit the app.
---

# Launch an iOS app on a selected device

Use this skill when the user wants the configured iPhone app test cycle. Unless the user explicitly says “앱만 실행” or “launch only,” do not stop after launching the app: complete the Advertisement test pass and force-quit verification.

## Inputs

- `device_udid`: the stable device identifier. Prefer this over row position or display-name matching.
- `app_name_or_bundle_id`: the app to launch; resolve a display name to its installed bundle identifier when necessary.

## Procedure

1. Open Xcode’s Devices and Simulators / Device Hub, or use an equivalent installed-device control that exposes device identity and launch actions.
2. Locate the device whose UDID exactly matches `device_udid`. Do not select a similarly named device or rely on the order of the device list.
3. Confirm the selected device is available and booted/connected. If it is unavailable, report that state instead of silently choosing another device.
4. Resolve `app_name_or_bundle_id` to the installed app. Use the app’s bundle identifier for the launch action where possible; do not infer an unrelated similarly named app.
5. Launch the app on the selected device.
6. Verify the launch result by checking that the selected device is foregrounding the requested app (or that the app’s process is running on that device). Report the device UDID and app identity used.

## Advertisement test pass

After launching this app, always perform both the appropriate automated regression check and an on-device UI pass for the configured test cycle. A launch-only request is the sole exception.

### Automated check

From the repository root, run the ad-flow regression suite with the Xcode developer directory selected:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer sh Tests/run_ad_regression.sh
```

If the task is specifically about the chained rewarded/interstitial flow, also run:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer python3 Tests/run_ad_flow_regression.py
```

Report the actual pass/fail output. These suites use mocks and do not prove that a live ad loaded.

### Device/UI check

On the exact selected device, exercise the ad path as follows:

1. Immediately after launching “아주대학교 프린터,” check for the opening/App Open advertisement.
2. If the opening ad exposes an App Store download button or link, open it, verify the intended product page, return to the app, and then close/dismiss the opening ad.
3. Confirm that the app is usable after the opening ad is closed.
4. Locate the print icon and double-click it three times in succession (three double-clicks total) to enter the print-triggered ad flow.
5. Confirm that the expected advertisement appears before testing its controls and destination link.
6. After completing the ad and App Store-link checks, swipe up from the bottom edge to open the iPhone app switcher, find “아주대학교 프린터,” and swipe its app card upward to force-quit it.
7. Verify that the app card is gone and that the app is no longer running. This force-quit is the end of one complete test cycle.

Then check that:

- the ad appears in the intended scene and does not cover unrelated UI;
- the opening/App Open ad can be closed after any App Store destination check and does not prevent normal app use;
- close/dismiss returns to the app and does not hang or stack another ad;
- the final app-switcher swipe removes “아주대학교 프린터” and ends the app process before the cycle is reported complete;
- rewarded completion is granted only after the reward callback, while early close grants no reward;
- chained ads continue or finish correctly after normal dismiss, no-fill, load failure, timeout, backgrounding, or screen exit;
- returning to the app does not present duplicate App Open/full-screen ads.
- if an ad exposes an App Store download button or link, open it and verify that it reaches the intended App Store product page for the advertised app; record the destination app and URL/product identity when observable;
- after checking the App Store link, return to the test app and verify that the original ad flow and app state remain well-defined.

Capture the device, app build/configuration, ad path, and observed result for each case. Do not use real user data, real purchases, or claim a live-network result when only mocked regression tests ran.

## Safety and boundaries

- The demonstrated example used iPhone 15 Pro (`VDJJV0K9YL`) and “아주대학교 프린터”; treat those as defaults only when the user asks for that same device and app.
- Never claim success from merely selecting a device row or opening Device Hub. Success requires a launch action and an observable running-app check.
- Treat an App Store link as verified only after opening it and observing the intended product page; seeing a clickable-looking ad button is not enough.
- Do not purchase, install, or update an advertised app unless the user explicitly requests that separate action. A valid test may stop at the product page.
- Do not report a completed cycle until the app has been force-quit and its termination has been observed.
- Do not install, delete, reset, erase, or modify device data unless the user separately requests it.
- If multiple installed apps match the display name, ask for or report the bundle identifier before launching.
