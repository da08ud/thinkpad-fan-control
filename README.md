# ThinkPad Fan Control

A small Bash command-line interface for reading and controlling the fan through the Linux `thinkpad_acpi` driver. It uses the driver's native `/proc/acpi/ibm/fan` interface and does not run a background fan-control service.

## Compatibility

- **Tested hardware:** Lenovo ThinkPad T480s
- **Tested operating system:** Fedora 44
- **Other ThinkPad models:** not yet verified

The `thinkpad_acpi` driver exposes a common fan interface, but firmware behavior and available modes vary by model. This project does not claim compatibility with every ThinkPad.

## Requirements

- Linux with Bash
- A loaded `thinkpad_acpi` kernel module
- `thinkpad_acpi` loaded with `fan_control=1` for manual fan writes
- The native `/proc/acpi/ibm/fan` interface
- `sudo` for fan-control writes when the CLI is run as a regular user
- `systemctl` for service status reporting
- Standard utilities used by the script: `awk`, `grep`, `head`, and `sed`

Manual-control capability must be enabled on the running module. A persistent modprobe option does not change an already loaded module; reboot after configuring it, then verify the live parameter. See [INSTALL.md](INSTALL.md).

## Commands

```text
fan status
fan manual
fan max
fan ultra
fan auto
fan off
```

### `fan status`

Read-only. Reports the fan mode, RPM, driver parameter, ThinkPad CPU sensor, labeled `coretemp` package/core readings, and the status of `thinkfan.service` and `fancontrol.service`. A systemd access error is reported as an error rather than as an inactive service.

### `fan manual`

Confirms an already selected numeric manual fan level (1–7) without writing a new level. If firmware reports `auto`, the CLI refuses to guess the firmware-selected speed and makes no change. This command intentionally cannot switch from firmware auto to manual while guaranteeing that fan speed will not change.

### `fan max`

Requests `level 7`, the highest recommended normal ThinkPad fan level, and verifies the mode reported by the driver. It requires `fan_control=1` in the running module. It does not use level 0 or the full-speed/disengaged mode.

### `fan ultra`

Requests the driver's `full-speed` mode only after the live fan interface advertises that command and the user types exactly `ULTRA` at an interactive terminal. The warning is shown before the confirmation prompt. Missing, non-interactive, or incorrect confirmation makes no change. After writing, the CLI verifies the reported mode. Some driver versions may report the full-speed mode using the `disengaged` compatibility label; the CLI accepts that label only when verifying a `full-speed` request and never sends `disengaged` as a command.

**Safety warning:** the kernel documentation warns that full-speed mode can exceed normal hardware limits. Use `fan ultra` only when you understand and accept that risk. The interface advertised `full-speed` on the tested T480s, but this mode has not been tested on all hardware or other ThinkPad models. `fan max` remains the recommended normal maximum.

### `fan auto`

Returns control to firmware with `level auto`, verifying the reported mode. If the interface already reports `auto`, it reports that firmware automatic mode is active and does not write. If `fan_control` is disabled while another mode is reported, it refuses to attempt a write that the driver has disabled.

### `fan off`

Alias for `fan auto`. It never means physically stopping the fan and never requests level 0.

## Installation

See [INSTALL.md](INSTALL.md) for Fedora setup, persistent module configuration, verification, and removal.

## Safety and scope

- Level 0 stops the fan and is never used by this CLI.
- The CLI never sends `disengaged`.
- Full-speed is available only through the explicit `ultra` command and confirmation flow described above.
- No fan-control service is installed or enabled by this project.
- The script does not disable CPU or firmware thermal protection.
- Hardware support should be verified before using manual control on an untested model.

## License

This project is distributed under the [MIT License](LICENSE).
