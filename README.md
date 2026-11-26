# Spaces

A macOS menu bar app that synchronizes Spaces across monitors, with quick group switching and a cross-Space Cmd+Tab picker.

## The problem

Mission Control and macOS Spaces are powerful, but they fall apart on a multi-monitor setup:

1. **Spaces have no names.** In Mission Control they all look the same, so it's hard to remember which Space is for which project.
2. **Spaces switch independently per monitor.** Even if you set up a nice workspace across both screens, switching on one display doesn't switch the other. You end up manually moving both monitors just to stay in the same context.

## The solution

Spaces lets you link one Space on Monitor A with one Space on Monitor B and treat them as a single named group. Once linked, you can switch both together — your workspace stays aligned and you can jump between projects without losing your setup.

- **Automatic numeric groups** — each group maps corresponding desktops across monitors
- **Switch instantly** — click a group in the menu bar or press the hotkey, and all monitors jump to the right desktops simultaneously
- **Custom Cmd+Tab** — browse apps by Space row; use Up/Down to change rows and Left/Right within a row
- **Follow** (on by default, Settings > General) — change the Space on one display with a swipe or Mission Control and the other displays in that group follow

## Requirements

- macOS 15.0 (Sequoia) or later
- [Xcode](https://developer.apple.com/xcode/) 16.0 or later (to build from source)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (to regenerate the Xcode project if needed)
- Keyboard shortcuts for switching desktops must be enabled in **System Settings > Keyboard > Keyboard Shortcuts > Mission Control** (Ctrl+1 through Ctrl+10, and optionally Ctrl+Option+1 through Ctrl+Option+6 for desktops 11-16)

## Installation

### Build and install

```bash
git clone https://github.com/eaglez1111/spaces.git
cd spaces/SpaceSwitcher
./install.sh
```

This builds the app and installs it to `/Applications/Spaces.app`. Launch Spaces manually after installation.

**No prebuilt binaries are published for this project; build it from source.** See [DEVELOPMENT.md](DEVELOPMENT.md) for build and test details.

### Stable signing and one-time permission cleanup

The installer now checks for a reusable signing identity **before** stopping or
replacing the installed app. It uses a single production bundle identity,
`com.spaceswitcher.Spaces`. The Xcode target builds `Spaces.app` directly; it no longer creates
a separate `SpaceSwitcher.app` identity.

To avoid repeated macOS Accessibility reapproval, create a code-signing
certificate **once** using Keychain Access → Certificate Assistant → Create a
Certificate (name `Spaces Local Signing`, identity type **Self Signed Root**,
certificate type **Code Signing**). Keep it in your login keychain and configure
it to be trusted for Code Signing. An existing Apple Development or Developer
ID Application identity also works; select it explicitly with
`SPACES_SIGNING_IDENTITY="certificate name or SHA-1" ./install.sh`.

Without a stable identity, `./install.sh` stops without changing the installed
app; use `SPACES_ALLOW_ADHOC=1 ./install.sh` only if you accept repeated
permission prompts. If switching away from a previous ad-hoc signature, remove
the old **Spaces** entry in macOS Privacy & Security → Accessibility, re-add the
installed `/Applications/Spaces.app`, approve it, and relaunch Spaces once.

An old **SpaceSwitcher** permission entry comes from an earlier development
build. Remove it manually with the minus button under Accessibility and, if
present, Input Monitoring. Remove any separate old `SpaceSwitcher.app` from
Applications using Finder. Keep the source directory named `SpaceSwitcher`:
it contains the Xcode project and is not another installed app.
The sole app target, executable and bundle identity are now `Spaces`.
The installer never modifies macOS privacy approvals or resets TCC data.

### Grant Accessibility access

On first launch, macOS will prompt you to grant Accessibility access in **System Settings > Privacy & Security > Accessibility**. This is required for simulating the keyboard shortcuts that switch desktops.

## Usage

### Menu bar

Click the menu bar icon to:
- Switch to any group
- Open Settings

### Settings

- **Groups tab** — review the automatically generated monitor/desktop mappings
- **General tab** — configure shortcuts, Cmd+Tab, synchronization, and Dock behavior

## How it works

- Uses macOS private CGS APIs to detect spaces and their IDs per display
- Switches desktops by simulating Ctrl+Number keyboard shortcuts (the same ones you'd press manually)
- Groups store `display UUID -> Space UUID`, so they keep pointing at the same Space when Spaces are reordered, added, or re-created, and when a display is unplugged and replugged
- Private CGS APIs are used only to *read* Space layout; Spaces are switched with the native keyboard shortcuts (see the notes below)
- Runs as a menu bar app (`LSUIElement`) with no dock icon

## Notes on macOS behavior

Findings from testing on macOS 26 (details in the repository issues):

- Switching a Space with the private `CGSManagedDisplaySetCurrentSpace` call is not equivalent to a native switch, so it is not used.
- When an external display is unplugged, macOS folds that display's first Space into the first laptop Space and appends its other Spaces to the laptop's Space list; on replug it restores them, and the first Space comes back with a different internal ID but the same UUID.

## Project structure

```
SpaceSwitcher/
├── App/                  # App entry point, AppDelegate, AppState, MenuBarView
├── Models/               # DesktopGroup, MonitorInfo, SpaceInfo
├── Logic/                # Pure logic (no AppKit/CGS), unit-tested via the SwiftPM package
├── Services/             # SpaceSwitcherService, MonitorManager, PersistenceManager
├── Settings/             # Settings window views
├── Overlay/              # Cross-Space Cmd+Tab picker and panel
├── Utilities/            # KeyCodes, CGS private API declarations
└── Resources/            # Assets, Info.plist, entitlements
```

## Dependencies

- [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) — global hotkey recording and handling
- [LaunchAtLogin](https://github.com/sindresorhus/LaunchAtLogin-Modern) — launch at login toggle

## License

MIT

## Developer tools

`tools/probes/` holds small standalone programs used to investigate macOS behavior. They are not part of the app or any build.


### Automatic, synchronized Space groups (this fork)

Groups are generated using each display's native Desktop **position**. Group 1 picks the
first Desktop on each display, group 2 the second, and so on. When a monitor has
fewer Desktops, later groups keep that monitor on its last available Desktop.
Changes to display/Space configurations automatically update the mapping.

**Option + Left/Right** switch to the previous/next group with wraparound.
**Option + Tab** cycles groups. **Cmd + Tab** opens the cross-Space app picker when enabled.
Each of these shortcuts can be reassigned in Settings → General.

The existing swipe-follow setting is independent of direct keyboard switching.
After display reconnection, "Refresh Groups" is also available in the menu bar.


### Follow activated apps (single-window mode)

**Spaces → Settings → General → Follow activated apps with one window** enables automatic
group switching for apps activated using AltTab or Command-Tab. When an activated
app has exactly one ordinary window, the app reads its Space and switches the
three-monitor group to the matching group. If the app has multiple normal windows,
the window belongs to several Spaces, or the same Space is reused across multiple
groups, it does nothing. This feature is independent of swipe-follow and can be
disabled in Settings.

Uses a read-only private SkyLight window-to-Space query; behavior may vary with
macOS versions. Fullscreen-only and minimized windows are not guaranteed.


### Bottom Dock lock (this fork)

Spaces → Settings → General includes **Keep Dock at bottom of one monitor** and a
**Dock monitor** selector. The feature defaults to on for new installations.
Move the Dock to the preferred monitor if it was previously on a different one. Once enabled, the
Dock stays on that monitor when you move the pointer to the bottom of another
screen. Hold **Option** to bypass the guard temporarily when you want to move
the Dock yourself.

Implementation: a low-overhead CGEventTap on pointer movement and drags, with
a small boundary guard on the *exposed* bottom edges of non-selected monitors.
The shared edge between vertically stacked monitors is intentionally not
guarded, so pointer travel between displays remains possible. No Dock restart,
private API, or system preference change is needed. The feature uses Spaces'
existing Accessibility permission. It pauses if the selected display is
disconnected, the Dock is not at the bottom, or there is only one monitor.

The Dock lock does **not** forcibly move a Dock that's already on the wrong
screen; place it first, then enable the toggle. Source technique adapted
from DockPin (MIT license, Copyright 2026 Meti Kadriu, see THIRD_PARTY_NOTICES.md).


### Cross-Space app picker (opt-in Cmd+Tab replacement)

**Cmd+Tab** can open a custom cross-Space app switcher. This replaces the native
app switcher only while the user enables it in Settings → General. The enabled/disabled preference now persists across launches. macOS Cmd+Tab
is restored whenever the toggle is switched off or the app quits normally;
if the keyboard event tap cannot start, Settings offers keyboard-permission troubleshooting.

The picker shows one horizontal row per automatic Space group: the first
row for Space 1, the second directly beneath it for Space 2, etc. No group
labels or group icons; one icon per app per group. Hold Command, tap Tab or
Shift+Tab to cycle, Left/Right to move within a row, or Up/Down to change
Space rows. Release Command to switch; Escape cancels. The chosen
app's Space group becomes active on all connected monitors before its window
is raised. The picker appears on the selected Dock monitor.

All window-to-Space membership queries run in a bounded, background task:
no expensive queries occur inside the system keyboard event-tap callback.
The window inventory uses a read-only private SkyLight API, so protected,
minimized, or unusual windows can be missing.

**Dock lock**, separately enabled in Settings, remembers its checked state and
selected monitor across launches.
It needs Accessibility permission and a bottom-positioned Dock. It may prevent
Dock migration when the mouse reaches another monitor's bottom edge. If its
mouse tap times out it stays disabled instead of re-enabling itself.

### Accessibility and reinstall behavior

Accessibility must be granted to the actual production bundle at
`/Applications/Spaces.app`. When an ad-hoc signed app is rebuilt, macOS may
invalidate its old Accessibility approval. In Privacy & Security →
Accessibility, remove obsolete SpaceSwitcher and Spaces entries, add the
installed Spaces.app, and toggle it on. Quit and relaunch the application
before testing. Settings always displays the current Accessibility grant in a neutral
status row, and offers a System Settings button if permission is missing.
Input Monitoring troubleshooting is shown only if Cmd+Tab interception fails.

For permission persistence across reinstallations, use a consistent code-signing
certificate (Apple Development, Developer ID Application, or a local self-signed
Code Signing certificate named **Spaces Local Signing**). The installer automatically
uses it if exactly one qualifying valid identity is available. To choose explicitly,
run `SPACES_SIGNING_IDENTITY="certificate name or SHA-1" ./install.sh`.
Without one, the installer falls back to ad-hoc signing, which can invalidate
the Accessibility grant after every code change. Switching to a stable signer
may require granting Accessibility one final time.

### Shortcuts and safe installation

Default shortcuts: Option+Left/Right (previous/next group), Option+Tab
(cycle groups). Enable custom Cmd+Tab separately in Settings. Group shortcuts
are editable in Settings.

Automatic groups are numbered **1, 2, 3, ...**, all with the original
computer icon. Swipe-follow and single-window activated-app following remain
independently configurable.

After the previous system freeze, the installer stops the actual
`SpaceSwitcher` executable before replacing `/Applications/Spaces.app`.
It no longer restarts Dock, resets Accessibility permissions, or automatically
launches the updated app. Settings persist in a stable preferences domain.
Cmd+Tab replacement is off on a fresh installation and remembers the user's choice.
Permission troubleshooting is shown only when needed.
