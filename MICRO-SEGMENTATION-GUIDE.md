# Micro-Segmentation Implementation Guide

## What is Micro-Segmentation?

**Traditional Segmentation (What you have now):**
```
┌─────────────────────────────────────┐
│  Application Subnet (172.16.1.0/24) │
│  ┌──────┐  ┌──────┐  ┌──────┐      │
│  │Web-1 │  │Web-2 │  │API-1 │      │
│  └──────┘  └──────┘  └──────┘      │
│  All can talk to each other         │
└─────────────────────────────────────┘
```

**Micro-Segmentation (Zero-Trust):**
```
┌─────────────────────────────────────┐
│  Application Subnet (172.16.1.0/24) │
│  ┌──────┐  ┌──────┐  ┌──────┐      │
│  │Web-1 │━━│Web-2 │  │API-1 │      │
│  └──┬───┘  └──────┘  └───┬──┘      │
│     │                     │         │
│     └─────────────────────┘         │
│     Only explicit paths allowed     │
└─────────────────────────────────────┘
```

## Implementation Options

### Option 1: Hetzner Cloud Firewalls Per Server (Recommended)

**Pros:**
- Managed by Hetzner (no host overhead)
- Stateful firewall rules
- Changes via Terraform
- Works at network edge

**Cons:**
- Limited to 50 rules per firewall
- Cannot inspect application layer
- No dynamic policy updates

**Implementation:**

```terraform
# Define your application topology
locals {
  # Map of servers and their allowed connections
  app_topology = {
    web_servers = {
      count = 2
      allows_from = ["0.0.0.0/0"]  # Internet
      allows_to = ["api_servers"]   # Internal services
      ports_in = [80, 443]
      ports_out = [8080]
    }
    api_servers = {
      count = 2
      allows_from = ["web_servers"]
      allows_to = ["database_servers"]
      ports_in = [8080]
      ports_out = [5432]
    }
    database_servers = {
      count = 2
      allows_from = ["api_servers"]
      allows_to = []  # No outbound except updates
      ports_in = [5432]
      ports_out = []
    }
  }
}

# Create individual firewall for each web server
resource "hcloud_firewall" "web_server" {
  count = 2
  name  = "${local.resource_prefix}-web-${count.index + 1}-fw"

  # Public access
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "443"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  # SSH from bastion only
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "22"
    source_ips = ["${hcloud_server.bastion.ipv4_address}/32"]
  }

  # Outbound to API servers only
  rule {
    direction       = "out"
    protocol        = "tcp"
    port            = "8080"
    destination_ips = [for s in hcloud_server.api : "${[for net in s.network : net.ip][0]}/32"]
  }

  # DNS and HTTPS for updates
  rule {
    direction       = "out"
    protocol        = "tcp"
    port            = "443"
    destination_ips = ["0.0.0.0/0", "::/0"]
  }

  rule {
    direction       = "out"
    protocol        = "udp"
    port            = "53"
    destination_ips = ["0.0.0.0/0", "::/0"]
  }
}

# API servers - accept only from web, connect only to DB
resource "hcloud_firewall" "api_server" {
  count = 2
  name  = "${local.resource_prefix}-api-${count.index + 1}-fw"

  # Accept from web servers only
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "8080"
    source_ips = [for s in hcloud_server.web : "${[for net in s.network : net.ip][0]}/32"]
  }

  # SSH from bastion only
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "22"
    source_ips = ["${hcloud_server.bastion.ipv4_address}/32"]
  }

  # Outbound to database servers only
  rule {
    direction       = "out"
    protocol        = "tcp"
    port            = "5432"
    destination_ips = [for s in hcloud_server.database : "${[for net in s.network : net.ip][0]}/32"]
  }

  # Updates only
  rule {
    direction       = "out"
    protocol        = "tcp"
    port            = "443"
    destination_ips = ["0.0.0.0/0", "::/0"]
  }
}

# Database servers - accept only from API, no outbound except updates
resource "hcloud_firewall" "database_server" {
  count = 2
  name  = "${local.resource_prefix}-db-${count.index + 1}-fw"

  # Accept PostgreSQL only from API servers
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "5432"
    source_ips = [for s in hcloud_server.api : "${[for net in s.network : net.ip][0]}/32"]
  }

  # SSH from bastion only
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "22"
    source_ips = ["${hcloud_server.bastion.ipv4_address}/32"]
  }

  # Minimal outbound - updates only
  rule {
    direction       = "out"
    protocol        = "tcp"
    port            = "443"
    destination_ips = ["0.0.0.0/0", "::/0"]
  }

  rule {
    direction       = "out"
    protocol        = "tcp"
    port            = "80"
    destination_ips = ["0.0.0.0/0", "::/0"]
  }
}
```

### Option 2: Host-Based Firewalls (UFW)

Add to your cloud-init configuration:

```yaml
#cloud-config
runcmd:
  # Install and configure UFW
  - apt-get install -y ufw
  
  # Default deny
  - ufw default deny incoming
  - ufw default deny outgoing
  
  # Allow SSH from bastion only
  - ufw allow from 172.16.0.10 to any port 22
  
  # Allow specific application traffic
  # For web server - allow public HTTPS, allow to API servers
  - ufw allow 443/tcp
  - ufw allow out to 172.16.1.20 port 8080 proto tcp
  - ufw allow out to 172.16.1.21 port 8080 proto tcp
  
  # For API server - allow from web servers, allow to DB servers
  - ufw allow from 172.16.1.10 to any port 8080 proto tcp
  - ufw allow from 172.16.1.11 to any port 8080 proto tcp
  - ufw allow out to 172.16.2.10 port 5432 proto tcp
  - ufw allow out to 172.16.2.11 port 5432 proto tcp
  
  # For database - allow from API servers only
  - ufw allow from 172.16.1.20 to any port 5432 proto tcp
  - ufw allow from 172.16.1.21 to any port 5432 proto tcp
  
  # Allow DNS and updates
  - ufw allow out 53
  - ufw allow out 80/tcp
  - ufw allow out 443/tcp
  
  # Enable
  - ufw --force enable
```

### Option 3: Combined Approach (Best Security)

Use **both** Hetzner Cloud Firewalls AND host-based UFW:

1. **Hetzner Firewall**: Coarse-grained network-level filtering
2. **UFW on each host**: Fine-grained application-aware rules

**Benefits:**
- Defense in depth (two layers)
- Hetzner blocks at network edge (saves host resources)
- UFW provides application-specific control
- If one is misconfigured, the other still protects

### Option 4: Software-Defined Micro-Segmentation (Advanced)

For dynamic workloads, use:

#### A) **Cilium (eBPF-based)**

```yaml
# CiliumNetworkPolicy - Allow web to API only
apiVersion: "cilium.io/v2"
kind: CiliumNetworkPolicy
metadata:
  name: "web-to-api"
spec:
  endpointSelector:
    matchLabels:
      app: web
  egress:
  - toEndpoints:
    - matchLabels:
        app: api
    toPorts:
    - ports:
      - port: "8080"
        protocol: TCP
```

**Pros:**
- Identity-based (not IP-based)
- Deep visibility and monitoring
- Automatic service discovery
- API-aware filtering (HTTP, gRPC, Kafka, etc.)

**Cons:**
- Requires Kubernetes or containerized workloads
- Learning curve
- Additional infrastructure

#### B) **Consul Service Mesh**

```hcl
# Intention: Allow web to call API
service_intentions {
  source      = "web"
  destination = "api"
  action      = "allow"
}

# Intention: Allow API to call database
service_intentions {
  source      = "api"
  destination = "postgres"
  action      = "allow"
}
```

**Pros:**
- Works with VMs and containers
- Service-to-service authentication (mTLS)
- Dynamic service discovery
- Traffic management (retries, timeouts)

**Cons:**
- Requires Consul infrastructure
- Agents on every server
- Additional operational complexity

### Option 3: Consul Service Mesh (Best for VMs)

**Why Consul is ideal for VM micro-segmentation:**
- VM-native design (no Kubernetes required)
- Lightweight agent on each VM
- Identity-based security with mTLS
- Service discovery built-in
- Intentions for zero-trust policies
- Works perfectly with your current Terraform setup

**Pros:**
- ✅ Designed for VMs (not container-first)
- ✅ Simple service-to-service policies (intentions)
- ✅ Automatic mTLS between services
- ✅ Built-in service discovery
- ✅ Native integration with Terraform
- ✅ Can inspect/route L7 traffic (HTTP, gRPC)
- ✅ Multi-datacenter support

**Cons:**
- Requires Consul server (can run on bastion)
- Agent on every VM (lightweight ~40MB RAM)
- Learning curve for new tool

#### Architecture

```
┌─────────────────────────────────────────────────┐
│  Bastion (172.16.0.10)                          │
│  ┌─────────────────────────────────┐            │
│  │  Consul Server                  │            │
│  │  - Service Registry             │            │
│  │  - Policy Engine                │            │
│  │  - Certificate Authority (CA)   │            │
│  └─────────────────────────────────┘            │
└─────────────────────────────────────────────────┘
                      │
        ┌─────────────┼─────────────┐
        │             │             │
┌───────▼──────┐ ┌───▼─────────┐ ┌─▼──────────────┐
│ Web Server   │ │ API Server  │ │ Database       │
│ 172.16.1.10  │ │ 172.16.1.20 │ │ 172.16.2.10    │
│              │ │             │ │                │
│ ┌──────────┐ │ │ ┌─────────┐ │ │ ┌────────────┐ │
│ │Consul    │ │ │ │Consul   │ │ │ │Consul      │ │
│ │Agent     │ │ │ │Agent    │ │ │ │Agent       │ │
│ └────┬─────┘ │ │ └────┬────┘ │ │ └─────┬──────┘ │
│      │       │ │      │      │ │       │        │
│ ┌────▼─────┐ │ │ ┌────▼────┐ │ │ ┌─────▼──────┐ │
│ │Envoy     │ │ │ │Envoy    │ │ │ │Envoy       │ │
│ │Proxy     │─┼─┼─│Proxy    │─┼─┼─│Proxy       │ │
│ │(Sidecar) │ │ │ │(Sidecar)│ │ │ │(Sidecar)   │ │
│ └────┬─────┘ │ │ └────┬────┘ │ │ └─────┬──────┘ │
│      │       │ │      │      │ │       │        │
│ ┌────▼─────┐ │ │ ┌────▼────┐ │ │ ┌─────▼──────┐ │
│ │Web App   │ │ │ │API App  │ │ │ │PostgreSQL  │ │
│ │:80       │ │ │ │:8080    │ │ │ │:5432       │ │
│ └──────────┘ │ │ └─────────┘ │ │ └────────────┘ │
└──────────────┘ └─────────────┘ └────────────────┘
    │                  │                  │
    └──────────────────┴──────────────────┘
              mTLS encrypted mesh
```

#### Implementation Steps

**1. Install Consul Server on Bastion**

Add to your `main.tf` bastion user_data:

```terraform
resource "hcloud_server" "bastion" {
  # ... existing config ...
  
  user_data = <<-EOF
    #cloud-config
    package_update: true
    package_upgrade: true
    packages:
      - wireguard
      - fail2ban
      - ufw
      - qrencode
      - htop
      - vim
      - curl
      - wget
      - git
      - unzip
    
    write_files:
      - path: /etc/consul.d/server.hcl
        owner: root:root
        permissions: '0644'
        content: |
          datacenter = "${var.environment}"
          data_dir = "/opt/consul"
          server = true
          bootstrap_expect = 1
          bind_addr = "172.16.0.10"
          client_addr = "0.0.0.0"
          
          ui_config {
            enabled = true
          }
          
          connect {
            enabled = true
          }
          
          ports {
            grpc = 8502
          }
    
    runcmd:
      # ... existing WireGuard setup ...
      
      # Install Consul
      - |
        CONSUL_VERSION="1.17.0"
        cd /tmp
        wget https://releases.hashicorp.com/consul/$${CONSUL_VERSION}/consul_$${CONSUL_VERSION}_linux_amd64.zip
        unzip consul_$${CONSUL_VERSION}_linux_amd64.zip
        mv consul /usr/local/bin/
        rm consul_$${CONSUL_VERSION}_linux_amd64.zip
      
      # Create Consul user and directories
      - useradd --system --home /etc/consul.d --shell /bin/false consul
      - mkdir -p /opt/consul /etc/consul.d
      - chown -R consul:consul /opt/consul /etc/consul.d
      
      # Create Consul systemd service
      - |
        cat > /etc/systemd/system/consul.service <<CONSUL_EOF
        [Unit]
        Description=Consul Service Discovery and Configuration
        After=network.target
        
        [Service]
        User=consul
        Group=consul
        ExecStart=/usr/local/bin/consul agent -config-dir=/etc/consul.d/
        ExecReload=/bin/kill -HUP \$MAINPID
        KillMode=process
        Restart=on-failure
        
        [Install]
        WantedBy=multi-user.target
        CONSUL_EOF
      
      # Start Consul
      - systemctl daemon-reload
      - systemctl enable consul
      - systemctl start consul
      
      # Allow Consul ports in UFW
      - ufw allow 8500/tcp  # HTTP API
      - ufw allow 8501/tcp  # HTTPS API
      - ufw allow 8502/tcp  # gRPC
      - ufw allow 8600/tcp  # DNS
      - ufw allow 8600/udp  # DNS
      - ufw allow 8300/tcp  # Server RPC
      - ufw allow 8301/tcp  # Serf LAN
      - ufw allow 8301/udp  # Serf LAN
      - ufw allow 8302/tcp  # Serf WAN
      - ufw allow 8302/udp  # Serf WAN
  EOF
}
```

**2. Install Consul Client on Application Servers**

```terraform
resource "hcloud_server" "application" {
  count = var.application_server_count
  # ... existing config ...
  
  user_data = <<-EOF
    #cloud-config
    package_update: true
    package_upgrade: true
    packages:
      - unzip
    
    write_files:
      - path: /etc/consul.d/client.hcl
        owner: root:root
        permissions: '0644'
        content: |
          datacenter = "${var.environment}"
          data_dir = "/opt/consul"
          server = false
          bind_addr = "{{ GetPrivateIP }}"
          retry_join = ["172.16.0.10"]
          
          connect {
            enabled = true
          }
          
          ports {
            grpc = 8502
          }
      
      - path: /etc/consul.d/web-service.hcl
        owner: root:root
        permissions: '0644'
        content: |
          service {
            name = "web"
            id = "web-${count.index + 1}"
            port = 80
            
            tags = ["production", "web-server"]
            
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
            
            check {
              id       = "web-http"
              name     = "HTTP Check"
              http     = "http://localhost:80/health"
              interval = "10s"
              timeout  = "1s"
            }
          }
    
    runcmd:
      # Install Consul
      - |
        CONSUL_VERSION="1.17.0"
        cd /tmp
        wget https://releases.hashicorp.com/consul/$${CONSUL_VERSION}/consul_$${CONSUL_VERSION}_linux_amd64.zip
        unzip consul_$${CONSUL_VERSION}_linux_amd64.zip
        mv consul /usr/local/bin/
        rm consul_$${CONSUL_VERSION}_linux_amd64.zip
      
      # Install Envoy (for Connect sidecar)
      - |
        curl -L https://func-e.io/install.sh | bash -s -- -b /usr/local/bin
        func-e use 1.28.0
        cp ~/.func-e/versions/1.28.0/bin/envoy /usr/local/bin/
      
      # Create Consul user and directories
      - useradd --system --home /etc/consul.d --shell /bin/false consul
      - mkdir -p /opt/consul /etc/consul.d
      - chown -R consul:consul /opt/consul /etc/consul.d
      
      # Create Consul systemd service
      - |
        cat > /etc/systemd/system/consul.service <<CONSUL_EOF
        [Unit]
        Description=Consul Agent
        After=network.target
        
        [Service]
        User=consul
        Group=consul
        ExecStart=/usr/local/bin/consul agent -config-dir=/etc/consul.d/
        ExecReload=/bin/kill -HUP \$MAINPID
        KillMode=process
        Restart=on-failure
        
        [Install]
        WantedBy=multi-user.target
        CONSUL_EOF
      
      # Start Consul
      - systemctl daemon-reload
      - systemctl enable consul
      - systemctl start consul
      
      # Wait for Consul to be ready
      - sleep 10
      
      # Start sidecar proxy
      - |
        cat > /etc/systemd/system/consul-sidecar.service <<SIDECAR_EOF
        [Unit]
        Description=Consul Connect Sidecar Proxy
        After=consul.service
        Requires=consul.service
        
        [Service]
        ExecStart=/usr/local/bin/consul connect proxy -sidecar-for web-${count.index + 1}
        Restart=always
        
        [Install]
        WantedBy=multi-user.target
        SIDECAR_EOF
      
      - systemctl daemon-reload
      - systemctl enable consul-sidecar
      - systemctl start consul-sidecar
      
      # Set hostname
      - hostnamectl set-hostname ${local.resource_prefix}-app-${count.index + 1}
  EOF
}
```

**3. Install Consul Client on Database Servers**

```terraform
resource "hcloud_server" "database" {
  count = var.database_server_count
  # ... existing config ...
  
  user_data = <<-EOF
    #cloud-config
    package_update: true
    package_upgrade: true
    packages:
      - postgresql
      - unzip
    
    write_files:
      - path: /etc/consul.d/client.hcl
        owner: root:root
        permissions: '0644'
        content: |
          datacenter = "${var.environment}"
          data_dir = "/opt/consul"
          server = false
          bind_addr = "{{ GetPrivateIP }}"
          retry_join = ["172.16.0.10"]
          
          connect {
            enabled = true
          }
          
          ports {
            grpc = 8502
          }
      
      - path: /etc/consul.d/postgres-service.hcl
        owner: root:root
        permissions: '0644'
        content: |
          service {
            name = "postgres"
            id = "postgres-${count.index + 1}"
            port = 5432
            
            tags = ["production", "database"]
            
            connect {
              sidecar_service {}
            }
            
            check {
              id       = "postgres-tcp"
              name     = "PostgreSQL TCP Check"
              tcp      = "localhost:5432"
              interval = "10s"
              timeout  = "1s"
            }
          }
      
      - path: /usr/local/bin/setup-postgres.sh
        owner: root:root
        permissions: '0755'
        content: |
          #!/bin/bash
          set -euo pipefail
          
          # Start postgres (in case not yet running)
          systemctl start postgresql || true
          # Find postgres config directory
          PGCONF_DIR=$$(ls -d /etc/postgresql/*/main 2>/dev/null | head -n1 || true)
          if [ -z "$$PGCONF_DIR" ]; then
            echo "No postgres config dir found, exiting"
            exit 0
          fi
          # Ensure postgres listens on localhost and private network
          if grep -q '^#listen_addresses' "$$PGCONF_DIR/postgresql.conf" 2>/dev/null; then
            sed -i "s/^#listen_addresses.*/listen_addresses = '127.0.0.1,172.16.0.0\/16'/" "$$PGCONF_DIR/postgresql.conf"
          elif grep -q '^listen_addresses' "$$PGCONF_DIR/postgresql.conf" 2>/dev/null; then
            sed -i "s/^listen_addresses.*/listen_addresses = '127.0.0.1,172.16.0.0\/16'/" "$$PGCONF_DIR/postgresql.conf"
          else
            echo "listen_addresses = '127.0.0.1,172.16.0.0/16'" >> "$$PGCONF_DIR/postgresql.conf"
          fi
          # Add PG HBA entry to allow private network access with md5
          if ! grep -q '^host\s\+all\s\+all\s\+172.16.0.0/16\s\+md5' "$$PGCONF_DIR/pg_hba.conf" 2>/dev/null; then
            echo "host    all             all             172.16.0.0/16            md5" >> "$$PGCONF_DIR/pg_hba.conf"
          fi
          # Restart postgres to apply changes
          systemctl restart postgresql
          # Create credentials and database
          CREDFILE=/root/postgres-credentials.txt
          umask 077
          : > "$$CREDFILE"
          POSTGRES_PASS=$$(openssl rand -hex 16)
          APP_USER="app_user"
          APP_DB="app_db"
          APP_PASS=$$(openssl rand -hex 16)
          sudo -u postgres psql -v ON_ERROR_STOP=1 <<SQL
          ALTER USER postgres WITH PASSWORD '$${POSTGRES_PASS}';
          CREATE USER $${APP_USER} WITH ENCRYPTED PASSWORD '$${APP_PASS}';
          CREATE DATABASE $${APP_DB} WITH OWNER $${APP_USER};
          SQL
          {
            echo "postgres:$${POSTGRES_PASS}"
            echo "$${APP_USER}:$${APP_PASS}"
            echo "database:$${APP_DB}"
          } >> "$$CREDFILE"
          chmod 600 "$$CREDFILE"
          echo "PostgreSQL configured. Credentials saved to $$CREDFILE"
    
    runcmd:
      # Install Consul
      - |
        CONSUL_VERSION="1.17.0"
        cd /tmp
        wget https://releases.hashicorp.com/consul/$${CONSUL_VERSION}/consul_$${CONSUL_VERSION}_linux_amd64.zip
        unzip consul_$${CONSUL_VERSION}_linux_amd64.zip
        mv consul /usr/local/bin/
        rm consul_$${CONSUL_VERSION}_linux_amd64.zip
      
      # Install Envoy
      - |
        curl -L https://func-e.io/install.sh | bash -s -- -b /usr/local/bin
        func-e use 1.28.0
        cp ~/.func-e/versions/1.28.0/bin/envoy /usr/local/bin/
      
      # Create Consul user and directories
      - useradd --system --home /etc/consul.d --shell /bin/false consul
      - mkdir -p /opt/consul /etc/consul.d
      - chown -R consul:consul /opt/consul /etc/consul.d
      
      # Create Consul systemd service
      - |
        cat > /etc/systemd/system/consul.service <<CONSUL_EOF
        [Unit]
        Description=Consul Agent
        After=network.target
        
        [Service]
        User=consul
        Group=consul
        ExecStart=/usr/local/bin/consul agent -config-dir=/etc/consul.d/
        ExecReload=/bin/kill -HUP \$MAINPID
        KillMode=process
        Restart=on-failure
        
        [Install]
        WantedBy=multi-user.target
        CONSUL_EOF
      
      # Start Consul
      - systemctl daemon-reload
      - systemctl enable consul
      - systemctl start consul
      
      # Setup PostgreSQL
      - bash /usr/local/bin/setup-postgres.sh
      
      # Wait for Consul to be ready
      - sleep 10
      
      # Start sidecar proxy
      - |
        cat > /etc/systemd/system/consul-sidecar.service <<SIDECAR_EOF
        [Unit]
        Description=Consul Connect Sidecar Proxy
        After=consul.service
        Requires=consul.service
        
        [Service]
        ExecStart=/usr/local/bin/consul connect proxy -sidecar-for postgres-${count.index + 1}
        Restart=always
        
        [Install]
        WantedBy=multi-user.target
        SIDECAR_EOF
      
      - systemctl daemon-reload
      - systemctl enable consul-sidecar
      - systemctl start consul-sidecar
      
      # Set hostname
      - hostnamectl set-hostname ${local.resource_prefix}-db-${count.index + 1}
  EOF
}
```

**4. Configure Service Intentions (Zero-Trust Policies)**

After infrastructure is deployed, configure intentions:

```bash
# SSH to bastion
ssh admin@<bastion-ip>

# Default deny all
consul intention create -deny '*' '*'

# Allow web to API
consul intention create -allow web api

# Allow API to database
consul intention create -allow api postgres

# Allow bastion to all (for monitoring)
consul intention create -allow bastion '*'

# List all intentions
consul intention list

# Check specific intention
consul intention check web api
```

**5. Use Service Discovery in Applications**

Your applications now use Consul DNS or connect to localhost:

```bash
# Instead of hardcoding IPs:
# DATABASE_URL=postgresql://user:pass@172.16.2.10:5432/db

# Use Consul DNS:
DATABASE_URL=postgresql://user:pass@postgres.service.consul:5432/db

# Or connect through sidecar proxy (automatically mTLS):
DATABASE_URL=postgresql://user:pass@localhost:5432/db
# (The sidecar forwards localhost:5432 to actual postgres with mTLS)
```

**6. Monitoring and Troubleshooting**

```bash
# Check service health
consul catalog services
consul catalog nodes -service=web
consul catalog nodes -service=postgres

# Check intentions
consul intention list
consul intention check web api

# View Consul UI
# Open in browser: http://<bastion-ip>:8500/ui

# Check sidecar proxy status
systemctl status consul-sidecar

# View Envoy stats
curl http://localhost:19000/stats

# Debug connection issues
consul connect proxy -sidecar-for web-1 -log-level=debug
```

#### Benefits of Consul Approach

**1. Zero-Trust by Default**
```bash
# Start with deny-all
consul intention create -deny '*' '*'

# Explicitly allow each connection
consul intention create -allow web api
consul intention create -allow api postgres
```

**2. Automatic mTLS**
- All service-to-service traffic encrypted
- Certificates automatically rotated
- No manual certificate management

**3. Service Discovery**
```bash
# Services find each other by name, not IP
# Survives VM replacements, IP changes
curl http://api.service.consul/endpoint
```

**4. L7 Traffic Management**
```hcl
# service-router for canary deployments
service_router {
  name = "api"
  routes = [
    {
      match {
        http {
          path_prefix = "/v2/"
        }
      }
      destination {
        service = "api-v2"
      }
    }
  ]
}
```

**5. Health Checking**
- Automatic health checks
- Unhealthy instances removed from load balancing
- Self-healing

#### Comparison with Other Options

| Feature | Hetzner FW | UFW | Consul |
|---------|-----------|-----|--------|
| **Managed** | ✅ Yes | ❌ No | ⚠️ Self-hosted |
| **Granularity** | IP-based | IP/port-based | Service identity |
| **mTLS** | ❌ No | ❌ No | ✅ Yes |
| **Service Discovery** | ❌ No | ❌ No | ✅ Yes |
| **L7 Routing** | ❌ No | ❌ No | ✅ Yes |
| **Health Checks** | ❌ No | ❌ No | ✅ Yes |
| **Complexity** | Low | Low | Medium |
| **Best For** | Network edge | Host firewall | Service mesh |

#### When to Use Consul

**✅ Use Consul when:**
- You have 5+ microservices
- Services need to discover each other
- You want automatic mTLS
- You need L7 routing/policies
- You're planning to grow infrastructure

**❌ Skip Consul when:**
- You have 1-3 simple servers
- Static IP configuration is fine
- Basic firewall rules are enough
- You don't want operational overhead

## Practical Implementation Steps

### Phase 1: Inventory and Map (Week 1)

1. **Document all services:**
```bash
# List all servers and their roles
terraform state list | grep hcloud_server

# Map dependencies
# Create a spreadsheet:
# Service | IP | Talks To | Ports | Protocol
# web-1   | 172.16.1.10 | api-1, api-2 | 8080 | TCP
# api-1   | 172.16.1.20 | db-1 | 5432 | TCP
```

2. **Capture current traffic:**
```bash
# On each server, log connections for 24-48 hours
sudo tcpdump -i any -n 'not port 22' -w /tmp/traffic.pcap

# Analyze with
tcpdump -r /tmp/traffic.pcap -n | awk '{print $3, $5}' | sort | uniq -c
```

3. **Create dependency map:**
```
Internet → Web Servers (80, 443)
Web Servers → API Servers (8080)
API Servers → Database Servers (5432)
Database Servers → Backup Storage (8000)
All Servers → DNS (53), Updates (80, 443)
Bastion → All Servers (22)
```

### Phase 2: Implement Gradually (Week 2-4)

**Day 1-3: Non-Production First**
```bash
# Apply to test environment
cd hzlandingzone-dev
terraform apply

# Validate application still works
curl https://test.example.com/health
```

**Day 4-7: Add Monitoring**
```bash
# Monitor blocked connections
sudo ufw status numbered
sudo iptables -L -v -n | grep DROP

# Check application logs for connection errors
journalctl -u your-app --since "1 hour ago" | grep -i "connection refused\|timeout"
```

**Week 2: Implement in Production (Blue-Green)**
```bash
# Create new servers with micro-segmentation
terraform apply -target=hcloud_server.web_v2

# Switch traffic gradually
# Monitor for issues
# Rollback plan ready
```

**Week 3-4: Iterate and Refine**
- Fine-tune rules based on actual traffic
- Remove overly permissive rules
- Add alerting for blocked traffic

### Phase 3: Automate and Monitor (Ongoing)

1. **Terraform Module:**
```terraform
module "micro_segment_server" {
  source = "./modules/micro-segmented-server"
  
  name = "web-1"
  allowed_inbound = [
    { from = "0.0.0.0/0", port = 443, protocol = "tcp" }
  ]
  allowed_outbound = [
    { to = "172.16.1.20/32", port = 8080, protocol = "tcp" },
    { to = "172.16.1.21/32", port = 8080, protocol = "tcp" }
  ]
}
```

2. **Monitoring and Alerting:**
```bash
# Alert on blocked traffic exceeding threshold
# Alert on new services discovered
# Regular compliance audits
```

## Comparison Matrix

| Approach | Complexity | Security Level | Performance Impact | Cost |
|----------|-----------|----------------|-------------------|------|
| Current (Subnet FW) | Low | Medium | None | Included |
| Per-Server Hetzner FW | Medium | High | None | Included |
| UFW on hosts | Medium | High | Minimal | Free |
| Both (Defense in Depth) | Medium-High | Very High | Minimal | Free |
| Cilium/Service Mesh | High | Very High | Low-Medium | Infrastructure cost |

## Recommended Path for Your Setup

**Immediate (This Week):**
1. Keep your current subnet-level firewalls
2. Add UFW rules on each server for additional control
3. Start with most critical servers (databases first)

**Short-term (Next Month):**
1. Migrate to per-server Hetzner Cloud Firewalls
2. Use Terraform to define explicit server-to-server rules
3. Implement monitoring and alerting

**Long-term (3-6 Months):**
1. If moving to Kubernetes, implement Cilium
2. If staying on VMs, consider Consul Connect
3. Implement automated compliance scanning

## Example: Migrating Your Current Setup

Here's a complete example for your landing zone:

```terraform
# micro-segmented-main.tf

# Web servers can only talk to API servers
resource "hcloud_server" "web" {
  count = 2
  name = "${local.resource_prefix}-web-${count.index + 1}"
  # ... other config ...
  
  firewall_ids = [hcloud_firewall.web[count.index].id]
  
  user_data = templatefile("${path.module}/cloud-init/web-server.yaml", {
    api_server_ips = [for s in hcloud_server.api : [for net in s.network : net.ip][0]]
    bastion_ip = [for net in hcloud_server.bastion.network : net.ip][0]
  })
}

# API servers can only talk to database servers
resource "hcloud_server" "api" {
  count = 2
  name = "${local.resource_prefix}-api-${count.index + 1}"
  # ... other config ...
  
  firewall_ids = [hcloud_firewall.api[count.index].id]
  
  user_data = templatefile("${path.module}/cloud-init/api-server.yaml", {
    web_server_ips = [for s in hcloud_server.web : [for net in s.network : net.ip][0]]
    db_server_ips = [for s in hcloud_server.database : [for net in s.network : net.ip][0]]
    bastion_ip = [for net in hcloud_server.bastion.network : net.ip][0]
  })
}

# Database servers accept only from API servers
resource "hcloud_server" "database" {
  count = 2
  name = "${local.resource_prefix}-db-${count.index + 1}"
  # ... other config ...
  
  firewall_ids = [hcloud_firewall.database[count.index].id]
  
  user_data = templatefile("${path.module}/cloud-init/db-server.yaml", {
    api_server_ips = [for s in hcloud_server.api : [for net in s.network : net.ip][0]]
    bastion_ip = [for net in hcloud_server.bastion.network : net.ip][0]
  })
}
```

Cloud-init template for UFW (cloud-init/web-server.yaml):

```yaml
#cloud-config
runcmd:
  # UFW setup for web server
  - apt-get install -y ufw
  - ufw default deny incoming
  - ufw default deny outgoing
  
  # Public access
  - ufw allow 80/tcp
  - ufw allow 443/tcp
  
  # SSH from bastion
  - ufw allow from ${bastion_ip} to any port 22
  
  # Outbound to API servers only
  %{ for ip in api_server_ips ~}
  - ufw allow out to ${ip} port 8080 proto tcp
  %{ endfor ~}
  
  # DNS and updates
  - ufw allow out 53
  - ufw allow out 80/tcp
  - ufw allow out 443/tcp
  
  - ufw --force enable
```

## Testing Your Micro-Segmentation

```bash
# From bastion, test connectivity matrix

# Should work: Web to API
ssh admin@172.16.1.10 "nc -zv 172.16.1.20 8080"

# Should work: API to Database
ssh admin@172.16.1.20 "nc -zv 172.16.2.10 5432"

# Should FAIL: Web to Database (bypassing API)
ssh admin@172.16.1.10 "nc -zv 172.16.2.10 5432"

# Should FAIL: Database to anything except updates
ssh admin@172.16.2.10 "nc -zv 172.16.1.10 443"
```

## Troubleshooting

**Issue: Application can't connect after implementing micro-segmentation**

```bash
# Check UFW logs
sudo tail -f /var/log/ufw.log

# Check Hetzner firewall via API
curl -H "Authorization: Bearer $HCLOUD_TOKEN" \
  https://api.hetzner.cloud/v1/servers/SERVER_ID

# Temporarily disable UFW to isolate issue
sudo ufw disable
# Test connection
# Re-enable
sudo ufw enable
```

**Issue: Too many firewall rules, hitting limits**

- Hetzner limit: 50 rules per firewall
- Solution: Use UFW for granular rules, Hetzner for coarse filtering
- Or: Use VLANs to create more isolation

## Summary

**Start Simple:**
1. Document current traffic patterns
2. Add UFW rules to databases first (highest value targets)
3. Expand to application servers
4. Finally web servers

**Key Principle:**
> "Default deny, explicit allow"

Every connection should be intentional and documented. If you can't explain why a connection exists, it probably shouldn't.

---
Last Updated: November 8, 2025
