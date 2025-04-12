#!/bin/sh

set -e


echo "[🔧] Installing required tools..."
opkg update
opkg install iw wireless-tools coreutils-timeout


echo "[📡] Setting up WiFi (SSID: On Demand WiFi, Password: ondemand123)..."
uci set wireless.@wifi-iface[0].ssid='On Demand WiFi'
uci set wireless.@wifi-iface[0].encryption='psk2'
uci set wireless.@wifi-iface[0].key='ondemand123'
uci commit wireless
wifi reload

PROBE_SCRIPT="/usr/bin/presence_monitor.sh"
INIT_SCRIPT="/etc/init.d/on_demand_wifi"

echo "[⚙️] Creating smart WiFi monitor..."

cat << 'EOF' > $PROBE_SCRIPT
#!/bin/sh

# Settings
LED_PATH="/sys/class/leds"
LEDS="blue:internet blue:status blue:wifi2 blue:wifi5"
SCAN_INTERVAL=30
WIFI_ON_DELAY=10

echo "[♻️] Starting WiFi Manager..

wifi_on() {
    echo "[🔛] Turning WiFi ON..."
    wifi up
    sleep $WIFI_ON_DELAY  # Wait for WiFi to start
    for led in $LEDS; do
        echo 1 > "$LED_PATH/$led/brightness" 2>/dev/null || true
    done
}

wifi_off() {
    echo "[🔴] Turning WiFi OFF..."
    for led in $LEDS; do
        echo 0 > "$LED_PATH/$led/brightness" 2>/dev/null || true
    done
    wifi down
}

check_connected() {
    iwinfo phy0-ap0 assoclist 2>/dev/null | grep -c "dBm"
}


scan_devices() {
    echo "[🔍] Scanning..."
    iw phy0 scan 2>/dev/null | grep "SSID" | grep -v "On Demand WiFi" | sort | uniq
}


wifi_off

while true; do
    CONNECTED=$(check_connected)
    
    if [ "$CONNECTED" -gt 0 ]; then
        echo "[📱] $CONNECTED device(s) connected - Keeping WiFi ON"
        wifi_on
        sleep $SCAN_INTERVAL
        continue
    fi

    NEARBY=$(scan_devices | wc -l)
    
    if [ "$NEARBY" -gt 0 ]; then
        echo "[👥] $NEARBY nearby device(s) detected:"
        scan_devices | sed 's/^/    /'
        wifi_on
        sleep $SCAN_INTERVAL
    else
        echo "[🕳️] No devices nearby"
        wifi_off
        sleep 10
    fi
done
EOF

chmod +x $PROBE_SCRIPT

echo "[🛠️] Creating startup service..."

cat << EOF > $INIT_SCRIPT
#!/bin/sh /etc/rc.common

START=99
STOP=10

start() {
    echo "[🚀] Starting WiFi Manager..."
    if ! pgrep -f presence_monitor.sh >/dev/null; then
        $PROBE_SCRIPT >> /var/log/wifi_manager.log 2>&1 &
    fi
}

stop() {
    echo "[🛑] Stopping WiFi Manager..."
    pkill -f presence_monitor.sh
    wifi up  # Ensure WiFi is on when stopped
    for led in $LEDS; do
        echo 1 > "/sys/class/leds/\$led/brightness" 2>/dev/null || true
    done
}
EOF

chmod +x $INIT_SCRIPT
/etc/init.d/on_demand_wifi enable
/etc/init.d/on_demand_wifi start

echo "[✅] Installation complete!"
echo "
=== How It Works ===
1. WiFi starts OFF
2. Every 30 seconds:
   - Checks for connected devices
   - Scans for nearby phones/laptops
3. Turns ON when devices are detected
4. Turns OFF when no one is around

View logs: tail -f /var/log/wifi_manager.log
"
