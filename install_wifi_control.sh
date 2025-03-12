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
opkg install iw >> "$LOG_FILE" 2>&1
opkg install tcpdump >> "$LOG_FILE" 2>&1
opkg install nodogsplash >> "$LOG_FILE" 2>&1  # Captive portal
opkg install uhttpd >> "$LOG_FILE" 2>&1       # Web server for captive portal

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

WAKE_DURATION=360
BOOT_DURATION=1200  # 20 minutes

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

# Function to listen for probe requests
listen_for_probes() {
    for iface in $INTERFACES; do
        # Put the interface in monitor mode
        ifconfig $iface down
        iwconfig $iface mode monitor
        ifconfig $iface up

        # Continuously listen for probe requests
        tcpdump -i $iface -e type mgt subtype probe-req -c 1 2>/dev/null | while read -r line; do
            log_message "Probe request detected on $iface. Turning Wi-Fi on."
            turn_on_wifi
            sleep $WAKE_DURATION
        done &
    done
}

listen_for_probes

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
        log_message "No connected devices. Wi-Fi will remain off until a probe request is detected."
    fi
done
EOF

log_message "Making the script executable..."
chmod +x /etc/config/wifi_control.sh

log_message "Setting up captive portal..."


opkg install nodogsplash >> "$LOG_FILE" 2>&1


cat << 'EOF' > /etc/config/nodogsplash
config nodogsplash
    option enabled '1'
    option gatewayinterface 'br-lan'
    option maxclients '250'
    option authentication 'on'
    option redirecturl 'http://192.168.1.1/captive-portal'
EOF

mkdir -p /www/captive-portal
cat << 'EOF' > /www/captive-portal/index.html
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Wi-Fi Setup</title>
    <style>
        body {
            font-family: 'Arial', sans-serif;
            background-color: #f4f4f4;
            display: flex;
            justify-content: center;
            align-items: center;
            height: 100vh;
            margin: 0;
        }
        .container {
            background: white;
            padding: 40px;
            border-radius: 12px;
            box-shadow: 0 4px 20px rgba(0, 0, 0, 0.1);
            text-align: center;
            max-width: 400px;
            width: 100%;
        }
        .logo {
            max-width: 150px;
            margin-bottom: 20px;
        }
        h1 {
            font-size: 24px;
            margin-bottom: 20px;
            color: #333;
        }
        input {
            width: 100%;
            padding: 12px;
            margin: 10px 0;
            border: 1px solid #ddd;
            border-radius: 6px;
            font-size: 16px;
        }
        input:focus {
            border-color: #007bff;
            outline: none;
        }
        button {
            background-color: #007bff;
            color: white;
            padding: 12px 24px;
            border: none;
            border-radius: 6px;
            font-size: 16px;
            cursor: pointer;
            transition: background-color 0.3s ease;
        }
        button:hover {
            background-color: #0056b3;
        }
        .footer {
            margin-top: 20px;
            font-size: 14px;
            color: #777;
        }
    </style>
</head>
<body>
    <div class="container">
        <img src="/captive-portal/onedmand.png" alt="Company Logo" class="logo">
        <h1>Set Up Your Wi-Fi</h1>
        <form action="/set-wifi" method="post">
            <input type="text" name="ssid" placeholder="Wi-Fi Name (SSID)" required>
            <input type="password" name="password" placeholder="Wi-Fi Password" required>
            <button type="submit">Save & Connect</button>
        </form>
        <div class="footer">Your connection will start automatically after setup.</div>
    </div>
</body>
</html>
EOF


wget -O /www/captive-portal/onedmand.png https://github.com/tsod99/wifiscript/blob/master/onedmand.png?raw=true

cat << 'EOF' > /www/captive-portal/set-wifi
#!/bin/sh

CONFIG_FILE="/etc/config/wifi_configured"

if [ -f "$CONFIG_FILE" ]; then
    # Redirect to a blank page to close the captive portal
    echo "HTTP/1.1 302 Found"
    echo "Location: http://192.168.1.1/captive-portal/close.html"
    echo
    exit 0
fi


read -r POST_DATA
SSID=$(echo "$POST_DATA" | sed -n 's/.*ssid=\([^&]*\).*/\1/p' | sed 's/%20/ /g')
PASSWORD=$(echo "$POST_DATA" | sed -n 's/.*password=\([^&]*\).*/\1/p')


uci set wireless.default_radio0.ssid="$SSID"
uci set wireless.default_radio0.key="$PASSWORD"
uci commit wireless
wifi reload


touch "$CONFIG_FILE"


/etc/init.d/nodogsplash stop


echo "HTTP/1.1 302 Found"
echo "Location: http://192.168.1.1/captive-portal/close.html"
echo
EOF

cat << 'EOF' > /www/captive-portal/close.html
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Close</title>
</head>
<body>
    <script>
        // Close the captive portal window
        window.close();
    </script>
</body>
</html>
EOF


chmod +x /www/captive-portal/set-wifi

cat << 'EOF' > /etc/config/uhttpd
config uhttpd 'main'
    option listen_http '0.0.0.0:80'
    option home '/www/captive-portal'
EOF

/etc/init.d/nodogsplash restart
/etc/init.d/uhttpd restart

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
