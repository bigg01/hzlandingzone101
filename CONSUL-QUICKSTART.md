# Consul Service Mesh - Quick Start Guide

## What Was Added

Your Hetzner landing zone now includes **Consul Service Mesh** for:
- ✅ **Service Discovery** - Services find each other by name
- ✅ **Automatic mTLS** - Encrypted service-to-service communication
- ✅ **Service Intentions** - Zero-trust access policies
- ✅ **Health Checking** - Automatic monitoring
- ✅ **Traffic Management** - Load balancing, routing

## Architecture

```
┌─────────────────────────────────────────────┐
│  Bastion (172.16.0.10)                      │
│  • Consul Server                            │
│  • Service Registry                         │
│  • UI: http://<bastion-ip>:8500            │
└─────────────────┬───────────────────────────┘
                  │
        ┌─────────┼──────────┐
        │         │          │
┌───────▼──────┐ │  ┌───────▼─────────┐
│ Web Servers  │ │  │ Database        │
│ 172.16.1.x   │ │  │ 172.16.2.x      │
│              │ │  │                 │
│ Service: web │ │  │ Service: postgres│
│ + Envoy      │─┼─▶│ + Envoy         │
└──────────────┘ │  └─────────────────┘
                 │
         mTLS Encrypted Mesh
```

## Deployment

### 1. Apply Terraform Configuration

```bash
cd hzlandingzone

# Review changes
terraform plan -var-file terraform.tfvars

# Deploy (will recreate servers with Consul)
terraform apply -var-file terraform.tfvars
```

**⚠️ Important:** This will recreate your servers to add Consul. Make sure you've backed up any data.

### 2. Wait for Services to Register

Services automatically register after ~30 seconds. Monitor with:

```bash
# Get bastion IP
BASTION_IP=$(terraform output -raw bastion_public_ip)

# Check Consul cluster
ssh admin@$BASTION_IP 'consul members'

# Wait for services to appear
ssh admin@$BASTION_IP 'watch -n 2 consul catalog services'
```

You should see:
```
consul
postgres
web
```

### 3. Configure Service Intentions (Access Policies)

```bash
# Run the setup script
ssh admin@$BASTION_IP '/usr/local/bin/setup-consul-intentions.sh'
```

This creates:
- ✅ Allow web → api
- ✅ Allow api → postgres
- ✅ Allow bastion → * (monitoring)

### 4. Access Consul UI

Open in browser:
```
http://<bastion-ip>:8500/ui
```

Via tunnel (more secure):
```bash
ssh -L 8500:localhost:8500 admin@$BASTION_IP
# Then open: http://localhost:8500/ui
```

## Service Discovery

Your applications can now find services by name instead of IP:

### Before (Hard-coded IPs):
```bash
# Application config
DATABASE_HOST=172.16.2.10
DATABASE_PORT=5432
```

### After (Service Discovery):

**Option 1: Consul DNS**
```bash
# Consul provides DNS on port 8600
DATABASE_HOST=postgres.service.consul
DATABASE_PORT=5432
```

**Option 2: Connect via Sidecar (Recommended)**
```bash
# Connect to localhost - sidecar handles routing + mTLS
DATABASE_HOST=localhost
DATABASE_PORT=5432  # or use upstream port from config
```

## Common Operations

### Check Service Health

```bash
# Via management script
./consul-manage.sh $BASTION_IP

# Or manually
ssh admin@$BASTION_IP 'consul catalog nodes -service=web'
ssh admin@$BASTION_IP 'consul catalog nodes -service=postgres'
```

### View Service Intentions (Policies)

```bash
ssh admin@$BASTION_IP 'consul intention list'
```

### Add New Intention

```bash
# Allow web to access postgres directly
ssh admin@$BASTION_IP 'consul intention create -allow web postgres'

# Deny specific service
ssh admin@$BASTION_IP 'consul intention create -deny web postgres'
```

### Test Service Connectivity

```bash
# Check if web can connect to postgres
ssh admin@$BASTION_IP 'consul intention check web postgres'
```

### Enable Zero-Trust Mode

```bash
# Default deny all connections
ssh admin@$BASTION_IP 'consul intention create -deny "*" "*"'

# Then explicitly allow each connection
ssh admin@$BASTION_IP 'consul intention create -allow web postgres'
ssh admin@$BASTION_IP 'consul intention create -allow bastion "*"'
```

### View Envoy Proxy Stats

```bash
# SSH to application server via bastion
ssh -J admin@$BASTION_IP admin@172.16.1.10

# View proxy stats
curl localhost:19000/stats | grep upstream
curl localhost:19000/clusters
curl localhost:19000/config_dump
```

## Service Registration

Services are automatically registered via configuration files in `/etc/consul.d/`.

### Web Service Example

Located at: `/etc/consul.d/web-service.hcl`

```hcl
service {
  name = "web"
  id = "web-1"
  port = 80
  
  connect {
    sidecar_service {
      proxy {
        upstreams = [
          {
            destination_name = "api"
            local_bind_port  = 8080
          }
        ]
      }
    }
  }
  
  checks = [
    {
      http     = "http://127.0.0.1:80/"
      interval = "10s"
      timeout  = "2s"
    }
  ]
}
```

### Postgres Service Example

Located at: `/etc/consul.d/postgres-service.hcl`

```hcl
service {
  name = "postgres"
  id = "postgres-1"
  port = 5432
  
  connect {
    sidecar_service {}
  }
  
  checks = [
    {
      tcp      = "127.0.0.1:5432"
      interval = "10s"
      timeout  = "2s"
    }
  ]
}
```

## Troubleshooting

### Services Not Appearing

```bash
# Check Consul agent status
ssh -J admin@$BASTION_IP admin@172.16.1.10 'systemctl status consul'

# Check logs
ssh -J admin@$BASTION_IP admin@172.16.1.10 'journalctl -u consul -f'

# Reload Consul config
ssh -J admin@$BASTION_IP admin@172.16.1.10 'consul reload'
```

### Sidecar Proxy Issues

```bash
# Check sidecar status
ssh -J admin@$BASTION_IP admin@172.16.1.10 'systemctl status consul-sidecar'

# View Envoy logs
ssh -J admin@$BASTION_IP admin@172.16.1.10 'journalctl -u consul-sidecar -f'

# Restart sidecar
ssh -J admin@$BASTION_IP admin@172.16.1.10 'sudo systemctl restart consul-sidecar'
```

### Connection Blocked by Intention

```bash
# Check if connection is allowed
ssh admin@$BASTION_IP 'consul intention check web postgres'

# View all intentions
ssh admin@$BASTION_IP 'consul intention list'

# Add missing intention
ssh admin@$BASTION_IP 'consul intention create -allow web postgres'
```

### Consul Server Not Accessible

```bash
# Check if Consul is running
ssh admin@$BASTION_IP 'systemctl status consul'

# Check firewall
ssh admin@$BASTION_IP 'sudo ufw status'

# Test connectivity
ssh admin@$BASTION_IP 'curl localhost:8500/v1/status/leader'
```

## Security Best Practices

### 1. Enable ACLs (Production)

```bash
# Bootstrap ACL system
ssh admin@$BASTION_IP 'consul acl bootstrap'

# Save the token securely
# Update /etc/consul.d/server.hcl with token
```

### 2. Enable mTLS for Consul Communications

```bash
# Already enabled in Connect mesh
# For Consul gossip, add TLS certificates
```

### 3. Use Zero-Trust Intentions

```bash
# Start with deny-all
ssh admin@$BASTION_IP 'consul intention create -deny "*" "*"'

# Explicitly allow each service communication
ssh admin@$BASTION_IP 'consul intention create -allow web postgres'
```

### 4. Restrict Consul UI Access

Update bastion firewall to only allow Consul UI from VPN:

```hcl
# In main.tf bastion firewall
rule {
  direction  = "in"
  protocol   = "tcp"
  port       = "8500"
  source_ips = ["192.168.100.0/24"]  # Only VPN clients
}
```

## Monitoring

### Check Service Health

```bash
# All services
ssh admin@$BASTION_IP 'consul catalog services'

# Specific service with health
ssh admin@$BASTION_IP 'consul catalog nodes -service=web -detailed'
```

### View Metrics

Envoy exposes metrics on port 19000:

```bash
ssh -J admin@$BASTION_IP admin@172.16.1.10 'curl localhost:19000/stats/prometheus'
```

### Service Mesh Traffic

```bash
# View active connections
ssh -J admin@$BASTION_IP admin@172.16.1.10 'curl localhost:19000/clusters'

# View connection stats
ssh -J admin@$BASTION_IP admin@172.16.1.10 'curl localhost:19000/stats | grep upstream_cx'
```

## Advanced Features

### Canary Deployments

```hcl
# service-splitter for traffic splitting
Kind = "service-splitter"
Name = "web"
Splits = [
  {
    Weight  = 90
    Service = "web-v1"
  },
  {
    Weight  = 10
    Service = "web-v2"
  },
]
```

### Circuit Breaking

```hcl
# service-defaults for circuit breaker
Kind = "service-defaults"
Name = "postgres"
UpstreamConfig = {
  Defaults = {
    Limits = {
      MaxConnections = 100
      MaxPendingRequests = 50
    }
  }
}
```

### L7 Traffic Routing

```hcl
# service-router for path-based routing
Kind = "service-router"
Name = "api"
Routes = [
  {
    Match {
      HTTP {
        PathPrefix = "/v2/"
      }
    }
    Destination {
      Service = "api-v2"
    }
  }
]
```

## Terraform Outputs

View all Consul information:

```bash
terraform output consul_ui_url
terraform output consul_management_commands
terraform output service_mesh_summary
```

## Related Documentation

- **MICRO-SEGMENTATION-GUIDE.md** - Option 3 details
- **SERVICE-MESH-VMS.md** - Consul architecture
- **AUTOMATION-GUIDE.md** - Ansible integration

## Getting Help

### Check Consul Version

```bash
ssh admin@$BASTION_IP 'consul version'
```

### Official Documentation

- Consul Docs: https://www.consul.io/docs
- Service Mesh: https://www.consul.io/docs/connect
- Intentions: https://www.consul.io/docs/connect/intentions

### Common Issues

**Issue**: Services not registering  
**Solution**: Check Consul agent logs, verify network connectivity to server

**Issue**: Sidecar proxy won't start  
**Solution**: Ensure Envoy is installed, check service definition syntax

**Issue**: Connection refused through mesh  
**Solution**: Check intentions allow the connection, verify sidecar is running

---

**Next Steps:**
1. ✅ Deploy infrastructure: `terraform apply`
2. ✅ Wait for services to register (~30 seconds)
3. ✅ Configure intentions: `ssh admin@$BASTION_IP '/usr/local/bin/setup-consul-intentions.sh'`
4. ✅ Access UI: `http://$BASTION_IP:8500/ui`
5. ✅ Test connectivity: `./consul-manage.sh $BASTION_IP`
