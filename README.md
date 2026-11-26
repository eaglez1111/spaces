# Spaces

A macOS menu bar app that links Spaces across multiple monitors into named project groups, so you can switch your entire workspace with a single click or hotkey.

![Spaces overlay switcher](screenshot.png)

## The problem

Mission Control and macOS Spaces are powerful, but they fall apart on a multi-monitor setup:

1. **Spaces have no names.** In Mission Control they all look the same, so it's hard to remember which Space is for which project.
2. **Spaces switch independently per monitor.** Even if you set up a nice workspace across both screens, switching on one display doesn't switch the other. You end up manually moving both monitors just to stay in the same context.

## The solution

Spaces lets you link one Space on Monitor A with one Space on Monitor B and treat them as a single named group. Once linked, you can switch both together — your workspace stays aligned and you can jump between projects without losing your setup.

- **Automatic numeric groups** — each group maps corresponding desktops across monitors
- **Switch instantly** — click a group in the menu bar or press the hotkey, and all monitors jump to the right desktops simultaneously
- **Overlay switcher** — press Option+Space to get a visual overlay showing all your groups, navigate with arrow keys or number keys
- **Move windows** — right-click in the overlay to move the frontmost window to another group's space
- **Auto-detect** — the active group updates automatically when you switch spaces via Mission Control
- **Follow** (on by default, Settings > General) — change the Space on one display with a swipe or Mission Control and the other displays in that group follow

## Requirements

- macOS 15.0 (Sequoia) or later
- [Xcode](https://developer.apple.com/xcode/) 16.0 or later (to build from source)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (to regenerate the Xcode project if needed)
- Keyboard shortcuts for switching desktops must be enabled in **System Settings > Keyboard > Keyboard Shortcuts > Mission Control** (Ctrl+1 through Ctrl+10, and optionally Ctrl+Option+1 through Ctrl+Option+6 for desktops 11-16)

## Installation

### Build and install

```bash
git clone https://github.com/minsfb/spaces.git
cd spaces/SpaceSwitcher
./install.sh
```

This builds the app, installs it to `/Applications/Spaces.app`, and launches it.

**No prebuilt binaries are published for this project; build it from source.** See [DEVELOPMENT.md](DEVELOPMENT.md) for build and test details.

### Grant Accessibility access

On first launch, macOS will prompt you to grant Accessibility access in **System Settings > Privacy & Security > Accessibility**. This is required for simulating the keyboard shortcuts that switch desktops.

## Usage

### Menu bar

Click the menu bar icon to:
- Switch to any group
- Create a new group (captures your current desktops)
- Open Settings

### Overlay (Option+Space)

Press **Option+Space** to show the overlay switcher:
- **Left/Right arrows** — navigate between groups
- **Enter** — switch to the focused group
- **1-9** — switch to a group by number
- **Right-click** — move the frontmost window to the focused group's space
- **Escape** — dismiss

### Settings

- **Groups tab** — review the automatically generated monitor/desktop mappings
- **General tab** — configure the hotkey, enable launch at login

## How it works

- Uses macOS private CGS APIs to detect spaces and their IDs per display
- Switches desktops by simulating Ctrl+Number keyboard shortcuts (the same ones you'd press manually)
- Groups store `display UUID -> Space UUID`, so they keep pointing at the same Space when Spaces are reordered, added, or re-created, and when a display is unplugged and replugged
- Private CGS APIs are used only to *read* Space layout; Spaces are switched with the native keyboard shortcuts (see the notes below)
- Runs as a menu bar app (`LSUIElement`) with no dock icon

## Notes on macOS behavior

Findings from testing on macOS 26 (details in the repository issues):

- Other apps' windows cannot be moved between Spaces with private CGS calls without disabling SIP; this project does not use or require SIP changes. Window moves in the overlay work by emulating a title-bar drag plus the Space-switch shortcut.
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
├── Overlay/              # Overlay switcher panel and views
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
**Option + Tab** cycles groups, and **Option + Space** opens the group overlay.
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


### Cmd+Tab: apps grouped by Space

Settings → General → **Replace Cmd+Tab with apps grouped by Space** is an
optional mode (on by default on new installations). The switcher shows one icon
per application in each native Space group. Thus Chrome can appear once in
Group 1 and again in Group 2 even if it has several windows in either group. No window previews
are rendered. Hold Command, tap Tab or Shift+Tab, and release Command to select.
Escape cancels. Choosing an app switches the full monitor group first and
then raises one of the app's windows within that group.

This mode takes over the operating system's Cmd+Tab/Cmd+Shift+Tab symbolic
hotkeys and uses a keyboard event tap; Accessibility permission is required.
Turning off the setting or quitting Spaces normally restores the native
switcher. Spaces also attempts to restore the native shortcuts on termination
signals and on its next launch after a crash. A forced termination (SIGKILL)
cannot run cleanup: relaunch Spaces to restore the shortcut.

The visible list is based on normal windows, and uses read-only private SkyLight
Space membership. Minimized, fullscreen-only, and protected windows may not
appear. The existing Space-group overlay (Option+Space) and group shortcuts
(Option+arrows by default) are unchanged.

The automatic groups are labeled **1, 2, 3, ...**, each using the original
computer icon.


### App switcher layout and installation defaults

The Cmd+Tab overlay now uses macOS-style **horizontal icon tiles**, one row
per automatically generated Space group (two groups = two rows). The Space
groups themselves are unlabeled in this overlay; only the selected app's name
appears beneath the icons. Each app appears once per group, even if it has
several windows there. Cmd+Tab navigation, group switching, and focus behavior
are unchanged.

Automatic groups are now labeled **1, 2, 3, ...** and all use the original
**Labtop** computer icon. On fresh installs (and only when a preference has
never been saved), these settings default to on: group swipe-follow,
single-window app-follow, Cmd+Tab replacement, bottom Dock lock, and launch at
login. The default dock target is the center display in a three-monitor
arrangement; otherwise it falls back to the main display. Shortcut defaults:
Option+Space for the existing group overlay, Option+Left/Right to change
groups, and Option+Tab to cycle groups. User-customized settings remain intact.
