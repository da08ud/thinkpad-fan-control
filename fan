#!/usr/bin/env bash
# Safe ThinkPad fan CLI for thinkpad_acpi.
# No fan-control service is started by this script.

set -u
set -o pipefail

PROC_FAN=/proc/acpi/ibm/fan
MODULE_PARAM=/sys/module/thinkpad_acpi/parameters/fan_control

error() { printf 'fan: %s\n' "$*" >&2; }

find_hwmon() {
    local d name
    for d in /sys/class/hwmon/hwmon*; do
        [[ -r "$d/name" ]] || continue
        IFS= read -r name < "$d/name" || continue
        if [[ "$name" == thinkpad ]]; then
            printf '%s\n' "$d"
            return 0
        fi
    done
    return 1
}

read_value() {
    local file=$1 value
    if [[ -r "$file" ]]; then
        IFS= read -r value < "$file" || value=unavailable
        printf '%s' "$value"
    else
        printf 'unavailable'
    fi
}

temp_c() {
    local file=$1 value
    if [[ -r "$file" ]] && IFS= read -r value < "$file" && [[ "$value" =~ ^-?[0-9]+$ ]]; then
        awk -v t="$value" 'BEGIN { printf "%.1f C", t / 1000 }'
    else
        printf 'unavailable'
    fi
}

fan_level() {
    sed -n 's/^level:[[:space:]]*//p' <<< "$1" | head -n1
}

show_service_state() {
    local unit=$1 output rc
    output=$(systemctl is-active "$unit" 2>&1)
    rc=$?
    case "$output" in
        active|inactive|failed|activating|deactivating|reloading|maintenance)
            printf '%s=%s' "$unit" "$output"
            ;;
        unknown|not-found)
            printf '%s=not-found' "$unit"
            ;;
        *)
            if [[ -n "$output" ]]; then
                printf '%s=error(exit %s): %s' "$unit" "$rc" "$output"
            else
                printf '%s=error(exit %s; no status returned)' "$unit" "$rc"
            fi
            ;;
    esac
}

status() {
    local fan_report level rpm hwmon param d name f label label_file raw package=unavailable
    local hottest_raw= core_list= sensor_count=0 sensor_value unit

    if [[ -r "$PROC_FAN" ]]; then
        fan_report=$(<"$PROC_FAN")
        level=$(fan_level "$fan_report")
        rpm=$(sed -n 's/^speed:[[:space:]]*//p' <<< "$fan_report" | head -n1)
        printf 'Fan mode: %s\n' "${level:-unknown}"
        printf 'Fan RPM: %s\n' "${rpm:-unavailable}"
        sed -n 's/^status:[[:space:]]*/Fan status: /p' <<< "$fan_report" | head -n1
    else
        fan_report=
        printf 'Fan interface: unavailable (%s)\n' "$PROC_FAN"
    fi

    param=$(read_value "$MODULE_PARAM")
    printf 'thinkpad_acpi fan_control: %s\n' "$param"
    hwmon=$(find_hwmon 2>/dev/null || true)
    if [[ -n "$hwmon" ]]; then
        label=$(read_value "$hwmon/temp1_label")
        [[ "$label" == unavailable ]] && label='ThinkPad CPU'
        printf '%s sensor: %s\n' "$label" "$(temp_c "$hwmon/temp1_input")"
        if [[ -r "$hwmon/pwm1_enable" ]]; then
            printf 'ThinkPad PWM mode: %s (0=offline, 1=manual, 2=firmware auto)\n' "$(read_value "$hwmon/pwm1_enable")"
        fi
    else
        printf 'ThinkPad hwmon: unavailable\n'
    fi

    for d in /sys/class/hwmon/hwmon*; do
        [[ -r "$d/name" ]] || continue
        IFS= read -r name < "$d/name" || continue
        [[ "$name" == coretemp ]] || continue

        for f in "$d"/temp*_input; do
            [[ -r "$f" ]] || continue
            ((sensor_count += 1))
            raw=$(read_value "$f")
            label_file=${f%_input}_label
            label=$(read_value "$label_file")
            [[ "$label" == unavailable ]] && label=${f##*/}
            sensor_value=$(temp_c "$f")
            printf 'coretemp %s: %s\n' "$label" "$sensor_value"

            if [[ "$label" == Package* ]]; then
                package=$sensor_value
            elif [[ "$label" == Core* && "$raw" =~ ^-?[0-9]+$ ]]; then
                if [[ -z "$hottest_raw" ]] || (( raw > hottest_raw )); then hottest_raw=$raw; fi
                if [[ -n "$core_list" ]]; then core_list+=', '; fi
                core_list+="$label=$sensor_value"
            fi
        done
        break
    done

    if (( sensor_count == 0 )); then
        printf 'coretemp sensors: unavailable\n'
    fi
    printf 'CPU package: %s\n' "$package"
    if [[ -n "$core_list" && -n "$hottest_raw" ]]; then
        printf 'CPU cores: %s\n' "$core_list"
        printf 'Hottest CPU core: %s\n' "$(awk -v t="$hottest_raw" 'BEGIN { printf "%.1f C", t / 1000 }')"
    else
        printf 'CPU cores: unavailable\n'
    fi

    printf 'Fan-management services: '
    for unit in thinkfan.service fancontrol.service; do
        show_service_state "$unit"
        printf ' '
    done
    printf '\n'
}

require_control() {
    local enabled
    [[ -r "$MODULE_PARAM" ]] || { error 'thinkpad_acpi is not loaded; no fan write attempted.'; return 1; }
    enabled=$(read_value "$MODULE_PARAM")
    if [[ "$enabled" != Y && "$enabled" != 1 ]]; then
        error "manual fan control is disabled in the running module (fan_control=$enabled); no fan write attempted. Reboot is required to apply the configured option."
        return 1
    fi
    [[ -r "$PROC_FAN" ]] || { error "fan interface is unavailable: $PROC_FAN; no fan write attempted."; return 1; }
}

write_level() {
    local level=$1 report actual

    # Level 0 is never accepted. Full-speed is reachable only through ultra_mode.
    case "$level" in
        7|auto|full-speed) ;;
        *) error "unsupported internal request '$level'; only level 7, auto, and confirmed full-speed are allowed."; return 2 ;;
    esac

    require_control || return 1
    if (( EUID != 0 )); then
        command -v sudo >/dev/null 2>&1 || { error 'sudo is required to write the fan interface.'; return 1; }
        if ! printf 'level %s\n' "$level" | sudo tee "$PROC_FAN" >/dev/null; then
            error "kernel write for level '$level' failed."
            return 1
        fi
    else
        if ! printf 'level %s\n' "$level" > "$PROC_FAN"; then
            error "kernel write for level '$level' failed."
            return 1
        fi
    fi

    report=$(<"$PROC_FAN")
    actual=$(fan_level "$report")
    case "$level:$actual" in
        full-speed:full-speed|full-speed:disengaged|7:7|auto:auto) ;;
        *)
        error "requested '$level' but the interface reports '${actual:-unknown}'; fan mode is not verified."
        printf '%s\n' "$report"
        return 1
        ;;
    esac
    if [[ "$level" == full-speed && "$actual" == disengaged ]]; then
        printf 'Fan mode verified: full-speed (interface reports its disengaged alias)\n'
    else
        printf 'Fan mode verified: %s\n' "$actual"
    fi
    sed -n 's/^speed:[[:space:]]*/Fan RPM: /p' <<< "$report" | head -n1
}

restore_auto() {
    local report current enabled
    [[ -r "$PROC_FAN" ]] || { error "fan interface is unavailable: $PROC_FAN; no write attempted."; return 1; }
    report=$(<"$PROC_FAN")
    current=$(fan_level "$report")
    enabled=$(read_value "$MODULE_PARAM")

    # If already in firmware auto, this is a verified no-op. With fan_control=N,
    # do not try a write: the driver has disabled control operations.
    if [[ "$current" == auto ]]; then
        printf 'Firmware automatic mode is already active; no write needed.\n'
        return 0
    fi
    if [[ "$enabled" != Y && "$enabled" != 1 ]]; then
        error "fan mode is '${current:-unknown}' while fan_control=$enabled; driver fan writes are disabled, so automatic mode cannot be requested safely. No write attempted."
        return 1
    fi
    write_level auto
}

manual_mode() {
    local report current enabled
    [[ -r "$MODULE_PARAM" ]] || { error 'thinkpad_acpi is not loaded; no fan write attempted.'; return 1; }
    enabled=$(read_value "$MODULE_PARAM")
    if [[ "$enabled" != Y && "$enabled" != 1 ]]; then
        error "manual fan control is disabled in the running module (fan_control=$enabled); no fan write attempted."
        return 1
    fi
    [[ -r "$PROC_FAN" ]] || { error "fan interface is unavailable: $PROC_FAN; no fan write attempted."; return 1; }
    report=$(<"$PROC_FAN")
    current=$(fan_level "$report")
    case "$current" in
        [1-7])
            printf 'Manual fan level %s is already active; leaving it unchanged.\n' "$current"
            ;;
        auto)
            error 'firmware is selecting the fan level. The interface does not expose that speed as a numeric level; refusing to guess or change speed.'
            return 2
            ;;
        *)
            error "cannot safely confirm a normal manual level (reported '${current:-unknown}'); no write attempted."
            return 2
            ;;
    esac
}

ultra_mode() {
    local report confirmation
    require_control || return 1
    report=$(<"$PROC_FAN")
    if ! grep -Eq '^commands:[[:space:]]*level <level> .*full-speed' <<< "$report"; then
        error 'the live fan interface does not advertise full-speed support; no change made.'
        return 1
    fi
    if [[ ! -t 0 ]]; then
        error 'ultra mode requires an interactive terminal for its confirmation; no change made.'
        return 2
    fi

    printf '%s\n' 'WARNING: Full-speed may exceed normal hardware limits. Use only if you accept that risk.' >&2
    printf 'Type ULTRA exactly to continue: ' >&2
    if ! IFS= read -r confirmation; then
        error 'confirmation was not received; no change made.'
        return 2
    fi
    if [[ "$confirmation" != ULTRA ]]; then
        error 'confirmation did not match ULTRA; no change made.'
        return 2
    fi

    write_level full-speed
}

usage() {
    cat <<'EOF'
Usage: fan {status|manual|max|ultra|auto|off}
  status  Show fan state, RPM, labeled temperatures, and service states.
  manual  Confirm a numeric manual level; refuses to guess while in firmware auto.
  max     Request level 7, the documented highest recommended normal level.
  ultra   Request full-speed after warning and exact ULTRA confirmation.
  auto    Return control to firmware, or confirm firmware auto is already active.
  off     Alias for auto; it never turns the physical fan off.
EOF
}

if (( $# != 1 )); then usage >&2; exit 2; fi
case "$1" in
    status) status ;;
    manual) manual_mode ;;
    max) write_level 7 ;;
    ultra) ultra_mode ;;
    auto|off) restore_auto ;;
    -h|--help|help) usage ;;
    *) error "unknown command: $1"; usage >&2; exit 2 ;;
esac
