# Linux Theft Protect

A simple yet effective anti-theft daemon for Linux laptops equipped with an accelerometer. This tool monitors for unexpected movement and automatically locks the screen to protect your data if the device is moved without authorization.

## Features

*   **Movement Detection**: Uses the built-in accelerometer to detect physical movement.
*   **Automatic Screen Lock**: Locks the screen when sustained movement exceeds a configurable threshold.
*   **Configurable**: Easily adjust sensitivity, sample rate, and trigger duration.
*   **Systemd Integration**: Runs as a background service, managed by `systemd`.
*   **Desktop Environment Agnostic**: Uses `loginctl` to lock the screen, which works across most modern desktop environments (GNOME, KDE, XFCE, etc.).

## How It Works

The `theft-protect-daemon.py` script runs as a background service.

1.  **Calibration**: On startup, it takes a baseline reading from the accelerometer.
2.  **Monitoring**: It continuously reads the accelerometer's X and Y axis values.
3.  **Triggering**: If the movement's magnitude surpasses a defined `SENSITIVITY_THRESHOLD` for a certain `TRIGGER_DURATION_SECONDS`, it's considered a potential theft event.
4.  **Locking**: The service executes the `lock-screen.sh` script, which uses `loginctl` to lock the current user's session.
5.  **Reset**: After a lock event, the service pauses briefly and then re-calibrates to a new "stable" position.

## Prerequisites

*   A Linux laptop with a built-in accelerometer that exposes its readings via `sysfs` (e.g., in `/sys/bus/iio/devices/`).
*   `systemd` as the init system.
*   Python 3.

### Finding Your Accelerometer Path

You need to find the file paths for your accelerometer's X and Y axes. A common location is `/sys/bus/iio/devices/iio:deviceX/`, where `X` is a number.

You can search for them using a command like this:

```bash
find /sys/bus/iio/devices/ -name "in_accel_x_raw"
find /sys/bus/iio/devices/ -name "in_accel_y_raw"
```

Once you find the paths, you will need to add them to the configuration file after installation.

## Installation

1.  Clone the repository:
    ```bash
    git clone https://github.com/m-eti/linux-theft-protect.git
    cd linux-theft-protect
    ```

2.  Run the installation script with root privileges. The script will copy files, set permissions, and enable the systemd service.
    ```bash
    sudo ./install.sh
    ```

## Configuration

After installation, you **must** edit the configuration file to match your hardware.

1.  Open the configuration file:
    ```bash
    sudo nano /etc/theft-protect/config.ini
    ```

2.  Update the `ACCEL_X_PATH` and `ACCEL_Y_PATH` with the paths you found earlier.

3.  Adjust `SENSITIVITY_THRESHOLD` and other parameters as needed. A lower threshold means more sensitivity.

4.  Start the service to apply the new configuration:
    ```bash
    sudo systemctl start theft-protect.service
    ```

## Usage

The service is managed by `systemd`.

*   **Start the service**: `sudo systemctl start theft-protect.service`
*   **Stop the service**: `sudo systemctl stop theft-protect.service`
*   **Check status and logs**: `systemctl status theft-protect.service` or `journalctl -u theft-protect.service -f`
*   **Enable on boot**: `sudo systemctl enable theft-protect.service` (done automatically by the installer)
*   **Disable on boot**: `sudo systemctl disable theft-protect.service`

## Uninstallation

To completely remove the application and its configuration, run the uninstallation script:

```bash
sudo ./uninstall.sh
```