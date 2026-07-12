# Spaces Event-Driven Refresh Manual QA

This checklist validates the event-driven Spaces refresh path for both yabai
and AeroSpace. Run the common scenarios once with each manager. Record the
macOS, CielBar, and window-manager versions and note any deviations beside the
relevant check.

## Automated Coverage Decision

The Xcode project currently contains one application target (`CielBar`) and no
test target. Task 10 intentionally does not add an XCTest target because the
project setup and maintenance cost would be larger than this validation-only
task. The core logic remains testable without a running window manager:

- `SpacesRefreshScheduler` injects its snapshot loader and publisher.
- `AerospaceEventJSONLParser.isRelevantEvent(_:)` is an internal, pure helper.

When a test target is introduced, add focused unit cases for:

- scheduler debounce: many requests inside the debounce interval start one
  load;
- scheduler single-flight: a slow load never overlaps another load;
- scheduler follow-up: one or more requests during a load cause exactly one
  subsequent load;
- scheduler unchanged snapshots: an equal snapshot is not published again;
- scheduler stale provider generation: a snapshot from a replaced provider is
  rejected and never becomes the last published state;
- parser acceptance: each of `focus-changed`, `focused-workspace-changed`,
  `focused-monitor-changed`, and `window-detected` is relevant;
- parser rejection: an unknown `_event`, a missing or non-string `_event`, an
  empty line, malformed JSON, and a non-object JSON value are not relevant;
- parser JSONL boundaries: separately supplied lines, trailing whitespace or
  CRLF, and extra payload keys do not change relevance.

## Setup and Expected Refresh Cost

1. Build a Debug app from the repository root:

   ```sh
   xcodebuild -project CielBar.xcodeproj -scheme CielBar \
     -configuration Debug -derivedDataPath /tmp/CielBarDerivedData \
     CODE_SIGNING_ALLOWED=NO build
   ```

2. Enable the Spaces widget and configure the selected manager path if it is
   not installed under `/opt/homebrew/bin` or `/usr/local/bin`.
3. Keep at least two workspaces and two windows in one workspace available.
4. Establish a visible reference for space focus, window focus, title, app
   icon, and workspace membership before each action.

The expected low-frequency fallback interval is 10 seconds. Allow up to one
fallback interval plus normal command runtime for a missed or unsupported
event to self-correct. App activation, wake, manager lifecycle changes, and
widget focus actions can request an earlier refresh.

Expected CLI launches per ordinary snapshot are:

| Provider path | Commands per snapshot | Commands |
| --- | ---: | --- |
| yabai | 2 | query spaces; query windows |
| AeroSpace with metadata support | 3 | list all workspaces; list all windows; list focused window |
| AeroSpace compatibility path | 4 | list all workspaces; list focused workspace; list all windows; list focused window |

AeroSpace may run an extra one-time metadata capability probe before settling
on the compatibility path. The long-lived `aerospace subscribe` process is the
event source and is not a per-snapshot launch. Focus clicks also add their
documented one-off focus command. An event burst should normally coalesce into
one snapshot; a request received during that load may cause one follow-up.

## Launch Order and Provider Lifecycle

For each manager, perform both launch orders:

- Start the window manager, then launch CielBar. The widget should populate
  immediately and should select yabai when both managers are running.
- Launch CielBar with neither manager running, then start the manager. The
  widget should populate after the launch notification without relaunching
  CielBar.
- Stop the active manager. The app must remain responsive and stop showing
  stale manager state after refresh.
- Start or restart that manager. Monitoring and current spaces should recover
  without duplicate monitor processes or yabai labels.
- With one manager active, start or stop the other and confirm the documented
  yabai-first selection remains stable.

## Focus and Window Mutation Matrix

For every row, confirm the widget reaches the authoritative manager state,
does not duplicate windows, and does not visibly churn when a repeated
snapshot is unchanged.

| Action | yabai expectation | AeroSpace expectation |
| --- | --- | --- |
| Focus a workspace with a keyboard shortcut | Prompt event-driven update | Prompt event-driven update |
| Click a workspace in the widget | Target workspace and a window gain focus | Target workspace gains focus |
| Focus another window in the same workspace by keyboard or mouse | Focus indicator moves promptly | Focus indicator moves promptly |
| Click a window in the widget | Its workspace and window gain focus | Its workspace and window gain focus |
| Open a managed window | Window appears promptly | Window appears on `window-detected` |
| Close a managed window | Window disappears promptly | Disappears by a related event if emitted, otherwise within 10 seconds |
| Change a window title, such as switching browser tabs | Title updates promptly | Updates by a related event if emitted, otherwise within 10 seconds |
| Minimize a window | Window visibility matches the next snapshot | Snapshot self-corrects within 10 seconds if no event is emitted |
| Restore/deminimize a window | Window returns when included by the provider | Snapshot self-corrects within 10 seconds if no event is emitted |
| Move a window to another workspace | Membership updates promptly | Membership updates by a related event or within 10 seconds |

## Restart, Sleep, Wake, and Unsupported Monitoring

- Restart the active manager while CielBar stays open. Confirm the previous
  monitor is cleaned up, the provider is recreated, and a fresh snapshot is
  shown.
- Put the Mac to sleep and wake it. Confirm wake requests a refresh, current
  focus and membership return, and monitoring continues without duplicates.
- Test an AeroSpace version/environment where `subscribe` is unsupported or
  exits nonzero. CielBar must not crash or repeatedly fork a subscription
  process; mutate state and confirm the 10-second fallback repairs the widget.
- Test yabai with signal registration unavailable. Registration errors may be
  logged, but the widget must stay usable and repair state through the same
  10-second fallback.
- After each unsupported-monitor test, restore the normal binary/configuration
  and restart the manager and CielBar before continuing.

## Icon Identity, Lifecycle, and Localization

Run these checks with multiple applications, including one whose displayed or
localized name differs from its bundle name when available:

- Confirm each window shows the icon belonging to its actual application, not
  another application with a similar name.
- Open a new application after CielBar starts. Its first managed window should
  acquire the correct icon after the launch-triggered cache reset.
- Quit and relaunch an application while CielBar remains open. Its icon should
  remain correct after the process identifier changes.
- Restart CielBar while the applications remain open. Icons should resolve
  correctly from bundle identifier, bundle path, or process identifier before
  falling back to localized app-name matching.
- Change the system/app language when practical, relaunch the application,
  and confirm the icon remains tied to application identity even when the
  localized display name changes.
- An application with no resolvable icon may show the existing question-mark
  fallback, but must not inherit a different app's cached icon.

## Monitor and Label Cleanup

For yabai, inspect registered signals with:

```sh
yabai -m signal --list | rg 'CielBar\.spaces-event\.'
```

While yabai is the active provider, expect one current-process label for each
of the 13 monitored events. After a graceful CielBar quit or provider switch,
expect none. After an ungraceful termination, relaunch CielBar and confirm it
removes stale `CielBar.spaces-event.*` labels before registering the current
set. Repeated manager or CielBar restarts must not increase the count.

For AeroSpace, inspect subscriptions with:

```sh
pgrep -fl 'aerospace.*subscribe'
```

Expect one CielBar-owned long-lived subscription while AeroSpace is selected,
and none after a graceful CielBar quit or provider switch. Restarting the
manager or CielBar must replace, not accumulate, the subscription process.

## Idle and Process Sampling

1. Leave the Spaces widget untouched for at least 30 seconds.
2. In Activity Monitor, select CielBar and observe CPU and wakeups. Use
   **Sample Process** during the idle window and save the sample with the QA
   record.
3. In a terminal, sample the process for another 20 seconds if a textual
   artifact is useful:

   ```sh
   sample "$(pgrep -x CielBar | head -n 1)" 20 -file /tmp/CielBar.sample.txt
   ```

4. Use Instruments/System Trace or an available exec tracing tool to count
   short-lived `yabai` or `aerospace` launches. Separate snapshot commands
   from the one long-lived AeroSpace subscription and one-off focus commands.
5. During an event-free 30-second interval, expect about three fallback
   snapshots. That is about six yabai command launches, nine AeroSpace
   metadata-path launches, or twelve AeroSpace compatibility-path launches,
   allowing for startup/capability probes and timing at interval boundaries.
6. Trigger a rapid burst of focus/title actions. Confirm command launches are
   coalesced and no two snapshot loads overlap; one follow-up snapshot is
   allowed when events arrive during an in-flight load.

The important regression check is that idle operation no longer resembles the
old 0.1-second polling baseline of about 20 yabai launches or at least 40
AeroSpace launches per second.

## Review, Rollback, and QA Record

Review the event chain in this order:

1. provider lifecycle selection and its generation guard;
2. yabai labels or the AeroSpace JSONL event parser and monitor cleanup;
3. scheduler debounce, single-flight, equality check, and follow-up handling;
4. provider snapshot command counts and icon identity metadata;
5. visible widget state after every matrix action above.

If event-driven behavior regresses, first stop CielBar so its yabai labels or
AeroSpace subscription are removed. Roll back the feature commits together;
the monitoring abstraction, fallback, provider lifecycle, snapshot reduction,
and icon changes are designed as one pipeline. After rollback, remove any
remaining `CielBar.spaces-event.*` yabai labels, restart the manager, and
relaunch the last known-good CielBar build. Do not leave a partially rolled
back monitor paired with a newer scheduler/provider lifecycle implementation.

For each provider, record pass/fail, observed recovery time, command counts,
unexpected logs, saved Activity Monitor/sample artifacts, and any scenario
that could not be run. A review is complete only when unrun manual cases are
explicitly identified rather than treated as passes.
