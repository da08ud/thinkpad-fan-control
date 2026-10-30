# ThinkPad Fan Control

## Project overview

ThinkPad Fan Control is a small Bash command-line interface for inspecting and controlling the cooling fan on supported Lenovo ThinkPads. It uses the Linux `thinkpad_acpi` kernel driver and its native `/proc/acpi/ibm/fan` interface.

This is a CLI, not a background daemon. It does not continuously manage temperatures, start a fan-control service, install `thinkfan`, or activate manual control at boot. Firmware automatic control remains available through `fan auto`.

## Quick Start

See [INSTALL.md](INSTALL.md) for complete Fedora installation and setup instructions, including the persistent `fan_control=1` module option.

```bash
fan status
fan max
fan manual
fan auto
fan off
fan ultra
```

- `fan status` reads and displays the current fan mode, RPM, module parameter, available ThinkPad and CPU temperatures, and relevant service status. It does not change fan control.
- `fan max` requests level 7, the highest recommended normal level, then checks the mode reported by the driver.
- `fan manual` confirms an already selected numeric manual level without writing a new level. It refuses to guess a level when firmware reports `auto`.
- `fan auto` returns control to firmware with `level auto`. If automatic mode is already reported, it confirms that state without writing. If control writes are disabled while another level is active, it refuses an unsupported write.
- `fan off` is an alias for `fan auto`. It does **not** physically turn off the fan.
- `fan ultra` requests full-speed only if the interface advertises it and the user types exactly `ULTRA` at an interactive prompt. It prints a warning first and verifies the resulting mode.

Fan-control commands require `thinkpad_acpi` to be loaded with `fan_control=1`; regular users are prompted for sudo when a write is needed. The script does not reload the kernel module. A persistent module option applies the next time the module loads, which may require rebooting. See [INSTALL.md](INSTALL.md).

## Usage examples

Check the current state without changing it:

```bash
fan status
```

Request the normal maximum, level 7. The CLI writes `level 7` and reports whether the interface confirms level 7:

```bash
fan max
```

Return control to the firmware. `fan off` does the same thing and never sends a fan-stop command:

```bash
fan auto
fan off
```

If a numeric manual level is already selected, `fan manual` reports it and leaves it unchanged. If the interface reports firmware `auto`, the command refuses to infer or set a manual speed:

```bash
fan manual
```

### Normal maximum and ultra mode

`fan max` uses **level 7**, the kernel-documented highest recommended normal fan level. This is the recommended maximum for routine use.

`fan ultra` requests the driver's `full-speed` mode, which is distinct from normal level 7. The kernel warns that full-speed may exceed normal hardware limits. The command checks that the live interface advertises full-speed, displays its warning, and proceeds only after an interactive user types exactly `ULTRA`. Missing or incorrect confirmation makes no change.

The T480s interface checked for this project advertised full-speed. That advertisement does not prove that full-speed behavior is safe or tested on every model. Some driver versions may report full-speed as `disengaged`; the CLI accepts that spelling only as a readback alias and never sends `disengaged` as a command. This project never recommends fan level 0 or the disengaged command.

## Compatibility matrix

| Hardware or platform | Status |
|---|---|
| Lenovo ThinkPad T480s | Tested |
| Fedora 44 | Tested |
| Other ThinkPad models | Not yet verified |
| Other Linux distributions | Not yet verified |

The T480s fan interface advertised the full-speed command during inspection, but full-speed mode has not been validated across hardware. ThinkPad firmware and driver behavior vary by model; compatibility with all ThinkPads is not claimed.

## Requirements

- Linux with Bash
- A loaded `thinkpad_acpi` kernel module
- `thinkpad_acpi` loaded with `fan_control=1` for manual fan writes
- The native `/proc/acpi/ibm/fan` interface
- `sudo` for fan-control writes when the CLI is run as a regular user
- `systemctl` for service status reporting
- Standard utilities used by the script: `awk`, `grep`, `head`, and `sed`

The script discovers ThinkPad and `coretemp` hwmon devices by their names and reads labeled temperature inputs when available. `fan status` reports `thinkfan.service` and `fancontrol.service`; systemd access errors are shown as errors rather than being mistaken for inactive services.

## Installation and removal

See [INSTALL.md](INSTALL.md) for Fedora setup, persistent module configuration, verification, troubleshooting, and removal instructions. The project does not edit shell startup configuration or install or enable a fan-control service.

## Safety

- **Never use fan level 0.** Level 0 stops the fan, so this CLI does not request it.
- **Never send `disengaged`.** The CLI never uses it as a command. A driver may return it only as a compatibility label when verifying full-speed.
- **`fan ultra` requires exact interactive confirmation.** The user must type `ULTRA` after seeing the warning; the mode is never activated automatically.
- **Full-speed may exceed normal hardware limits.** Use `fan ultra` only if you understand and accept that risk. Prefer `fan max` for the recommended normal maximum.
- **Hardware and firmware behavior vary by model.** Verify the live interface and available modes on a device before using manual control. Other ThinkPad models and Linux distributions are not yet verified.
- The CLI does not disable CPU or firmware thermal protection and does not run a background fan manager.

## Roadmap

- [ ] Add automated tests for command behavior.
- [ ] Test compatibility on additional ThinkPad models.
- [ ] Improve hardware and driver diagnostics.
- [ ] Add more Linux distribution documentation.
- [ ] Improve error handling and user documentation.

## Contributing

Bug reports and pull requests are welcome. When reporting an issue, include the Linux distribution and version, kernel version, ThinkPad model, the relevant `fan status` output, and the fan interface's reported commands when available. Redact serial numbers and other personal or device-identifying information.

Users with other ThinkPad models can help by reporting which read-only fan modes and sensor information their driver advertises. Do not test level 0 or send `disengaged`; full-speed may exceed normal hardware limits. For code changes, submit a pull request with a clear description of the behavior changed and the checks performed. Do not describe untested models or distributions as compatible.

## License

This project is distributed under the [MIT License](LICENSE).
