#!/bin/sh

# Update package list and install required packages
opkg update
opkg install nano curl

# Create the Wi-Fi control script
cat << 'EOF' > /etc/config/wifi_control.sh
#!/bin/sh

# Time intervals (in seconds)
CHECK_INTERVAL=300  # How often to wake up and check
WAKE_DURATION=20    # How long to keep Wi-Fi on during the check

ACTIVE_MANAGEMENT=0

turn_on_wifi() {
    wifi up
    echo "Wi-Fi turned on due to active management."
}


monitor_access() {
    while true; do
        # Check for active SSH sessions
        if pgrep dropbear > /dev/null || pgrep sshd > /dev/null; then
            ACTIVE_MANAGEMENT=1
            turn_on_wifi
        else
            # Check for active web interface access
            if netstat -tn | grep ':80\|:443' | grep ESTABLISHED > /dev/null; then
                ACTIVE_MANAGEMENT=1
                turn_on_wifi
            else
                ACTIVE_MANAGEMENT=0
            fi
        fi

        # Sleep for a short time before checking again
        sleep 10
    done
}

monitor_access &

while true; do
    if [ "$ACTIVE_MANAGEMENT" -eq 0 ]; then
        wifi up

        sleep $WAKE_DURATION

        connected_devices=$(iw dev wlan0 station dump | grep Station | wc -l)

        if [ "$connected_devices" -eq 0 ]; then
            wifi down
        else
            echo "Devices connected. Keeping Wi-Fi on."
        fi

        sleep $((CHECK_INTERVAL - WAKE_DURATION))
    else
        # If someone is actively managing the router, skip the periodic check
        echo "Active management detected. Skipping periodic Wi-Fi check."
        sleep 10
    fi
done
EOF

chmod +x /etc/config/wifi_control.sh

cat << 'EOF' >> /etc/rc.local
/etc/config/wifi_control.sh &
EOF

echo "Setup complete! Rebooting the router..."
reboot