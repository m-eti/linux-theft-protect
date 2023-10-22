#!/bin/bash

set -euo pipefail

SCRIPT_NAME="theft-protect"

# --- Defaults ---
ACCEL_X_PATH=""
ACCEL_Y_PATH=""
SAMPLE_INTERVAL="0.2"
THRESHOLD="5"
TRIGGER_DURATION="0.5"
LOCKER_SCRIPT_PATH=""
CALIBRATION_SAMPLES="10"
READING_WINDOW_SIZE="5"
DEAD_ZONE="1"
IGNORE_LID_CLOSED="true"

# --- Runtime State ---
BASELINE_X="0"
BASELINE_Y="0"
TRIGGERED_SINCE=""
STABLE_SINCE=""
CONFIG_PATH="${XDG_CONFIG_HOME:-$HOME/.config}/theft-protect/config.ini"

# --- Sliding Window ---
declare -a WINDOW_X=()
declare -a WINDOW_Y=()
WINDOW_COUNT=0
WINDOW_IDX=0

# --- Logging ---
log() {
    local level="$1"
    shift
    logger -t "$SCRIPT_NAME" "[$level] $*"
    if [ -t 1 ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*" >&2
    fi
}

log_info()  { log "INFO"  "$@"; }
log_warn()  { log "WARN"  "$@"; }
log_error() { log "ERROR" "$@"; }
log_debug() { log "DEBUG" "$@"; }

# --- Float Math (awk) ---
float_calc() {
    awk "BEGIN { printf \"%.6f\", $1 }"
}

float_gt() {
    awk "BEGIN { exit !($1 > $2) }"
}

float_abs() {
    awk "BEGIN { v = $1; printf \"%.6f\", (v < 0) ? -v : v }"
}

# --- INI Config Parser ---
load_config() {
    local config_file="$1"

    if [ ! -f "$config_file" ]; then
        log_error "Configuration file not found: $config_file"
        exit 1
    fi

    local section=""
    local line key value

    while IFS= read -r line || [ -n "$line" ]; do
        line="${line%%#*}"
        line="$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
        [ -z "$line" ] && continue

        if [[ "$line" =~ ^\[([A-Za-z_]+)\]$ ]]; then
            section="${BASH_REMATCH[1]}"
            continue
        fi

        if [[ "$line" =~ ^([A-Za-z_]+)[[:space:]]*=[[:space:]]*(.*)$ ]]; then
            key="${BASH_REMATCH[1]}"
            value="${BASH_REMATCH[2]}"
            value="$(echo "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

            case "${section}.${key}" in
                Sensor.ACCEL_X_PATH)          ACCEL_X_PATH="$value" ;;
                Sensor.ACCEL_Y_PATH)          ACCEL_Y_PATH="$value" ;;
                Daemon.SAMPLE_INTERVAL_SECONDS) SAMPLE_INTERVAL="$value" ;;
                Daemon.SENSITIVITY_THRESHOLD) THRESHOLD="$value" ;;
                Daemon.TRIGGER_DURATION_SECONDS) TRIGGER_DURATION="$value" ;;
                Daemon.LOCKER_SCRIPT_PATH)    LOCKER_SCRIPT_PATH="$value" ;;
                Daemon.CALIBRATION_SAMPLES)   CALIBRATION_SAMPLES="$value" ;;
                Daemon.READING_WINDOW_SIZE)   READING_WINDOW_SIZE="$value" ;;
                Daemon.DEAD_ZONE)             DEAD_ZONE="$value" ;;
                Daemon.IGNORE_LID_CLOSED)     IGNORE_LID_CLOSED="$value" ;;
            esac
        fi
    done < "$config_file"

    # Expand $HOME in locker script path
    LOCKER_SCRIPT_PATH="${LOCKER_SCRIPT_PATH//\$HOME/$HOME}"

    log_info "Configuration loaded."
}

# --- Accelerometer Auto-Detection ---
auto_detect_accelerometer() {
    local device_dir name_file
    for name_file in /sys/bus/iio/devices/iio:device*/name; do
        [ -f "$name_file" ] || continue
        device_dir="$(dirname "$name_file")"
        if grep -qi 'accel' "$name_file" 2>/dev/null; then
            local x_raw="$device_dir/in_accel_x_raw"
            local y_raw="$device_dir/in_accel_y_raw"
            if [ -r "$x_raw" ] && [ -r "$y_raw" ]; then
                ACCEL_X_PATH="$x_raw"
                ACCEL_Y_PATH="$y_raw"
                log_info "Auto-detected accelerometer: X=$ACCEL_X_PATH, Y=$ACCEL_Y_PATH"
                return 0
            fi
        fi
    done
    return 1
}

# --- Sensor I/O ---
read_sensor() {
    local path="$1"
    if [ -r "$path" ]; then
        local val
        val=$(cat "$path" 2>/dev/null) && echo "$val" && return 0
    fi
    return 1
}

# --- Lid Detection ---
is_lid_closed() {
    if [ "$IGNORE_LID_CLOSED" != "true" ]; then
        return 1
    fi

    local lid_path
    for lid_path in /proc/acpi/button/lid/*/state; do
        [ -f "$lid_path" ] || continue
        if grep -qi 'closed' "$lid_path" 2>/dev/null; then
            return 0
        fi
    done
    return 1
}

# --- Sliding Window ---
window_init() {
    WINDOW_X=()
    WINDOW_Y=()
    WINDOW_COUNT=0
    WINDOW_IDX=0
    local i
    for ((i = 0; i < READING_WINDOW_SIZE; i++)); do
        WINDOW_X+=("0")
        WINDOW_Y+=("0")
    done
}

window_add() {
    WINDOW_X[$WINDOW_IDX]="$1"
    WINDOW_Y[$WINDOW_IDX]="$2"
    WINDOW_IDX=$(( (WINDOW_IDX + 1) % READING_WINDOW_SIZE ))
    if (( WINDOW_COUNT < READING_WINDOW_SIZE )); then
        WINDOW_COUNT=$((WINDOW_COUNT + 1))
    fi
}

window_average() {
    local axis="$1"
    local sum="0"
    local i val

    for ((i = 0; i < WINDOW_COUNT; i++)); do
        if [ "$axis" = "x" ]; then
            val="${WINDOW_X[$i]}"
        else
            val="${WINDOW_Y[$i]}"
        fi
        sum=$(float_calc "$sum + $val")
    done

    float_calc "$sum / $WINDOW_COUNT"
}

# --- Calibration ---
calibrate() {
    log_info "Calibrating... Please keep the laptop perfectly still."

    local -a samples_x=()
    local -a samples_y=()
    local i x y

    for ((i = 0; i < CALIBRATION_SAMPLES; i++)); do
        x=$(read_sensor "$ACCEL_X_PATH") || x=""
        y=$(read_sensor "$ACCEL_Y_PATH") || y=""

        if [ -n "$x" ] && [ -n "$y" ]; then
            samples_x+=("$x")
            samples_y+=("$y")
        fi
        sleep 0.1
    done

    local count=${#samples_x[@]}
    if (( count < 3 )); then
        log_error "Calibration failed. Too few valid sensor readings ($count). Exiting."
        exit 1
    fi

    # Sort, trim min/max, average remaining
    local trimmed_avg_x trimmed_avg_y
    trimmed_avg_x=$(printf '%s\n' "${samples_x[@]}" | sort -n | sed '1d;$d' | awk '{s+=$1; n++} END {printf "%.6f", s/n}')
    trimmed_avg_y=$(printf '%s\n' "${samples_y[@]}" | sort -n | sed '1d;$d' | awk '{s+=$1; n++} END {printf "%.6f", s/n}')

    BASELINE_X="$trimmed_avg_x"
    BASELINE_Y="$trimmed_avg_y"

    log_info "Calibration complete. Baseline (X, Y): ($BASELINE_X, $BASELINE_Y) from $count samples"
}

# --- Screen Lock ---
lock_screen() {
    log_info "Threshold exceeded. Executing lock screen script."
    if [ -x "$LOCKER_SCRIPT_PATH" ]; then
        if "$LOCKER_SCRIPT_PATH"; then
            log_info "Screen lock command sent."
        else
            log_error "Locker script exited with error."
        fi
    else
        log_error "Locker script not found or not executable: $LOCKER_SCRIPT_PATH"
    fi
}

# --- Get Epoch Time (float) ---
now() {
    date '+%s.%N'
}

# --- Main Loop ---
run() {
    calibrate
    window_init
    STABLE_SINCE=$(now)

    log_info "Entering main monitoring loop."

    while true; do
        # Lid check
        if is_lid_closed; then
            log_debug "Lid is closed. Suppressing movement detection."
            sleep "$SAMPLE_INTERVAL"
            continue
        fi

        # Read sensors
        local current_x current_y
        current_x=$(read_sensor "$ACCEL_X_PATH") || { sleep "$SAMPLE_INTERVAL"; continue; }
        current_y=$(read_sensor "$ACCEL_Y_PATH") || { sleep "$SAMPLE_INTERVAL"; continue; }

        # Update sliding window
        window_add "$current_x" "$current_y"

        # Smoothed averages
        local smooth_x smooth_y
        smooth_x=$(window_average "x")
        smooth_y=$(window_average "y")

        # Delta from baseline
        local delta_x delta_y
        delta_x=$(float_abs "$smooth_x - $BASELINE_X")
        delta_y=$(float_abs "$smooth_y - $BASELINE_Y")

        # Movement magnitude (with dead zone)
        local magnitude
        magnitude=$(awk "BEGIN {
            mag = $delta_x + $delta_y - $DEAD_ZONE
            printf \"%.6f\", (mag > 0) ? mag : 0
        }")

        # Threshold check
        if float_gt "$magnitude" "$THRESHOLD"; then
            STABLE_SINCE=""

            if [ -z "$TRIGGERED_SINCE" ]; then
                TRIGGERED_SINCE=$(now)
                log_warn "Movement detected. Magnitude: $magnitude. Starting timer."
            fi

            local elapsed
            elapsed=$(awk "BEGIN { printf \"%.6f\", $(now) - $TRIGGERED_SINCE }")

            if float_gt "$elapsed" "$TRIGGER_DURATION"; then
                lock_screen
                log_info "Service will pause for 60 seconds after locking."
                sleep 60
                calibrate
                window_init
                TRIGGERED_SINCE=""
                STABLE_SINCE=$(now)
            fi
        else
            # No movement
            if [ -n "$TRIGGERED_SINCE" ]; then
                log_info "Movement stopped. Resetting trigger timer."
                TRIGGERED_SINCE=""
            fi

            if [ -z "$STABLE_SINCE" ]; then
                STABLE_SINCE=$(now)
            else
                local stable_elapsed
                stable_elapsed=$(awk "BEGIN { printf \"%.6f\", $(now) - $STABLE_SINCE }")
                if float_gt "$stable_elapsed" "5.0"; then
                    # Baseline drift correction (EMA, alpha=0.01)
                    BASELINE_X=$(awk "BEGIN { printf \"%.6f\", $BASELINE_X * 0.99 + $smooth_x * 0.01 }")
                    BASELINE_Y=$(awk "BEGIN { printf \"%.6f\", $BASELINE_Y * 0.99 + $smooth_y * 0.01 }")
                fi
            fi
        fi

        sleep "$SAMPLE_INTERVAL"
    done
}

# --- Entry Point ---
main() {
    log_info "Starting $SCRIPT_NAME daemon."

    # Check dependencies
    for cmd in awk date cat sort grep logger; do
        if ! command -v "$cmd" &>/dev/null; then
            log_error "Required command not found: $cmd"
            exit 1
        fi
    done

    load_config "$CONFIG_PATH"

    # Resolve sensor paths
    if [ -z "$ACCEL_X_PATH" ] || [ -z "$ACCEL_Y_PATH" ] || [ ! -r "$ACCEL_X_PATH" ]; then
        log_info "Sensor paths not configured or not found. Attempting auto-detection..."
        if ! auto_detect_accelerometer; then
            log_error "Could not auto-detect accelerometer. Please configure ACCEL_X_PATH and ACCEL_Y_PATH in $CONFIG_PATH"
            exit 1
        fi
    fi

    # Validate locker script
    if [ -z "$LOCKER_SCRIPT_PATH" ] || [ ! -f "$LOCKER_SCRIPT_PATH" ]; then
        log_error "Locker script not found: $LOCKER_SCRIPT_PATH"
        exit 1
    fi

    run
}

main "$@"
