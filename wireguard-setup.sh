#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
#
# WireGuard Setup Script
# Complete setup with server and client configuration

set -e

# Check if running as root
[[ $UID == 0 ]] || {
        echo "You must be root to run this."
        exit 1
}

# Configuration variables
WG_INTERFACE="wg0"
WG_PORT="51820"
SERVER_IP="192.168.2.1"
CLIENT_IP="192.168.2.2"
SUBNET="192.168.2.0/24"
CONFIG_FILE="myconfig.conf"
PRIVATE_KEY_FILE="/etc/wireguard/privatekey"
PUBLIC_KEY_FILE="/etc/wireguard/publickey"

# Create directory for WireGuard configs
mkdir -p /etc/wireguard

echo "=== WireGuard Setup Script ==="

# Function to generate keys
generate_keys() {
        echo "Generating WireGuard keys..."
        umask 077
        wg genkey >"$PRIVATE_KEY_FILE"
        wg pubkey <"$PRIVATE_KEY_FILE" >"$PUBLIC_KEY_FILE"
        echo "Keys generated successfully"
}

# Function to setup interface
setup_interface() {
        echo "Setting up WireGuard interface..."

        # Remove existing interface if it exists
        ip link del dev "$WG_INTERFACE" 2>/dev/null || true

        # Create WireGuard interface
        ip link add dev "$WG_INTERFACE" type wireguard

        # Set IP address with subnet
        ip address add dev "$WG_INTERFACE" "$SERVER_IP/24"

        # Set interface up
        ip link set up dev "$WG_INTERFACE"

        echo "Interface $WG_INTERFACE created with IP $SERVER_IP/24"
}

# Function to configure WireGuard from file
configure_from_file() {
        if [[ -f "$CONFIG_FILE" ]]; then
                echo "Configuring WireGuard from $CONFIG_FILE..."
                wg setconf "$WG_INTERFACE" "$CONFIG_FILE"
                echo "Configuration applied"
        else
                echo "Warning: Config file $CONFIG_FILE not found"
        fi
}

# Function to configure WireGuard manually
configure_manual() {
        echo "Configuring WireGuard manually..."

        # Generate keys if they don't exist
        if [[ ! -f "$PRIVATE_KEY_FILE" ]]; then
                generate_keys
        fi

        # Read keys
        PRIVATE_KEY=$(cat "$PRIVATE_KEY_FILE")

        # Set basic configuration
        wg set "$WG_INTERFACE" listen-port "$WG_PORT" private-key "$PRIVATE_KEY_FILE"

        # Add peer (example - replace with actual values)
        # wg set "$WG_INTERFACE" peer "ABCDEF..." allowed-ips 192.168.88.0/24 endpoint 209.202.254.14:8172

        echo "Manual configuration applied (listening on port $WG_PORT)"
}

# Function to test setup
test_setup() {
        echo "=== WireGuard Status ==="
        wg show
        echo ""
        echo "=== Interface Status ==="
        ip addr show "$WG_INTERFACE"
        echo ""

        # Test connectivity (optional)
        echo "Testing connectivity..."
        ping -c 1 "$CLIENT_IP" 2>/dev/null || echo "Client $CLIENT_IP not reachable"
}

# Function for ncat client setup
setup_ncat_client() {
        if [[ -f "contrib/examples/ncat-client-server/client.sh" ]]; then
                echo "Running ncat client script..."
                sudo contrib/examples/ncat-client-server/client.sh || true

                if [[ "$1" == "default-route" ]]; then
                        echo "Setting default route through VPN..."
                        sudo contrib/examples/ncat-client-server/client.sh default-route || true

                        echo "Testing IP address..."
                        curl -s zx2c4.com/ip || echo "Failed to get IP"
                fi
        else
                echo "Ncat client script not found"
        fi
}

# Function to connect to demo server
connect_demo() {
        echo "Connecting to WireGuard demo server..."
        exec 3<>/dev/tcp/demo.wireguard.com/42912 || {
                echo "Failed to connect to demo server"
                return 1
        }

        privatekey="$(wg genkey)"
        wg pubkey <<<"$privatekey" >&3
        IFS=: read -r status server_pubkey server_port internal_ip <&3

        if [[ $status == OK ]]; then
                echo "Connected to demo server!"
                echo "Internal IP: $internal_ip"

                # Setup temporary interface
                ip link del dev wg0 2>/dev/null || true
                ip link add dev wg0 type wireguard
                wg set wg0 private-key <(echo "$privatekey") peer "$server_pubkey" \
                        allowed-ips 0.0.0.0/0 endpoint "demo.wireguard.com:$server_port" \
                        persistent-keepalive 25
                ip address add "$internal_ip"/24 dev wg0
                ip link set up dev wg0

                if [[ "$1" == "default-route" ]]; then
                        host="$(wg show wg0 endpoints | sed -n 's/.*\t\(.*\):.*/\1/p')"
                        ip route add $(ip route get $host | sed '/ via [0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}/{s/^\(.* via [0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\).*/\1/}' | head -n 1) 2>/dev/null || true
                        ip route add 0/1 dev wg0
                        ip route add 128/1 dev wg0
                        echo "Default route set through VPN"
                fi
        else
                echo "Failed to connect to demo server"
                return 1
        fi
}

# Main menu
echo ""
echo "Select an option:"
echo "1. Basic setup (generate keys + interface)"
echo "2. Configure from file ($CONFIG_FILE)"
echo "3. Manual configuration"
echo "4. Connect to WireGuard demo server"
echo "5. Complete setup (all steps)"
echo "6. Show status"
echo "7. Exit"
echo ""

read -p "Enter choice [1-7]: " choice

case $choice in
1)
        generate_keys
        setup_interface
        test_setup
        ;;
2)
        configure_from_file
        test_setup
        ;;
3)
        generate_keys
        setup_interface
        configure_manual
        test_setup
        ;;
4)
        connect_demo "$@"
        ;;
5)
        generate_keys
        setup_interface
        configure_manual
        test_setup
        echo ""
        echo "=== Opening Chromium ==="
        chromium "http://192.168.4.1" 2>/dev/null || echo "Chromium not installed"
        ;;
6)
        test_setup
        ;;
7)
        echo "Exiting..."
        exit 0
        ;;
*)
        echo "Invalid choice"
        exit 1
        ;;
esac

echo ""
echo "=== Setup Complete ==="
echo "To check status: wg show"
echo "To bring interface down: ip link set dev wg0 down"
echo "To bring interface up: ip link set dev wg0 up"
echo "To delete interface: ip link del dev wg0"