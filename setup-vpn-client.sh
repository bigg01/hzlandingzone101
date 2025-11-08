#!/bin/bash
# WireGuard Client Setup Script
# This script helps you set up a WireGuard VPN connection to your Hetzner Landing Zone

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}WireGuard VPN Client Setup${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Check if WireGuard is installed
if ! command -v wg &> /dev/null; then
    echo -e "${RED}WireGuard is not installed!${NC}"
    echo ""
    echo "Please install WireGuard first:"
    echo "  Ubuntu/Debian: sudo apt install wireguard wireguard-tools"
    echo "  Fedora/RHEL:   sudo dnf install wireguard-tools"
    echo "  macOS:         brew install wireguard-tools"
    echo ""
    exit 1
fi

echo -e "${GREEN}✓ WireGuard is installed${NC}"
echo ""

# Get bastion IP from terraform
echo -e "${BLUE}Getting bastion IP from Terraform...${NC}"
BASTION_IP=$(terraform output -raw bastion_public_ip 2>/dev/null)

if [ -z "$BASTION_IP" ]; then
    echo -e "${RED}Could not get bastion IP from Terraform.${NC}"
    read -p "Please enter your bastion public IP: " BASTION_IP
fi

echo -e "${GREEN}✓ Bastion IP: ${BASTION_IP}${NC}"
echo ""

# Get server public key
echo -e "${BLUE}Retrieving server configuration...${NC}"
echo "You may need to enter your SSH password/passphrase..."
echo ""

SERVER_CONFIG=$(ssh -i ./id_ed25519_hetzner_cloud_k3s -o StrictHostKeyChecking=no admin@${BASTION_IP} 'sudo cat /root/wireguard-info.txt && echo "---CONFIG---" && sudo cat /etc/wireguard/wg0.conf' 2>/dev/null)

if [ -z "$SERVER_CONFIG" ]; then
    echo -e "${RED}Could not retrieve server configuration.${NC}"
    echo "Make sure you can SSH to the bastion host."
    exit 1
fi

SERVER_PUBKEY=$(echo "$SERVER_CONFIG" | grep -A1 "WireGuard Public Key:" | tail -n1 | awk '{print $1}')

if [ -z "$SERVER_PUBKEY" ]; then
    # Try to extract from config
    SERVER_PUBKEY=$(echo "$SERVER_CONFIG" | grep "^PublicKey" | awk '{print $3}')
fi

echo -e "${GREEN}✓ Retrieved server configuration${NC}"
echo ""

# Generate client keys
CONFIG_DIR="$HOME/.wireguard"
mkdir -p "$CONFIG_DIR"
chmod 700 "$CONFIG_DIR"

CLIENT_KEY="$CONFIG_DIR/client-privatekey"
CLIENT_PUB="$CONFIG_DIR/client-publickey"

if [ -f "$CLIENT_KEY" ]; then
    echo -e "${YELLOW}Client keys already exist. Use existing keys? (y/n)${NC}"
    read -r USE_EXISTING
    if [[ ! "$USE_EXISTING" =~ ^[Yy]$ ]]; then
        echo -e "${BLUE}Generating new client keys...${NC}"
        wg genkey | tee "$CLIENT_KEY" | wg pubkey > "$CLIENT_PUB"
        chmod 600 "$CLIENT_KEY" "$CLIENT_PUB"
    fi
else
    echo -e "${BLUE}Generating client keys...${NC}"
    wg genkey | tee "$CLIENT_KEY" | wg pubkey > "$CLIENT_PUB"
    chmod 600 "$CLIENT_KEY" "$CLIENT_PUB"
fi

CLIENT_PRIVATE=$(cat "$CLIENT_KEY")
CLIENT_PUBLIC=$(cat "$CLIENT_PUB")

echo -e "${GREEN}✓ Client keys ready${NC}"
echo ""

# Choose client IP
echo -e "${BLUE}Choose client IP address:${NC}"
read -p "Enter client number (2-254) [default: 2]: " CLIENT_NUM
CLIENT_NUM=${CLIENT_NUM:-2}

if [ "$CLIENT_NUM" -lt 2 ] || [ "$CLIENT_NUM" -gt 254 ]; then
    echo -e "${RED}Invalid client number. Using 2.${NC}"
    CLIENT_NUM=2
fi

CLIENT_IP="192.168.100.${CLIENT_NUM}"
echo -e "${GREEN}✓ Client IP: ${CLIENT_IP}/32${NC}"
echo ""

# Create client config
CONFIG_FILE="$CONFIG_DIR/wg0-client.conf"

echo -e "${BLUE}Creating client configuration...${NC}"
cat > "$CONFIG_FILE" <<EOF
[Interface]
# Client private key
PrivateKey = ${CLIENT_PRIVATE}

# Client IP address on VPN
Address = ${CLIENT_IP}/32

# DNS servers (optional)
DNS = 1.1.1.1, 8.8.8.8

[Peer]
# Server public key
PublicKey = ${SERVER_PUBKEY}

# Server endpoint
Endpoint = ${BASTION_IP}:51820

# Allowed IPs (split tunnel - only route Hetzner network)
# Change to 0.0.0.0/0 to route all traffic through VPN
AllowedIPs = 192.168.100.0/24, 172.16.0.0/16

# Keep connection alive
PersistentKeepalive = 25
EOF

chmod 600 "$CONFIG_FILE"
echo -e "${GREEN}✓ Configuration created: ${CONFIG_FILE}${NC}"
echo ""

# Display config
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Client Configuration:${NC}"
echo -e "${BLUE}========================================${NC}"
cat "$CONFIG_FILE"
echo ""

# Add peer to server
echo -e "${YELLOW}========================================${NC}"
echo -e "${YELLOW}IMPORTANT: Add client to server${NC}"
echo -e "${YELLOW}========================================${NC}"
echo ""
echo "You need to add your client's public key to the server."
echo "Your client public key is:"
echo ""
echo -e "${GREEN}${CLIENT_PUBLIC}${NC}"
echo ""
echo "Run this command to add it automatically:"
echo ""
echo -e "${BLUE}ssh -i ./id_ed25519_hetzner_cloud_k3s admin@${BASTION_IP} 'sudo wg set wg0 peer ${CLIENT_PUBLIC} allowed-ips ${CLIENT_IP}/32'${NC}"
echo ""
echo "Make it persistent by adding to server config:"
echo ""
echo -e "${BLUE}ssh -i ./id_ed25519_hetzner_cloud_k3s admin@${BASTION_IP} 'sudo tee -a /etc/wireguard/wg0.conf <<EOFPEER

[Peer]
PublicKey = ${CLIENT_PUBLIC}
AllowedIPs = ${CLIENT_IP}/32
EOFPEER
'${NC}"
echo ""
read -p "Press Enter to add client to server automatically, or Ctrl+C to do it manually..."

# Add to server
echo -e "${BLUE}Adding client to server...${NC}"
ssh -i ./id_ed25519_hetzner_cloud_k3s -o StrictHostKeyChecking=no admin@${BASTION_IP} "sudo wg set wg0 peer ${CLIENT_PUBLIC} allowed-ips ${CLIENT_IP}/32" 2>/dev/null

# Make it persistent
ssh -i ./id_ed25519_hetzner_cloud_k3s -o StrictHostKeyChecking=no admin@${BASTION_IP} "sudo tee -a /etc/wireguard/wg0.conf >/dev/null <<EOFPEER

[Peer]
# Client ${CLIENT_NUM} - Added $(date)
PublicKey = ${CLIENT_PUBLIC}
AllowedIPs = ${CLIENT_IP}/32
EOFPEER
" 2>/dev/null

echo -e "${GREEN}✓ Client added to server${NC}"
echo ""

# Instructions
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Next Steps:${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo "To connect to the VPN, run:"
echo -e "${GREEN}sudo wg-quick up ${CONFIG_FILE}${NC}"
echo ""
echo "To disconnect:"
echo -e "${GREEN}sudo wg-quick down ${CONFIG_FILE}${NC}"
echo ""
echo "To check status:"
echo -e "${GREEN}sudo wg show${NC}"
echo ""
echo "To test connectivity:"
echo -e "${GREEN}ping 10.10.10.1${NC}  # Ping VPN server"
echo -e "${GREEN}ping 10.0.0.10${NC}   # Ping bastion private IP"
echo ""
echo "Would you like to connect now? (y/n)"
read -r CONNECT_NOW

if [[ "$CONNECT_NOW" =~ ^[Yy]$ ]]; then
    echo -e "${BLUE}Connecting to VPN...${NC}"
    sudo wg-quick up "$CONFIG_FILE"
    echo ""
    echo -e "${GREEN}✓ Connected!${NC}"
    echo ""
    echo "Testing connectivity..."
    if ping -c 3 10.10.10.1 &>/dev/null; then
        echo -e "${GREEN}✓ VPN connection successful!${NC}"
    else
        echo -e "${YELLOW}⚠ Could not ping VPN server. Check your configuration.${NC}"
    fi
    echo ""
    echo "VPN Status:"
    sudo wg show
else
    echo ""
    echo -e "${YELLOW}Setup complete! Connect manually when ready.${NC}"
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Setup Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
