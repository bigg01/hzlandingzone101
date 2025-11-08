# WireGuard VPN Client Setup Guide

This guide will help you connect to your Hetzner Landing Zone VPN using WireGuard.

## Prerequisites

You should have already retrieved the server configuration from the bastion:
```bash
ssh -i ./id_ed25519_hetzner_cloud_k3s admin@<bastion-ip> 'sudo cat /root/wireguard-info.txt && sudo cat /etc/wireguard/wg0.conf'
```

## Step 1: Install WireGuard on Your Local Machine

### Linux (Ubuntu/Debian)
```bash
sudo apt update
sudo apt install wireguard wireguard-tools
```

### Linux (Fedora/RHEL)
```bash
sudo dnf install wireguard-tools
```

### macOS
```bash
brew install wireguard-tools
# Or download WireGuard GUI from: https://www.wireguard.com/install/
```

### Windows
Download and install from: https://www.wireguard.com/install/

## Step 2: Generate Your Client Keys

```bash
# Generate your private key
wg genkey | tee client-privatekey | wg pubkey > client-publickey

# View your keys
echo "Your private key:"
cat client-privatekey
echo ""
echo "Your public key:"
cat client-publickey
```

**Important:** Keep your private key secure and never share it!

## Step 3: Create Client Configuration

Create a new file: `~/wg0-client.conf` (or any name you prefer)

```bash
# Create the config directory if it doesn't exist
mkdir -p ~/.wireguard

# Create the configuration file
nano ~/.wireguard/wg0-client.conf
```

Add the following content (replace the placeholders):

```ini
[Interface]
# Your client's private key (generated in Step 2)
PrivateKey = <YOUR_CLIENT_PRIVATE_KEY>

# IP address for your client on the VPN network
Address = 192.168.100.2/32

# Optional: Use VPN for DNS queries
DNS = 1.1.1.1, 8.8.8.8

[Peer]
# Server's public key (from the bastion: /root/wireguard-info.txt)
PublicKey = <SERVER_PUBLIC_KEY_FROM_BASTION>

# Server's public IP and port
Endpoint = <BASTION_PUBLIC_IP>:51820

# Routes: 
# - 192.168.100.0/24 = VPN network
# - 172.16.0.0/16 = Your Hetzner private network
# Use 0.0.0.0/0 to route ALL traffic through VPN
AllowedIPs = 192.168.100.0/24, 172.16.0.0/16

# Keep connection alive (important for NAT traversal)
PersistentKeepalive = 25
```

### Example Configuration

Here's what it should look like with example values:

```ini
[Interface]
PrivateKey = yAnz5TF+lXXJte14tji3zlMNq+hd2rYUIgJBgB3fBmk=
Address = 192.168.100.2/32
DNS = 1.1.1.1

[Peer]
PublicKey = AbCdEf1234567890aBcDeF1234567890aBcDeF1234=
Endpoint = 91.98.27.105:51820
AllowedIPs = 192.168.100.0/24, 172.16.0.0/16
PersistentKeepalive = 25
```

## Step 4: Add Your Client to the Server

SSH into your bastion and add your client's public key:

```bash
# Connect to bastion
ssh -i ./id_ed25519_hetzner_cloud_k3s admin@<bastion-ip>

# Add your client peer (run as root)
sudo wg set wg0 peer <YOUR_CLIENT_PUBLIC_KEY> allowed-ips 192.168.100.2/32

# Make it persistent by adding to config
sudo tee -a /etc/wireguard/wg0.conf <<EOF

[Peer]
PublicKey = <YOUR_CLIENT_PUBLIC_KEY>
AllowedIPs = 192.168.100.2/32
EOF

# Alternatively, edit the file directly
sudo nano /etc/wireguard/wg0.conf
```

Add this section to the server's config:

```ini
[Peer]
PublicKey = <YOUR_CLIENT_PUBLIC_KEY>
AllowedIPs = 192.168.100.2/32
```

Then restart WireGuard on the server:

```bash
sudo systemctl restart wg-quick@wg0

# Verify it's working
sudo wg show
```

## Step 5: Connect from Your Local Machine

### Linux/macOS (Command Line)

```bash
# Make sure the config has correct permissions
chmod 600 ~/.wireguard/wg0-client.conf

# Connect
sudo wg-quick up ~/.wireguard/wg0-client.conf

# Check status
sudo wg show

# Test connectivity
ping 192.168.100.1  # Ping the VPN server
ping 172.16.0.10   # Ping the bastion's private IP

# Disconnect when done
sudo wg-quick down ~/.wireguard/wg0-client.conf
```

### Linux (System-wide with systemd)

```bash
# Copy config to system location
sudo cp ~/.wireguard/wg0-client.conf /etc/wireguard/wg0-client.conf
sudo chmod 600 /etc/wireguard/wg0-client.conf

# Enable and start
sudo systemctl enable wg-quick@wg0-client
sudo systemctl start wg-quick@wg0-client

# Check status
sudo systemctl status wg-quick@wg0-client
sudo wg show

# Stop
sudo systemctl stop wg-quick@wg0-client
```

### macOS/Windows (GUI)

1. Open the WireGuard application
2. Click "Import tunnel(s) from file"
3. Select your `wg0-client.conf` file
4. Click "Activate" to connect

## Step 6: Verify Connection

Once connected, test the VPN:

```bash
# Check your VPN IP
ip addr show  # Linux
ifconfig      # macOS

# You should see a wg0-client interface with IP 192.168.100.2

# Test connectivity to VPN server
ping 192.168.100.1

# Test connectivity to bastion's private IP
ping 172.16.0.10

# SSH to bastion via private network
ssh -i ./id_ed25519_hetzner_cloud_k3s admin@172.16.0.10

# Access other resources in your private network
ssh admin@172.16.1.x  # Application servers
ssh admin@172.16.2.x  # Database servers
```

## Troubleshooting

### Connection not working

1. **Check firewall on local machine:**
   ```bash
   # Linux
   sudo ufw allow 51820/udp
   
   # macOS
   # Usually no action needed
   ```

2. **Verify server is listening:**
   ```bash
   ssh -i ./id_ed25519_hetzner_cloud_k3s admin@<bastion-public-ip>
   sudo wg show
   sudo ss -tulpn | grep 51820
   ```

3. **Check logs:**
   ```bash
   # Linux client
   sudo journalctl -u wg-quick@wg0-client -f
   
   # Server
   sudo journalctl -u wg-quick@wg0 -f
   ```

4. **Verify endpoint is reachable:**
   ```bash
   nc -u -v <bastion-ip> 51820
   ```

### Can't ping or access private network

1. **Check AllowedIPs in client config** - make sure it includes `172.16.0.0/16`

2. **Verify IP forwarding on server:**
   ```bash
   ssh -i ./id_ed25519_hetzner_cloud_k3s admin@<bastion-ip>
   sudo sysctl net.ipv4.ip_forward  # Should be 1
   ```

3. **Check iptables rules:**
   ```bash
   sudo iptables -L -v -n
   sudo iptables -t nat -L -v -n
   ```

### Multiple clients

To add more clients, repeat Steps 2-5 with different IPs:
- Client 1: 192.168.100.2/32
- Client 2: 192.168.100.3/32
- Client 3: 192.168.100.4/32
- etc.

## Quick Reference Commands

```bash
# Connect
sudo wg-quick up ~/.wireguard/wg0-client.conf

# Disconnect
sudo wg-quick down ~/.wireguard/wg0-client.conf

# Check status
sudo wg show

# Test VPN
ping 192.168.100.1

# SSH via VPN
ssh -i ./id_ed25519_hetzner_cloud_k3s admin@172.16.0.10
```

## Security Best Practices

1. ✅ Keep your private key secure (`client-privatekey`)
2. ✅ Use `chmod 600` on config files
3. ✅ Don't commit WireGuard configs to Git
4. ✅ Use strong, unique keys for each client
5. ✅ Regularly rotate keys (every 6-12 months)
6. ✅ Remove unused peer configurations from server
7. ✅ Monitor VPN access logs

## Useful Tips

### Auto-connect on Boot (Linux)

```bash
sudo systemctl enable wg-quick@wg0-client
```

### Route All Traffic Through VPN

Change in client config:
```ini
AllowedIPs = 0.0.0.0/0, ::/0
```

⚠️ This will route ALL internet traffic through your VPN

### Split Tunnel (Default)

Only route Hetzner private network:
```ini
AllowedIPs = 192.168.100.0/24, 172.16.0.0/16
```

Your regular internet traffic goes directly, only Hetzner traffic uses VPN.

## Need Help?

- WireGuard Documentation: https://www.wireguard.com/quickstart/
- Check server logs: `ssh admin@<bastion-ip> 'sudo journalctl -u wg-quick@wg0 -f'`
- Verify connectivity: `ping 192.168.100.1`
