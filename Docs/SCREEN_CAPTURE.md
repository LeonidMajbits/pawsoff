# ScreenCaptureKit integration

**PawsOff does not stop capture. It also cannot make an arbitrary display-capture client see through its windows without cooperation.** Modify the client filter, not the guard's window-sharing flag. See architecture sources S7–S9.

Within the existing capture client's async setup, use its chosen display:

```swift
let available = try await SCShareableContent.excludingDesktopWindows(
    false, onScreenWindowsOnly: false
)
let pawsOffApplications = available.applications.filter {
    $0.bundleIdentifier == "com.leonidmajbits.pawsoff"
}
let filter = SCContentFilter(
    display: selectedDisplay,
    excludingApplications: pawsOffApplications,
    exceptingWindows: []
)
// New stream:
let stream = SCStream(filter: filter, configuration: configuration, delegate: delegate)
// Or, for the existing stream instead:
// try await stream.updateContentFilter(filter)
```

`selectedDisplay`, `configuration` and `delegate` are objects belonging to the capture client, not PawsOff. Get the application list after the bundled PawsOff process exists. An application-based filter covers that process's subsequent curtain windows better than freezing a list of its current window IDs. After PawsOff restarts, refresh its process entry and the filter. Empty matches mean **no exclusion**; handle that as a configuration error rather than claiming success. The standalone probe does so.

A client capturing one application/window may use a window-specific filter instead. Do not add an exclusion and then add the same curtain window to `exceptingWindows`, which would invert the intended rule. A capture client's own existing permissions and OS privacy controls still apply. The app's one-off source handoff cannot modify Gemini Operator Lab's unseen capture implementation.

## Native probe

```bash
make probes
# PawsOff must already be running as its bundle.
# Start this in Terminal; immediately focus the harmless input probe and drop the curtain.
(sleep 5; dist/probes/capture-probe --seconds 45 \
  --snapshot "$HOME/Desktop/pawsoff-excluded.png") > /tmp/pawsoff-capture-excluded.ndjson 2>&1 &
```

The five-second delay lets the curtain's process/windows appear in the shareable-content list before filter creation. The output PNG path must not exist. Keep the curtain active until the probe ends so the saved last complete frame tests exclusion while active. The first run may require Screen Recording authorization for the probe/launching host; complete that consent with the curtain off and rerun. Authorization for PawsOff's input guard is different from authorization for this capture probe.

For a control run, use another new filename and add `--include-curtain`. That control capture should contain the curtain/HUD; the exclusion run should contain the actual underlying scene. Inspect the images locally. Snapshots can contain private desktop information and are **not uploaded automatically**.

The probe records successful shareable-content enumeration, elapsed query time and cumulative complete-frame counts, on the main display selected at startup. A static screen may produce fewer new complete frames; low counts alone do not prove blocked capture. Display disconnects, a PawsOff restart and cross-display capture require refreshing the target/filter or rerunning the probe. It is a bounded diagnostic, not a production capture service or a frame-rate benchmark.

Default operation writes no screenshot; `--snapshot` is explicit opt-in. `--seconds` is bounded to 1–3600. The probe is not linked into the shipped utility. It was syntax-parsed, not natively compiled or run, in this handoff.
