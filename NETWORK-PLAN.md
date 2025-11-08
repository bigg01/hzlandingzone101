# Network I### Virtual Machine Network (Hetzner Cloud)
- **CIDR**: `172.16.0.0/16`
- **Size**: 65,536 IP addresses
- **Range**: 172.16.0.0 - 172.16.255.255
- **Purpose**: All Hetzner cloud VMs (bastion, apps, databases)dress Plan

#### Advantages of 172.16.x.x Range fo### Can't reach 172.16.x.x from VPN
- Check AllowedIPs includes `172.16.0.0/16`
- Verify VPN is connected: `sudo wg show`
- Check IP forwarding on bastion: `sysctl net.ipv4.ip_forward`
- Test VPN interface: `ping 192.168.100.1`
- Test VM network: `ping 172.16.0.10`

### Routing conflicts
- If your local network uses 172.16.x.x (unlikely):
  - Option 1: Change VM network to 10.x.x.x
  - Option 2: Use full tunnel VPN (AllowedIPs = 0.0.0.0/0)
  - Option 3: Use more specific routes
- If your local network uses 192.168.100.x:
  - Change VPN subnet to 192.168.101.x or 192.168.200.xRFC 1918 compliant private network (172.16.0.0/12)
- ✅ Less common than 10.x or 192.168.x - fewer conflicts
- ✅ No conflicts with typical home/office networks (192.168.x.x)
- ✅ No conflicts with 10.x.x.x corporate networks
- ✅ Large address space (172.16.0.0 - 172.31.255.255)

### Advantages of 192.168.100.x for VPN
- ✅ RFC 1918 compliant
- ✅ Using .100 subnet avoids conflicts with .0, .1, .2 (most common)
- ✅ Clearly separated from VM network (different major subnet)
- ✅ Easy to identify VPN traffic vs VM traffic

### Potential Conflicts
- ⚠️ Some home routers use 172.16.x.x (rare but possible)
- ⚠️ If your local network is 192.168.100.x, VPN will conflict
- ✅ Solution: Change VPN to 192.168.101.x or use different subnetw
## Overview
- **Virtual Machines**: **172.16.0.0/16** (RFC 1918 private network)
- **WireGuard VPN**: **192.168.100.0/24** (isolated VPN network)

## Network Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Internet / Public                         │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       │ Public IP
                       │
         ┌─────────────▼──────────────┐
         │  Bastion Host              │
         │  Public IP: x.x.x.x        │
         │  VM IP: 172.16.0.10        │  ◄─── Hetzner VM Network
         │  VPN IP: 192.168.100.1     │  ◄─── WireGuard VPN
         └─────┬──────────────┬───────┘
               │              │
               │              │ UDP 51820 (WireGuard)
               │              │
               │         ┌────▼─────────────────────┐
               │         │  VPN Clients             │
               │         │  192.168.100.2-254       │
               │         │  (Your laptop/desktop)   │
               │         └──────────────────────────┘
               │
               │ 172.16.0.0/16 (Private Network)
               │
        ┌──────┴─────────────────────┐
        │                             │
┌───────▼──────────┐        ┌────────▼─────────┐
│  App Servers     │        │  Database Svrs   │
│  172.16.1.0/24   │◄──────►│  172.16.2.0/24   │
│                  │        │                  │
└──────────────────┘        └──────────────────┘
```

**Traffic Flow:**
1. VPN Client (192.168.100.2) connects to Bastion (192.168.100.1)
2. VPN traffic is routed through Bastion to VM network (172.16.x.x)
3. VMs communicate on 172.16.0.0/16 network
4. All traffic between networks is encrypted (WireGuard)

## Network Structuretwork IP Address Plan - 192.168.x.x Range

## Overview
Updated from 10.0.0.0/16 to **172.16.0.0/16** private network range.

## Network Structure

### Main Network
- **CIDR**: `172.16.0.0/16`
- **Size**: 65,536 IP addresses
- **Range**: 172.16.0.0 - 192.168.255.255

## Subnets

### 1. Management Subnet
- **CIDR**: `172.16.0.0/24`
- **Purpose**: Bastion host, monitoring, management tools
- **Hosts**: 254 available
- **Range**: 172.16.0.1 - 172.16.0.254
- **Key Hosts**:
  - `172.16.0.10` - Bastion host

### 2. Application Subnet
- **CIDR**: `172.16.1.0/24`
- **Purpose**: Application servers, web servers
- **Hosts**: 254 available
- **Range**: 172.16.1.1 - 172.16.1.254
- **Key Hosts**:
  - `172.16.1.x` - Application servers (auto-assigned)

### 3. Services Subnet
- **CIDR**: `172.16.2.0/24`
- **Purpose**: Shared services, databases, caches
- **Hosts**: 254 available
- **Range**: 172.16.2.1 - 172.16.2.254
- **Key Hosts**:
  - `172.16.2.x` - Database servers (auto-assigned)

### 4. DMZ Subnet
- **CIDR**: `172.16.10.0/24`
- **Purpose**: Public-facing services, load balancers
- **Hosts**: 254 available
- **Range**: 172.16.10.1 - 172.16.10.254

## VPN Network

### WireGuard VPN (Separate from VM Network)
- **CIDR**: `192.168.100.0/24`
- **Purpose**: VPN client connections (remote access)
- **Range**: 192.168.100.1 - 192.168.100.254
- **Size**: 254 available IPs
- **Key Hosts**:
  - `192.168.100.1` - VPN server (bastion's WireGuard interface)
  - `192.168.100.2-254` - VPN clients (laptops, workstations, etc.)

**Note**: This is a separate network from the VM network. Traffic from VPN clients (192.168.100.x) can access VMs (172.16.x.x) via the bastion's routing.

## Firewall Rules

### Management Subnet (172.16.0.0/24)
- ✅ SSH from anywhere (port 22)
- ✅ WireGuard VPN (UDP 51820)
- ✅ ICMP (ping)
- ✅ All outbound traffic

### Application Subnet (172.16.1.0/24)
- ✅ HTTP (port 80) from anywhere
- ✅ HTTPS (port 443) from anywhere
- ✅ SSH (port 22) from 172.16.0.0/16 only
- ✅ ICMP (ping) from anywhere
- ✅ All outbound traffic

### Services Subnet (172.16.2.0/24) - Most Restrictive
- ✅ PostgreSQL (5432) from 172.16.0.0/16 only
- ✅ MySQL (3306) from 172.16.0.0/16 only
- ✅ MongoDB (27017) from 172.16.0.0/16 only
- ✅ Redis (6379) from 172.16.0.0/16 only
- ✅ SSH (22) from 172.16.0.0/24 only (management subnet)
- ✅ ICMP from 172.16.0.0/16 only
- ✅ Outbound to 172.16.0.0/16 and updates (80, 443)

## IP Allocation Strategy

### Reserved IPs
- `.0` - Network address (reserved)
- `.1` - Usually gateway (Hetzner)
- `.255` - Broadcast address (reserved)

### Recommended Allocation

#### Management Subnet (172.16.0.0/24)
```
172.16.0.1   - Gateway (Hetzner)
172.16.0.10  - Bastion host
172.16.0.11  - Monitoring server (future)
172.16.0.12  - Jump host 2 (future)
172.16.0.20-50 - Reserved for infrastructure
172.16.0.51-254 - Available
```

#### Application Subnet (172.16.1.0/24)
```
172.16.1.1   - Gateway (Hetzner)
172.16.1.10-99   - Web servers
172.16.1.100-199 - API servers
172.16.1.200-254 - Worker nodes
```

#### Services Subnet (172.16.2.0/24)
```
172.16.2.1   - Gateway (Hetzner)
172.16.2.10-29   - PostgreSQL servers
172.16.2.30-49   - MySQL servers
172.16.2.50-69   - MongoDB servers
172.16.2.70-89   - Redis/Cache servers
172.16.2.90-109  - Message queues
172.16.2.110-254 - Other services
```

#### DMZ Subnet (172.16.10.0/24)
```
172.16.10.1   - Gateway (Hetzner)
172.16.10.10-29  - Load balancers
172.16.10.30-49  - Reverse proxies
172.16.10.50-69  - CDN origins
172.16.10.70-254 - Public services
```

## VPN Client Configuration

When connecting via VPN, use these settings:

```ini
[Interface]
Address = 192.168.100.2/32  # Your VPN IP

```ini
[Peer]
AllowedIPs = 192.168.100.0/24, 172.16.0.0/16  # VPN network + VM network
```

**Network Separation:**
- `192.168.100.0/24` - WireGuard VPN network (your client's IP)
- `172.16.0.0/16` - Hetzner VM network (all servers)
```

## Access Patterns

### From VPN Client
- ✅ Can access: All 172.16.0.0/16 (entire private network)
- ✅ Can ping: 172.16.0.10 (bastion)
- ✅ Can SSH: Any server in private network

### From Bastion (172.16.0.10)
- ✅ Can access: All subnets
- ✅ Can manage: All servers

### From Application Server (172.16.1.x)
- ✅ Can access: Database servers (172.16.2.x)
- ✅ Can access: Other app servers
- ✅ Cannot: Directly accessed from internet (except ports 80, 443)

### From Database Server (172.16.2.x)
- ✅ Can access: Other servers in private network
- ✅ Cannot: Directly accessed from internet
- ✅ Cannot: SSH from application subnet (must use bastion)

## Testing Connectivity

### Test from Local Machine (via VPN)
```bash
# Connect to VPN first
sudo wg-quick up ~/.wireguard/wg0-client.conf

# Test VPN server (WireGuard interface)
ping 192.168.100.1

# Test bastion private IP (VM network)
ping 172.16.0.10

# SSH to bastion via private IP
ssh -i ./id_ed25519_hetzner_cloud_k3s admin@172.16.0.10

# SSH to application server (via VPN)
ssh admin@172.16.1.x

# SSH to database server (via VPN)
ssh admin@172.16.2.x
```

### Test from Bastion
```bash
# Test application subnet
ping 172.16.1.10

# Test services subnet
ping 172.16.2.10

# Test database connection
psql -h 172.16.2.10 -U postgres
```

### Test from Application Server
```bash
# Test database connectivity
psql -h 172.16.2.10 -U app_user -d app_db

# Test Redis
redis-cli -h 172.16.2.70 ping
```

## Migration Notes

If migrating from 10.0.0.0/16:
1. ✅ Update Terraform configuration
2. ✅ Run `terraform apply`
3. ✅ Update VPN client configs (AllowedIPs)
4. ✅ Update application configs (database connection strings)
5. ✅ Update monitoring/alerting rules
6. ✅ Update DNS records (if any)
7. ✅ Update firewall rules in applications

## Security Considerations

### Advantages of 192.168.x.x Range
- ✅ RFC 1918 compliant private network
- ✅ Commonly used, well understood
- ✅ No conflicts with 10.x.x.x networks you might VPN into

### Potential Conflicts
- ⚠️ May conflict with home/office networks using 192.168.x.x
- ⚠️ If your local network is 172.16.1.x, you'll have routing issues
- ✅ Solution: Use VPN full tunnel mode or change local network

### Best Practices
1. ✅ Always connect via VPN for management
2. ✅ Use bastion as jump host
3. ✅ Keep database servers in services subnet
4. ✅ Restrict SSH to management subnet for databases
5. ✅ Use security groups/firewalls at application level too
6. ✅ Monitor access logs regularly
7. ✅ Rotate credentials periodically

## Troubleshooting

### Can't reach 192.168.x.x from VPN
- Check AllowedIPs includes `172.16.0.0/16`
- Verify VPN is connected: `sudo wg show`
- Check IP forwarding on bastion: `sysctl net.ipv4.ip_forward`

### Routing conflicts
- If your local network uses 192.168.x.x:
  - Option 1: Change local network to 10.x.x.x
  - Option 2: Use full tunnel VPN (AllowedIPs = 0.0.0.0/0)
  - Option 3: Use more specific routes

### Services can't communicate
- Check firewall rules: `sudo ufw status`
- Verify Hetzner firewall in console
- Test with: `telnet 172.16.2.10 5432`

## Future Expansion

Available subnets for growth:
- `192.168.3.0/24` - Additional services
- `192.168.4.0/24` - Development environment
- `192.168.5.0/24` - Staging environment
- `192.168.11-20.0/24` - Additional DMZ zones
- `192.168.100-199.0/24` - Reserved for future use
- `192.168.200-254.0/24` - Special purpose

## Quick Reference

| Network Type | Subnet | CIDR | Purpose | First IP | Last IP | Gateway |
|--------------|--------|------|---------|----------|---------|---------|
| VM Network | Management | 172.16.0.0/24 | Bastion, Mgmt | 172.16.0.1 | 172.16.0.254 | 172.16.0.1 |
| VM Network | Application | 172.16.1.0/24 | App Servers | 172.16.1.1 | 172.16.1.254 | 172.16.1.1 |
| VM Network | Services | 172.16.2.0/24 | Databases | 172.16.2.1 | 172.16.2.254 | 172.16.2.1 |
| VM Network | DMZ | 172.16.10.0/24 | Public Services | 172.16.10.1 | 172.16.10.254 | 172.16.10.1 |
| VPN Network | WireGuard | 192.168.100.0/24 | Remote Access | 192.168.100.1 | 192.168.100.254 | N/A |
