#!/bin/sh

echo "Updating package list and installing required packages..."
opkg update
opkg install tcpdump

echo "Creating new Wi-Fi control script..."
cat << 'EOF' > /etc/config/wifi_control.sh
#!/bin/sh

# Time intervals (in seconds)
CHECK_INTERVAL=15  # How often to check for probe requests (e.g., every 15 seconds)
WAKE_DURATION=60   # How long to keep Wi-Fi on after a probe request is detected (e.g., 60 seconds)

turn_on_wifi() {
    wifi up
    echo "Wi-Fi turned on due to probe request or connected devices."
}

while true; do
    # Check for connected devices
    connected_devices=$(iw dev wlan0 station dump | grep Station | wc -l)

    if [ "$connected_devices" -gt 0 ]; then
        turn_on_wifi
        sleep $WAKE_DURATION
    else
        probe_requests=$(tcpdump -i wlan0 -c 1 -e type mgt subtype probe-req 2>/dev/null | wc -l)

        if [ "$probe_requests" -gt 0 ]; then
            turn_on_wifi
            sleep $WAKE_DURATION
        else
            wifi down
        fi
    fi
    
    sleep $CHECK_INTERVAL
done
EOF

echo "Making the script executable..."
chmod +x /etc/config/wifi_control.sh

if grep -q "wifi_control.sh" /etc/rc.local; then
    echo "Old script entry found in /etc/rc.local. Deleting it..."
    sed -i '/wifi_control.sh/d' /etc/rc.local
fi

echo "Adding the new script to startup..."
sed -i '/exit 0/i /etc/config/wifi_control.sh &' /etc/rc.local

echo "Setup complete! Rebooting the router..."
reboot
