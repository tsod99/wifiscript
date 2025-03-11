#!/bin/sh

LOG_FILE="/etc/config/wifi_control.log"
MAX_LOG_SIZE=$((1 * 1024 * 1024))  # 1 MB in bytes

log_message() {
    echo "$(date): $1" >> "$LOG_FILE"
    echo "$1"
    
    log_size=$(wc -c < "$LOG_FILE" 2>/dev/null)
    if [ "$log_size" -gt "$MAX_LOG_SIZE" ]; then
        > "$LOG_FILE"
        log_message "Log file cleared to prevent excessive growth."
    fi
}

> "$LOG_FILE"

log_message "Starting installation process..."

log_message "Installing required packages..."
opkg update >> "$LOG_FILE" 2>&1
opkg install iw tcpdump >> "$LOG_FILE" 2>&1

log_message "Ensuring Wi-Fi radios are enabled..."
uci set wireless.radio0.disabled='0' 2>/dev/null
uci set wireless.radio1.disabled='0' 2>/dev/null
uci commit wireless
wifi reload

log_message "Bringing up Wi-Fi radios..."
wifi
sleep 5

log_message "Checking for Wi-Fi interfaces..."
INTERFACES=$(iw dev | grep Interface | awk '{print $2}')

if [ -z "$INTERFACES" ]; then
    log_message "No Wi-Fi interfaces detected. Attempting to install drivers..."
    opkg update >> "$LOG_FILE" 2>&1
    opkg install kmod-mt76 >> "$LOG_FILE" 2>&1
    sleep 5
    wifi reload
    sleep 5
    INTERFACES=$(iw dev | grep Interface | awk '{print $2}')
    if [ -z "$INTERFACES" ]; then
        log_message "ERROR: No Wi-Fi interfaces found even after driver installation. Exiting."
    fi
else
    log_message "Wi-Fi interfaces found: $INTERFACES"
fi


if ping -c 1 8.8.8.8 >/dev/null 2>&1; then
    log_message "Internet connection available. Proceeding with installation."
else
    log_message "ERROR: No internet connection. Cannot install tcpdump."
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
    
    log_size=$(wc -c < "$LOG_FILE" 2>/dev/null)
    if [ "$log_size" -gt "$MAX_LOG_SIZE" ]; then
        > "$LOG_FILE"
        log_message "Log file cleared to prevent excessive growth."
    fi
}

CHECK_INTERVAL=15
WAKE_DURATION=60  # 7 minutes
BOOT_DURATION=420  # 7 minutes

turn_on_wifi() {
    wifi up
    log_message "Wi-Fi turned on (SSID broadcast enabled)."
}

turn_off_wifi() {
    wifi down
    log_message "Wi-Fi turned off (SSID broadcast disabled)."
}

log_message "Router reboot detected."
turn_on_wifi
sleep $BOOT_DURATION

while true; do
    INTERFACES=$(iw dev | grep Interface | awk '{print $2}')
    ACTIVE_DEVICES=0

    for iface in $INTERFACES; do
        count=$(iw dev $iface station dump | grep Station | wc -l)
        ACTIVE_DEVICES=$((ACTIVE_DEVICES + count))
    done

    if [ "$ACTIVE_DEVICES" -gt 0 ]; then
        log_message "$ACTIVE_DEVICES devices connected. Keeping Wi-Fi on."
        turn_on_wifi
        sleep $WAKE_DURATION
    else
        log_message "No connected devices. Checking for probe requests..."
        PROBE_REQUESTS=0

        for iface in $INTERFACES; do
            if timeout 15 tcpdump -i $iface -e type mgt subtype probe-req 2>/dev/null | grep -q "Probe Request"; then
                PROBE_REQUESTS=1
                break
            fi
        done

        if [ "$PROBE_REQUESTS" -eq 1 ]; then
            log_message "Probe request detected. Keeping Wi-Fi on for $WAKE_DURATION seconds."
            turn_on_wifi
            sleep $WAKE_DURATION
        else
            log_message "No probe requests detected in the last 15 seconds. Turning Wi-Fi off."
            turn_off_wifi
        fi
    fi
    sleep $CHECK_INTERVAL

done
EOF

log_message "Making the script executable..."
chmod +x /etc/config/wifi_control.sh

log_message "Using rc.local for startup..."
sed -i '/wifi_control/d' /etc/rc.local
if grep -q "exit 0" /etc/rc.local; then
    sed -i '/exit 0/i /etc/config/wifi_control.sh &' /etc/rc.local
else
    echo "/etc/config/wifi_control.sh &" >> /etc/rc.local
    echo "exit 0" >> /etc/rc.local
fi

log_message "Setup complete! Rebooting the router in 10 seconds..."
sleep 10
reboot
