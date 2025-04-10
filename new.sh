#!/bin/sh

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

check_success() {
    if [ "$1" -eq 0 ]; then
        echo -e "${GREEN}✓ Success${NC}"
    else
        echo -e "${RED}✗ Failed${NC}"
        exit 1
    fi
}

echo -e "\n${YELLOW}=== On Demand WIFI Portal Setup ===${NC}\n"

echo -n "[1/8] Checking internet connection... "
ping -c 1 -W 3 google.com >/dev/null 2>&1
if [ $? -ne 0 ]; then
    echo -e "${RED}✗ No internet access${NC}"
    echo -e "${YELLOW}Please configure network connectivity first!${NC}"
    exit 1
else
    echo -e "${GREEN}✓ Connected${NC}"
fi

echo -n "[2/8] Updating package lists... "
opkg update >/dev/null 2>&1
check_success $?

echo -n "[3/8] Installing nodogsplash... "
opkg install nodogsplash >/dev/null 2>&1
check_success $?

echo -n "[4/8] Installing wget... "
opkg install wget >/dev/null 2>&1
check_success $?

echo -n "[5/8] Installing base64... "
opkg install coreutils-base64 >/dev/null 2>&1
check_success $?

echo -n "[6/8] Configuring captive portal... "
mkdir -p /etc/nodogsplash

cat > /etc/nodogsplash/nodogsplash.conf <<'EOL'
GatewayInterface br-lan
GatewayAddress 192.168.1.1
MaxClients 250
AuthIdleTimeout 480
ClientIdleTimeout 60
ForcedRedirectDomain https://www.openwrt.org
PreAuthIdleTimeout 60
RedirectURL https://www.openwrt.org
TrafficControl yes
TrafficControlLimitUpload 0
TrafficControlLimitDownload 0
TrafficControlLimitBurst 0

FirewallRuleSet authenticated-users {
    FirewallRule allow to 0.0.0.0/0
}

FirewallRuleSet preauthenticated-users {
    FirewallRule allow to 192.168.1.1
    FirewallRule allow udp port 53
    FirewallRule allow tcp port 53
    FirewallRule allow tcp port 80
}

FirewallRuleSet validating-users {
    FirewallRule allow to 0.0.0.0/0
}

FirewallRuleSet users {
    FirewallRule allow to 0.0.0.0/0
}
EOL
check_success $?

echo -n "[7/8] Downloading and configuring logo... "
LOGO_URL="https://github.com/tsod99/wifiscript/raw/master/onedmand.png"
LOGO_PATH="/etc/nodogsplash/logo.png"

wget -q "$LOGO_URL" -O "$LOGO_PATH"
if [ $? -ne 0 ]; then
    echo -e "${RED}✗ Failed to download logo${NC}"
    exit 1
fi

# Use -w 0 if supported, fallback otherwise
LOGO_BASE64=$(base64 -w 0 "$LOGO_PATH" 2>/dev/null || base64 "$LOGO_PATH")
cat > /etc/nodogsplash/splash.html <<EOL
<!DOCTYPE html>
<html>
<head>
    <title>On Demand WIFI Setup</title>
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <style>
        body { font-family: Arial, sans-serif; text-align: center; margin: 0; padding: 20px; }
        .container { max-width: 500px; margin: 0 auto; }
        img { max-width: 100%; height: auto; margin-bottom: 20px; }
        form { background: #f9f9f9; padding: 20px; border-radius: 5px; }
        input { margin: 10px 0; padding: 8px; width: 100%; box-sizing: border-box; }
        button { background: #0066cc; color: white; border: none; padding: 10px 15px; cursor: pointer; }
    </style>
</head>
<body>
    <div class="container">
        <img src="data:image/png;base64,$LOGO_BASE64" alt="On Demand WIFI Logo">
        <h1>On Demand WIFI Setup</h1>
        <p>Please configure your WiFi network</p>
        
        <form action="/setwifi" method="post">
            <input type="text" name="ssid" placeholder="WiFi Name (SSID)" required value="On Demand WIFI">
            <input type="password" name="password" placeholder="Password" required>
            <button type="submit">Save Settings</button>
        </form>
    </div>
</body>
</html>
EOL
check_success $?

echo -n "[8/8] Configuring WiFi settings and handler... "

uci set wireless.@wifi-iface[0].ssid="On Demand WIFI"
uci commit wireless

cat > /etc/nodogsplash/setwifi <<'EOL'
#!/bin/sh

if [ "$REQUEST_METHOD" = "POST" ]; then
    SSID=$(echo "$QUERY_STRING" | sed -n 's/.*ssid=\([^&]*\).*/\1/p' | sed 's/%20/ /g')
    PASSWORD=$(echo "$QUERY_STRING" | sed -n 's/.*password=\([^&]*\).*/\1/p')

    uci set wireless.@wifi-iface[0].ssid="$SSID"
    uci set wireless.@wifi-iface[0].key="$PASSWORD"
    uci commit wireless

    /etc/init.d/network restart

    /etc/init.d/nodogsplash disable
    /etc/init.d/nodogsplash stop

    cat <<EOF
HTTP/1.1 200 OK
Content-Type: text/html
Refresh: 5;url=about:blank

<!DOCTYPE html>
<html>
<head>
    <title>WiFi Setup Complete</title>
    <script>
        setTimeout(function() {
            window.close();
        }, 3000);
    </script>
    <style>
        body { font-family: Arial, sans-serif; text-align: center; padding: 50px; }
        h1 { color: #4CAF50; }
    </style>
</head>
<body>
    <h1>✓ WiFi Setup Complete</h1>
    <p>Your new WiFi network <strong>$SSID</strong> is ready to use!</p>
    <p>This window will close automatically...</p>
</body>
</html>
EOF
    exit 0
fi
EOL

chmod +x /etc/nodogsplash/setwifi
check_success $?

echo -n "Starting captive portal service... "
/etc/init.d/nodogsplash enable >/dev/null 2>&1 && \
/etc/init.d/nodogsplash restart >/dev/null 2>&1
check_success $?

echo -e "\n${GREEN}=== Setup Completed Successfully ===${NC}"
echo -e "${YELLOW}On Demand WIFI portal is now active!${NC}"
echo -e "Default WiFi Name (SSID): ${YELLOW}On Demand WIFI${NC}"
echo -e "To check status: ${YELLOW}service nodogsplash status${NC}"
echo -e "To view logs: ${YELLOW}logread | grep nodogsplash${NC}"

