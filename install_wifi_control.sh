#!/bin/sh

LOG_FILE="/etc/config/wifi_control.log"
MAX_LOG_SIZE=$((1 * 1024 * 1024))

log_message() {
    echo "$(date): $1" >> "$LOG_FILE"
    echo "$1"
    
    if [ $(stat -c%s "$LOG_FILE") -gt $MAX_LOG_SIZE ]; then
        > "$LOG_FILE"
        log_message "Log file cleared to prevent excessive growth."
    fi
}

> "$LOG_FILE"

log_message "Starting installation process..."

log_message "Ensuring Wi-Fi radios are enabled..."
if uci get wireless.radio0.disabled >/dev/null 2>&1 && [ "$(uci get wireless.radio0.disabled)" = "1" ]; then
    log_message "2.4 GHz radio is disabled. Enabling it..."
    uci set wireless.radio0.disabled='0'
fi

if uci get wireless.radio1.disabled >/dev/null 2>&1 && [ "$(uci get wireless.radio1.disabled)" = "1" ]; then
    log_message "5 GHz radio is disabled. Enabling it..."
    uci set wireless.radio1.disabled='0'
fi

if uci changes wireless >/dev/null 2>&1; then
    log_message "Committing Wi-Fi configuration changes..."
    if uci commit wireless; then
        log_message "Wi-Fi configuration committed successfully."
    else
        log_message "ERROR: Failed to commit Wi-Fi configuration."
        exit 1
    fi
fi

log_message "Bringing up Wi-Fi radios..."
if wifi; then
    log_message "Wi-Fi radios brought up successfully."
else
    log_message "ERROR: Failed to bring up Wi-Fi radios."
    exit 1
fi

if ping -c 1 8.8.8.8 >/dev/null 2>&1; then
    log_message "Internet connection available. Proceeding with installation."
else
    log_message "ERROR: No internet connection. Cannot install tcpdump."
    exit 1
fi

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
MAX_LOG_SIZE=$((1 * 1024 * 1024))

log_message() {
    echo "$(date): $1" >> "$LOG_FILE"
    echo "$1"
    
    if [ $(stat -c%s "$LOG_FILE") -gt $MAX_LOG_SIZE ]; then
        > "$LOG_FILE"
        log_message "Log file cleared to prevent excessive growth."
    fi
}

CHECK_INTERVAL=15
WAKE_DURATION=60
BOOT_DURATION=120

turn_on_wifi() {
    wifi up
    log_message "Wi-Fi turned on (SSID broadcast enabled)."
}

turn_off_wifi() {
    wifi down
    log_message "Wi-Fi turned off (SSID broadcast disabled)."
}

log_message "Router reboot detected. Keeping Wi-Fi on for $BOOT_DURATION seconds..."
turn_on_wifi
sleep $BOOT_DURATION

while true; do
    if [ "$(uci get wireless.radio0.disabled 2>/dev/null)" = "1" ]; then
        log_message "2.4 GHz Wi-Fi is currently disabled. Skipping connected devices check."
    else
        connected_devices_2g=$(iw dev wlan0 station dump | grep Station | wc -l)
    fi

    if [ "$(uci get wireless.radio1.disabled 2>/dev/null)" = "1" ]; then
        log_message "5 GHz Wi-Fi is currently disabled. Skipping connected devices check."
    else
        connected_devices_5g=$(iw dev wlan1 station dump | grep Station | wc -l)
    fi

    if [ "$connected_devices_2g" -gt 0 ] || [ "$connected_devices_5g" -gt 0 ]; then
        log_message "Devices connected. Keeping Wi-Fi on."
        turn_on_wifi
        sleep $WAKE_DURATION
    else
        probe_requests_2g=$(tcpdump -i wlan0 -c 1 -e type mgt subtype probe-req 2>/dev/null | awk '/Probe Request/ {print $2, $10}')
        probe_requests_5g=$(tcpdump -i wlan1 -c 1 -e type mgt subtype probe-req 2>/dev/null | awk '/Probe Request/ {print $2, $10}')
        
        if [ -n "$probe_requests_2g" ] || [ -n "$probe_requests_5g" ]; then
            log_message "Probe request detected. Waiting 2 seconds before turning on Wi-Fi."
            sleep 2
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
chmod +x /etc/config/wifi_control.sh

log_message "Using rc.local for startup..."
sed -i '/wifi_control.sh/d' /etc/rc.local

echo "/etc/config/wifi_control.sh &" >> /etc/rc.local

log_message "Setup complete! Rebooting the router in 10 seconds..."
sleep 10
reboot
