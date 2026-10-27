# Tartellette

A minimal macOS menu bar front-end for [Tart](https://tart.run) virtual machines.

## Features

The menu lists the local VMs reported by `tart list` (green = running, orange = suspended, grey = stopped).
OCI images from tart's cache are in a separate **OCI Images** section, because they can't be run directly. Each image has:

- **Clone**: creates a local VM from the image with `tart clone`. The VM is named after the image, e.g. `ghcr.io/cirruslabs/macos-golden-gate-xcode:latest` → `golden-gate-xcode`. If that name is taken, `-2`, `-3` and so on is added.
- **Delete…**: removes the image from tart's cache after confirmation. VMs already cloned from it are not affected.

Each local VM has a submenu with:

- **Start / Resume / Stop / Suspend**: Start (stopped VMs) and Resume (suspended VMs) run `tart run` detached and log to `~/Library/Logs/Tartellette/<vm>.log`.
  Stop is offered for running and suspended VMs. On a suspended VM it discards the saved state, so it asks for confirmation first.
- **Show GUI on Start**: a per-VM toggle. When off, the VM starts with `--no-graphics`.
- **Allow Suspend (No Audio)**: on by default, and can only be changed while the VM is stopped. Starts the VM with `--suspendable`, which disables audio.
  Only a VM started this way can be suspended: a VM booted without the flag can still be suspended, but its snapshot never restores.
  If a resume fails anyway, Tartellette offers to discard the saved state and boot normally.
- **Settings** (local VMs, only while stopped): display, CPU cores, and memory, applied with `tart set`.
  - Display: standard sizes from 1024×768 to 1920×1080, or Free, which turns on `--display-refit`.
  - CPU cores: from 2 to the number of host cores minus one.
  - Memory: from 4 GB to half of the host's RAM.
  Current values are read from the VM's `config.json`, because `tart get` doesn't report display refit.
- **Shared Folders**: the host folders passed to `tart run --dir`. You can add, remove, make read-only, and set the guest name or mount tag.
  Editing is only possible while the VM is stopped, because changing shares on a suspended VM would break its snapshot.
  A missing folder is marked with ⚠, and Start refuses to run until it is restored or removed.
- **Copy IP Address**: copies the output of `tart ip` to the clipboard.
- **Open Shell in Terminal**: opens an `ssh <user>@<ip>` session in your default terminal.
  That's the app registered to open executable files, e.g. iTerm2 after "Make iTerm2 Default Term". Without one, it falls back to Terminal.
  The user defaults to `admin`; change it with `defaults write com.tartellette.app sshUser <name>`.
- **Info…**: shows the output of `tart get`.
- **Rename… / Delete…**: only shown when the VM is not running. Rename is only offered for local VMs, and Delete asks for confirmation first.

## Build

```sh
./scripts/bundle.sh        # -> build/Tartellette.app
open build/Tartellette.app
```

For development, `swift run` also works.

## Layout / extending

| Path | Role |
|------|------|
| `Tart/TartClient.swift` | Wraps the `tart` CLI. Add new subcommands (create, clone, pull, login…) here. |
| `Tart/VM.swift` | Model decoded from `tart list --format json`. |
| `Tart/VMConfig.swift` | Per-VM run options (GUI, shared folders) and how they map to `tart run` arguments. Add new run options here. |
| `Tart/VMHardware.swift` | Reads display, CPU and memory from a VM's `config.json`, and lists the choices offered for each. |
| `Actions/HardwareActions.swift` | The Settings submenu. |
| `Actions/SharedFolderActions.swift` | The Shared Folders submenu. It shows how to build nested, data-driven menus with the `.submenu` kind. |
| `Actions/VMAction.swift` | Action descriptor and `AppContext`. A descriptor has a kind (`command` or `toggle`), a visibility predicate, and an optional `isDone` predicate. With `isDone` set, the VM shows a spinner until the predicate holds. |
| `Actions/ImageActions.swift` | Actions for OCI images (Clone, Delete). |
| `Actions/VMActions.swift` | The per-VM action registry. Append a `VMAction` to a group to add a menu entry. |
| `UI/MenuBuilder.swift` | Generates the menu from the VM list and the action registry. |
| `UI/Dialogs.swift`, `UI/Terminal.swift` | Alerts, prompts, and terminal launching. |
| `AppDelegate.swift` | Status item, refresh loop (on menu open and every 5 s). |

Global commands (e.g. "New VM…", "Registry Login…") can go into `MenuBuilder.populate` above the Quit item.
They can also go into a similar `GlobalActions` registry once more of them exist.
