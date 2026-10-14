# Refs freeze: 14 October 2026

## Recorded evidence

The owner reported that Refs stopped responding to capture shortcuts and inputs. Finder subsequently reported that Refs was not responding. The running app was `/Applications/Refs.app`, PID 74361, launched on 12 October at 13:36:07. No restart, installation or further UI interaction was performed while preparing this fix.

Two previously captured samples, at 17:26:22.520 and 17:29:46.912 CEST, contain the same 12 Swift cooperative worker threads blocked in `AEDeterminePermissionToAutomateTarget`, waiting on a native semaphore. These threads remained blocked across the 204.392-second interval. A text search finds 13 occurrences because the sampling report also repeats the function in its totals summary.

The sampled binary, the existing release binary, and its dSYM share UUID `37044592-32A6-3B91-A80F-CFEC60C4D33C`. Symbolication identifies the call chain as:

```text
BrowserPermissionsModel.refresh()                 BrowserPermissions.swift:58
BrowserSupport.knownPermission(for:)              BrowserSupport.swift:170
BrowserSupport.permission(for:ask:)               BrowserSupport.swift:155
AEDeterminePermissionToAutomateTarget (ask: false)
semaphore_wait_trap
```

Line numbers above describe the pre-fix implementation at source head `cde0d45973094de1547259e76a2ab4958b601f82`. The sample files were saved locally as `/private/tmp/refs-freeze.sample.txt` and `/private/tmp/refs-after-escape.sample.txt`.

```sh
dwarfdump --uuid .build/release/Refs .build/release/Refs.dSYM
atos -o .build/release/Refs.dSYM/Contents/Resources/DWARF/Refs -arch arm64 -l 0x102934000 0x10296f8b9 0x102965cf5 0x10296f881 0x102969774 0x10294eeb8 0x10294e8e0
```

## Application failure mechanism

Permission-list refresh observes all application launches and terminations, Refs activation, and remembered permission changes. Each notification starts a new detached task, with no refresh-in-progress guard. A detached task still runs on Swift's cooperative executor. When a passive macOS permission check fails to return, successive refresh notifications consume more cooperative workers. The recorded blocked workers all originated in these refreshes; they were not capture-prefetch calls.

Capture has related unbounded waits. It awaits the selected browser's prefetch task before calling its completion callback. AppDelegate retains the capture session until that callback; later capture shortcuts return early while that session exists. Its fallback `BrowserAccess.check` also synchronously checks Automation permission inside the capture's MainActor task, creating another direct UI-blocking path.

Swift's maintainers explain that [detached tasks use the same cooperative pool and blocking many of its workers can prevent other tasks from progressing](https://forums.swift.org/t/concurrency-blocking-a-detached-task/52870). Moving a blocking operation into another detached task or racing it in a task group does not make the native call cancellable.

## Limits of the diagnosis

The samples establish persistent native waits and repeated refresh fanout. They do not reveal the queried browser or the internal macOS/TCC condition that caused the permission API to stall. Both samples show the main thread in AppKit's normal event loop, so they do not by themselves prove why Finder marked the app unresponsive or explain every rejected input. The fix targets the demonstrated application failure mechanism and removes the related main-thread and capture-metadata waits.

Read-only historical unified-log searches for Refs/TCC around 17:23–17:30 returned 19 relevant event records, with no browser target or evidence of a permission denial, timeout or deadlock. A narrower AppleEvents/AEDetermine query for PID 74361 returned no records, including informational/debug events. These logs do not establish the underlying native cause.

## Fix requirements

- Run synchronous permission and AppleScript work on dedicated blocking execution, with a small fixed limit on actual native operations.
- Coalesce identical requests and return a fallback at a deadline. A timed-out native operation must continue occupying its slot until it actually returns, preventing abandoned-thread growth.
- Use an independent timer queue; neither Swift worker availability nor the blocked native queue may control the deadline.
- Coalesce permission-list refreshes and keep UI state changes on MainActor.
- Bound optional browser metadata and remove synchronous permission checks from capture completion. A screenshot can still be saved with its app/window title when URL lookup is unavailable.
- Verify with held synthetic lookups, without contacting macOS permission services or modifying the owner's library.

The implementation limits native work to two permission queries and one tab-script operation. Tab-script execution stays serialized as [recommended by Apple DTS](https://developer.apple.com/forums/thread/759287). Different browsers may briefly compete for a slot; callers retry asynchronously within their original deadline, so normal contention does not immediately discard the selected browser's URL. Passive permission checks have a 0.6-second budget, tab reads 1.2 seconds, and explicit permission prompts 120 seconds. Actual native calls remain counted after callers time out, until the calls return. A permanently stalled native API can therefore make browser metadata unavailable until a later restart, while screenshots and the UI remain independent of that work.

Permission refresh maintains one in-flight task and at most one follow-up refresh. Explicit requests cancel stale passive refreshes before updating their row. Unknown status stays unavailable rather than being counted as a decided permission; onboarding offers Retry when only unavailable statuses remain.

## Validation

The regression for refresh fanout failed before the fix: 16 refresh requests produced 16 held permission lookups instead of one. The same test passes after coalescing.

All 68 tests in 11 suites pass. New checks cover native permission/tab stalls, caller deadlines, worker-slot retention, cancellation, coalescing, late results, serialized multi-browser lookups, and the actual capture-result finalization seam retaining its image/window metadata while native work is still blocked. The in-memory fixtures and injected calls do not contact browser Automation services or use the owner's library.

```sh
CLANG_MODULE_CACHE_PATH="$PWD/.build/freeze-check/clang-cache" SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/freeze-check/swift-cache" swift test --disable-sandbox --scratch-path .build/freeze-check --cache-path .build/freeze-check/pm-cache --config-path .build/freeze-check/pm-config --security-path .build/freeze-check/pm-security
```

The outer filesystem sandbox prevented two existing fixtures from using macOS HEIC/H.264 encoders. Re-running the already-built suite with the same flags and `--skip-build` outside that sandbox passed all 68 tests. The new freeze tests passed in both environments.

The release build passes without compiler warnings. A separate local verification app is prepared at `build/freeze-fix/Refs.app`; `codesign --verify --deep --strict` passes. This verification copy is ad hoc signed. A future installation should use the existing development signing identity to preserve macOS permission attribution.

The installed executable's SHA-256 remains `835e6f9e9627ae4252901482040ea00dc5778f815d6e43cc7c7e88a1abe9fd78`, identical to the value recorded before the fix. No restart, installation, permission change or owner-library write was performed. Native hotkeys and Finder reopening still need runtime verification when the owner chooses to apply the fix.
