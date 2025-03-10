#!/bin/sh

LOG_FILE="/etc/config/wifi_control.log"

log_message() {
    echo "$(date): $1" >> "$LOG_FILE"
}

> "$LOG_FILE"

log_message "Starting installation process..."

if opkg update >> "$LOG_FILE" 2>&1; then
    log_message "Package list updated successfully."
else
    log_message "ERROR: Failed to update package list."
    exit 1
fi

if opkg install tcpdump >> "$LOG_FILE" 2>&1; then
    log_message "tcpdump installed successfully."
else
    log_message "ERROR: Failed to install tcpdump."
    exit 1
fi

log_message "Creating new Wi-Fi control script..."
cat << 'EOF' > /etc/config/wifi_control.sh
#!/bin/sh

LOG_FILE="/etc/config/wifi_control.log"

log_message() {
    echo "$(date): $1" >> "$LOG_FILE"
}

CHECK_INTERVAL=15
WAKE_DURATION=60
BOOT_DURATION=120

turn_on_wifi() {
    wifi up
    log_message "Wi-Fi turned on."
}

turn_off_wifi() {
    wifi down
    log_message "Wi-Fi turned off."
}

log_message "Router reboot detected. Keeping Wi-Fi on for $BOOT_DURATION seconds..."
turn_on_wifi
sleep $BOOT_DURATION

while true; do
    connected_devices=$(iw dev wlan0 station dump | grep Station | wc -l)

    if [ "$connected_devices" -gt 0 ]; then
        log_message "Devices connected. Keeping Wi-Fi on."
        turn_on_wifi
        sleep $WAKE_DURATION
    else
        probe_requests=$(tcpdump -i wlan0 -c 1 -e type mgt subtype probe-req 2>/dev/null | awk '/Probe Request/ {print $2, $10}')
        
        if [ -n "$probe_requests" ]; then
            log_message "Probe request detected from $probe_requests. Turning on Wi-Fi."
            turn_on_wifi
            sleep $WAKE_DURATION
        else
            log_message "No probe requests or connected devices. Turning off Wi-Fi."
            turn_off_wifi
        fi
    fi
    
    sleep $CHECK_INTERVAL
done
EOF

log_message "Making the script executable..."
if chmod +x /etc/config/wifi_control.sh >> "$LOG_FILE" 2>&1; then
    log_message "Script made executable successfully."
else
    log_message "ERROR: Failed to make script executable."
    exit 1
fi

if grep -q "wifi_control.sh" /etc/rc.local; then
    log_message "Old script entry found in /etc/rc.local. Deleting it..."
    if sed -i '/wifi_control.sh/d' /etc/rc.local >> "$LOG_FILE" 2>&1; then
        log_message "Old script entry removed successfully."
    else
        log_message "ERROR: Failed to remove old script entry."
        exit 1
    fi
fi

log_message "Adding the new script to startup..."
if sed -i '/exit 0/i /etc/config/wifi_control.sh &' /etc/rc.local >> "$LOG_FILE" 2>&1; then
    log_message "Script added to startup successfully."
else
    log_message "ERROR: Failed to add script to startup."
    exit 1
fi

log_message "Setup complete! Rebooting the router..."
reboot
