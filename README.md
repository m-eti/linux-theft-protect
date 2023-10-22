# Linux Theft Protect

A lightweight anti-theft daemon for Linux laptops equipped with an accelerometer. Written entirely in **bash** with no Python dependency. Monitors for unexpected movement and automatically locks the screen to protect your data.

## Features

- **Movement Detection**: Uses the built-in accelerometer via sysfs to detect physical movement.
- **Automatic Screen Lock**: Locks the screen when sustained movement exceeds a configurable threshold.
- **Zero Python Dependency**: Pure bash + awk -- runs on virtually any Linux system.
- **User-Level Install**: No root/sudo required. Installs entirely within your home directory.
- **Systemd User Service**: Starts automatically on graphical login, managed via `systemctl --user`.
- **Desktop Environment Agnostic**: Uses `loginctl` to lock the screen (GNOME, KDE, XFCE, etc.).
- **Configurable**: Adjust sensitivity, sample rate, trigger duration, and more.

## How It Works

1. **Calibration**: On startup, takes baseline readings from the accelerometer (sorted, trimmed, averaged).
2. **Monitoring**: Continuously reads accelerometer X/Y values, smoothed via a sliding window average.
3. **Triggering**: If movement magnitude exceeds `SENSITIVITY_THRESHOLD` for `TRIGGER_DURATION_SECONDS`, it is considered a theft event.
4. **Locking**: Executes `lock-screen.sh` which uses `loginctl lock-session` on the active graphical session.
5. **Reset**: After a lock event, pauses for 60 seconds then re-calibrates to the new position.
6. **Drift Correction**: During stable periods (>5s), slowly adjusts the baseline via exponential moving average to account for thermal/positional drift.

## Prerequisites

- A Linux laptop with a built-in accelerometer exposing readings via sysfs (`/sys/bus/iio/devices/`).
- `systemd` as init system (with user instance support).
- Standard tools: `bash`, `awk`, `cat`, `sort`, `grep`, `logger`, `loginctl`.

### Finding Your Accelerometer Path

```bash
find /sys/bus/iio/devices/ -name "in_accel_x_raw"
find /sys/bus/iio/devices/ -name "in_accel_y_raw"
```

Or let the daemon auto-detect it (default behavior when paths are empty in config).

## Installation

1. Clone the repository:
    ```bash
    git clone https://github.com/m-eti/linux-theft-protect.git
    cd linux-theft-protect
    ```

2. Run the installation script (**no root needed**):
    ```bash
    ./install.sh
    ```

The script will:
- Install the daemon and lock script to `~/.local/bin/`
- Install the configuration to `~/.config/theft-protect/config.ini`
- Install and enable the systemd user service

## Configuration

Edit the configuration file after installation:

```bash
nano ~/.config/theft-protect/config.ini
```

Key settings:

| Setting | Default | Description |
|---|---|---|
| `ACCEL_X_PATH` / `ACCEL_Y_PATH` | (auto-detect) | Sensor file paths |
| `SENSITIVITY_THRESHOLD` | 5 | Lower = more sensitive |
| `TRIGGER_DURATION_SECONDS` | 0.5 | Sustained movement time to trigger |
| `SAMPLE_INTERVAL_SECONDS` | 0.2 | Polling rate (seconds) |
| `DEAD_ZONE` | 1 | Noise filter (subtract from magnitude) |
| `IGNORE_LID_CLOSED` | true | Skip detection when lid is closed |

## Usage

All commands are user-level (no sudo):

```bash
# Start the service
systemctl --user start theft-protect

# Stop the service
systemctl --user stop theft-protect

# Check status
systemctl --user status theft-protect

# View logs
journalctl --user -u theft-protect -f

# Enable on login (done automatically by installer)
systemctl --user enable theft-protect

# Disable on login
systemctl --user disable theft-protect
```

## Uninstallation

```bash
./uninstall.sh
```

The script will stop the service, remove installed files, and optionally remove the configuration directory.
