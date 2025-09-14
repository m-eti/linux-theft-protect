#!/usr/bin/env python3

import time
import os
import subprocess
import configparser
import sys
import logging

# Setup basic logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')

class TheftProtectDaemon:
    def __init__(self, config_path='/etc/theft-protect/config.ini'):
        self.config = self.load_config(config_path)
        self.baseline_x = 0
        self.baseline_y = 0
        self.triggered_since = None

    def load_config(self, config_path):
        """Loads configuration from the INI file."""
        if not os.path.exists(config_path):
            logging.error(f"Configuration file not found at {config_path}")
            sys.exit(1)
        
        parser = configparser.ConfigParser()
        parser.read(config_path)
        
        config = {
            'accel_x_path': parser.get('Sensor', 'ACCEL_X_PATH'),
            'accel_y_path': parser.get('Sensor', 'ACCEL_Y_PATH'),
            'sample_interval': parser.getfloat('Daemon', 'SAMPLE_INTERVAL_SECONDS'),
            'threshold': parser.getint('Daemon', 'SENSITIVITY_THRESHOLD'),
            'trigger_duration': parser.getfloat('Daemon', 'TRIGGER_DURATION_SECONDS'),
            'locker_script': parser.get('Daemon', 'LOCKER_SCRIPT_PATH')
        }
        logging.info("Configuration loaded successfully.")
        return config

    def read_sensor(self, path):
        """Reads a single integer value from a sysfs file."""
        try:
            with open(path, 'r') as f:
                return int(f.read().strip())
        except (IOError, ValueError) as e:
            logging.error(f"Could not read sensor at {path}: {e}")
            return None

    def calibrate(self):
        """Sets the initial baseline sensor readings."""
        logging.info("Calibrating... Please keep the laptop perfectly still.")
        x = self.read_sensor(self.config['accel_x_path'])
        y = self.read_sensor(self.config['accel_y_path'])

        if x is None or y is None:
            logging.error("Calibration failed. Could not read initial sensor values. Exiting.")
            sys.exit(1)
            
        self.baseline_x = x
        self.baseline_y = y
        logging.info(f"Calibration complete. Baseline (X, Y): ({self.baseline_x}, {self.baseline_y})")

    def lock_screen(self):
        """Executes the external screen locker script."""
        logging.info("Threshold exceeded. Executing lock screen script.")
        try:
            subprocess.run([self.config['locker_script']], check=True)
            logging.info("Screen lock command sent.")
        except (subprocess.CalledProcessError, FileNotFoundError) as e:
            logging.error(f"Failed to execute locker script: {e}")

    def run(self):
        """Main monitoring loop."""
        self.calibrate()
        
        while True:
            current_x = self.read_sensor(self.config['accel_x_path'])
            current_y = self.read_sensor(self.config['accel_y_path'])
            
            if current_x is None or current_y is None:
                time.sleep(self.config['sample_interval'])
                continue

            # Calculate the deviation from the baseline
            delta_x = abs(current_x - self.baseline_x)
            delta_y = abs(current_y - self.baseline_y)
            
            # Use Manhattan distance for simplicity and speed
            movement_magnitude = delta_x + delta_y
            
            if movement_magnitude > self.config['threshold']:
                if self.triggered_since is None:
                    # Start the trigger timer
                    self.triggered_since = time.time()
                    logging.warning(f"Movement detected. Magnitude: {movement_magnitude}. Starting timer.")
                
                # Check if the trigger duration has been met
                if (time.time() - self.triggered_since) >= self.config['trigger_duration']:
                    self.lock_screen()
                    # Wait for a long time to prevent immediate re-locking
                    # A more advanced version could have a state machine
                    logging.info("Service will pause for 60 seconds after locking.")
                    time.sleep(60) 
                    self.calibrate() # Re-calibrate after resuming
                    self.triggered_since = None
            else:
                # If movement stops, reset the trigger timer
                if self.triggered_since is not None:
                    logging.info("Movement stopped. Resetting trigger timer.")
                    self.triggered_since = None

            time.sleep(self.config['sample_interval'])

if __name__ == "__main__":
    daemon = TheftProtectDaemon()
    daemon.run()
