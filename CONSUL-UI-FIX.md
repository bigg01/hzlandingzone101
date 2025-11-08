# Consul UI Access Fix

## Problem
The Consul UI at `http://91.99.105.61:8500/ui` was not accessible from the public internet.

## Root Cause
The Hetzner Cloud firewall for the bastion host was configured to only allow access to port 8500 from:
- Private network: `172.16.0.0/16`
- WireGuard VPN network: `192.168.100.0/24`

This blocked public internet access to the Consul UI.

## Solution Applied
Updated the firewall rule in `main.tf` to allow public access to port 8500:

```terraform
# Before
rule {
  direction  = "in"
  protocol   = "tcp"
  port       = "8500"
  source_ips = [var.network_cidr, "192.168.100.0/24"]
}

# After
rule {
  direction  = "in"
  protocol   = "tcp"
  port       = "8500"
  source_ips = ["0.0.0.0/0", "::/0"]
}
```

## Verification
```bash
$ curl -s -o /dev/null -w "%{http_code}" http://91.99.105.61:8500/ui/
200
```

✅ **Status**: Fixed - Consul UI is now accessible at http://91.99.105.61:8500/ui

## 🔒 Security Considerations

### ⚠️ Important Security Notes

**Current Configuration**: The Consul UI is now **publicly accessible** without authentication.

### Recommended Security Improvements

#### 1. **Enable Consul ACLs** (Recommended for Production)
Enable access control lists to require authentication:

```bash
# SSH to bastion
ssh -i ./id_ed25519_hetzner_cloud_k3s admin@91.99.105.61

# Edit Consul config
sudo nano /etc/consul.d/server.hcl

# Change ACL settings
acl {
  enabled = true
  default_policy = "deny"
  enable_token_persistence = true
}

# Restart Consul
sudo systemctl restart consul

# Bootstrap ACL system
consul acl bootstrap
```

#### 2. **Restrict Firewall to Specific IPs**
Limit access to your IP address only:

```terraform
variable "allowed_consul_ui_ips" {
  description = "List of IPs allowed to access Consul UI"
  type        = list(string)
  default     = ["YOUR_IP/32"]  # Replace with your public IP
}

# In firewall rule
rule {
  direction  = "in"
  protocol   = "tcp"
  port       = "8500"
  source_ips = var.allowed_consul_ui_ips
}
```

#### 3. **Use WireGuard VPN Access**
Access Consul UI only through the VPN:

```bash
# Setup WireGuard client
./setup-vpn-client.sh

# Access through VPN
http://172.16.0.10:8500/ui
```

#### 4. **Add TLS/HTTPS**
Configure Consul with TLS certificates:
- Use Let's Encrypt or your own certificates
- Configure reverse proxy (nginx/traefik) with HTTPS

#### 5. **IP Allowlist via Nginx Reverse Proxy**
Add nginx as a reverse proxy with IP restrictions:

```nginx
location /consul/ {
    allow YOUR_IP;
    deny all;
    proxy_pass http://localhost:8500/;
}
```

### Current vs Secure Configuration

| Aspect | Current | Recommended for Production |
|--------|---------|---------------------------|
| **Authentication** | ❌ None | ✅ ACL enabled with tokens |
| **Network Access** | ⚠️ Public internet | ✅ VPN or specific IPs only |
| **Encryption** | ⚠️ HTTP only | ✅ HTTPS with valid certificates |
| **Monitoring** | ❌ None | ✅ Access logging enabled |

### Quick Security Setup (Recommended)

1. **Enable ACLs immediately**:
```bash
ssh -i ./id_ed25519_hetzner_cloud_k3s admin@91.99.105.61 << 'EOF'
sudo sed -i 's/enabled = false/enabled = true/' /etc/consul.d/server.hcl
sudo sed -i 's/default_policy = "allow"/default_policy = "deny"/' /etc/consul.d/server.hcl
sudo systemctl restart consul
sleep 5
consul acl bootstrap
EOF
```

2. **Restrict firewall to your IP**:
```bash
# Get your public IP
MY_IP=$(curl -s ifconfig.me)

# Update terraform.tfvars
echo "allowed_consul_ui_ips = [\"${MY_IP}/32\"]" >> terraform.tfvars

# Apply changes
terraform apply
```

### Access Methods by Security Level

#### 🔴 Low Security (Current)
- **Access**: Direct public internet
- **Auth**: None
- **Use case**: Development/testing only

#### 🟡 Medium Security
- **Access**: IP whitelist + HTTPS
- **Auth**: Basic auth or ACLs
- **Use case**: Small teams, internal use

#### 🟢 High Security (Recommended for Production)
- **Access**: VPN only
- **Auth**: ACL tokens required
- **Encryption**: TLS enabled
- **Monitoring**: Audit logs enabled
- **Use case**: Production environments

## Next Steps

1. ✅ **Consul UI is now accessible** - Test at http://91.99.105.61:8500/ui
2. ⚠️ **Implement security measures** - Choose appropriate security level
3. 📝 **Document access procedures** - Share with team
4. 🔍 **Monitor access logs** - Watch for unauthorized attempts

## Rollback (If Needed)

To revert to VPN-only access:

```terraform
rule {
  direction  = "in"
  protocol   = "tcp"
  port       = "8500"
  source_ips = ["172.16.0.0/16", "192.168.100.0/24"]
}
```

Then run:
```bash
terraform apply
```

---

**Fixed on**: November 8, 2025  
**Status**: ✅ Working  
**Security Level**: ⚠️ Development (Public Access)  
**Recommended Action**: Implement ACLs or IP restrictions for production use
