# Tartellette

A minimal macOS menu bar front-end for [Tart](https://tart.run) virtual machines.

## Features

The menu lists every VM reported by `tart list` (green = running, orange = suspended, grey = stopped).
The **Hide Remote (OCI) Images** toggle shows only local VMs, and the setting is remembered.
Each VM has a submenu with:

- **Start / Stop / Suspend**: Start runs `tart run` detached and logs to `~/Library/Logs/Tartellette/<vm>.log`.
- **Show GUI on Start**: a per-VM toggle. When off, the VM starts with `--no-graphics`.
- **Copy IP Address**: copies the output of `tart ip` to the clipboard.
- **Open Shell in Terminal**: opens an `ssh <user>@<ip>` session in the default handler for `.command` files.
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
| `Actions/VMAction.swift` | Action descriptor and `AppContext`. A descriptor has a kind (`command` or `toggle`), a visibility predicate, and an optional `isDone` predicate. With `isDone` set, the VM shows a spinner until the predicate holds. |
| `Actions/VMActions.swift` | The per-VM action registry. Append a `VMAction` to a group to add a menu entry. |
| `UI/MenuBuilder.swift` | Generates the menu from the VM list and the action registry. |
| `UI/Dialogs.swift`, `UI/Terminal.swift` | Alerts, prompts, and terminal launching. |
| `AppDelegate.swift` | Status item, refresh loop (on menu open and every 5 s). |

Global commands (e.g. "New VM…", "Registry Login…") can go into `MenuBuilder.populate` above the Quit item.
They can also go into a similar `GlobalActions` registry once more of them exist.
