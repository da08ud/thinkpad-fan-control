# Installation and setup

These instructions target Fedora 44. The CLI is a Bash script and uses the native `thinkpad_acpi` interface; it does not install `thinkfan` or enable a service.

## 1. Check the hardware interface

Confirm the driver and fan interface exist:

```bash
lsmod | grep '^thinkpad_acpi'
cat /proc/acpi/ibm/fan
```

Do not assume every ThinkPad reports or supports the same fan modes. This project has been tested on a Lenovo ThinkPad T480s only.

## 2. Install the CLI

From this repository directory:

```bash
sudo install -D -m 0755 fan /usr/local/bin/fan
```

Open a new terminal or refresh the command cache, then check resolution:

```bash
command -v fan
fan --help
```

If a shell function or alias named `fan` takes precedence, remove that conflicting definition from the shell startup file and start a new shell. This repository does not edit shell configuration.

## 3. Enable the driver's manual-control capability

Manual writes require the `thinkpad_acpi` module option `fan_control=1`. Inspect existing module configuration before adding an option:

```bash
grep -R -n 'thinkpad_acpi\|fan_control' /etc/modprobe.d /etc/modules-load.d 2>/dev/null
```

Back up any existing file that you plan to edit. Preserve unrelated settings and avoid adding conflicting `thinkpad_acpi` options. Add this option to the appropriate modprobe configuration:

```text
options thinkpad_acpi fan_control=1
```

For example, if no existing file contains a `thinkpad_acpi` option, create a dedicated file:

```bash
printf '%s\n' 'options thinkpad_acpi fan_control=1' | sudo tee /etc/modprobe.d/thinkpad-fan-control.conf
```

The setting applies when the module is next loaded. Do not unload the live module on a running laptop. Reboot only when ready, then verify:

```bash
cat /sys/module/thinkpad_acpi/parameters/fan_control
cat /proc/acpi/ibm/fan
```

The parameter should report `Y`, and the fan interface should show the commands available on that driver/model. If the parameter remains disabled, investigate module-load timing and initramfs configuration for that Fedora installation before proceeding.

## 4. Use the CLI

```bash
fan status
fan max
fan auto
```

`fan max` requests normal level 7, not level 0 or full-speed. `fan auto` returns control to the embedded controller. `fan off` is an alias for `fan auto` and does not stop the physical fan.

`fan ultra` displays a warning because full-speed may exceed normal hardware limits. It proceeds only if the live interface advertises full-speed and the user types exactly `ULTRA` in an interactive terminal. Full-speed is advertised by the tested T480s interface, but has not been tested across other hardware. Prefer `fan max` for the normal maximum.

`fan manual` only confirms an already selected numeric manual level. It refuses to infer a manual level from firmware auto because the native interface does not reveal a numeric equivalent that can safely preserve the current speed.

## Removal

Remove the installed command:

```bash
sudo rm /usr/local/bin/fan
```

If you added `/etc/modprobe.d/thinkpad-fan-control.conf` specifically for this tool, remove that file to stop requesting the option on future module loads:

```bash
sudo rm /etc/modprobe.d/thinkpad-fan-control.conf
```

If instead you edited an existing modprobe file, restore only the backed-up version or remove only the `fan_control=1` option you added. Reboot for a module option change to take effect. Removal does not install, stop, or disable any fan-control service.

## Troubleshooting

- If control commands report `fan_control=N`, the module is still running without manual-control support. The CLI will not reload it; apply the persistent option at the next planned reboot.
- If a mode is rejected or does not appear in the interface readback, do not repeat the command blindly. Check the interface's advertised commands and the model-specific driver behavior.
- If `fan status` reports systemd access errors, that does not establish that a service is inactive. Check the system manager from a normal system terminal.
