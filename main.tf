terraform {
  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = ">= 1.51.0"
    }
  }
  required_version = ">= 1.5.0"
}

provider "hcloud" {
  token = var.hcloud_token
}

# Variables
variable "hcloud_token" {
  description = "Hetzner Cloud API token"
  type        = string
  sensitive   = true
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "prod"
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "landing-zone"
}

variable "network_zone" {
  description = "Network zone (eu-central or us-east)"
  type        = string
  default     = "eu-central"
}

variable "primary_location" {
  description = "Primary Hetzner datacenter location"
  type        = string
  default     = "nbg1"
}

variable "ssh_public_key_path" {
  description = "Path to SSH public key"
  type        = string
  default     = "./id_ed25519_hetzner_cloud_k3s.pub"
}

variable "allowed_ssh_ips" {
  description = "List of IP addresses allowed to SSH (CIDR notation)"
  type        = list(string)
  default     = ["0.0.0.0/0", "::/0"]
}

variable "tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default = {
    ManagedBy   = "Terraform"
    Environment = "Landing-Zone"
  }
}

variable "application_server_count" {
  description = "Number of application servers to create"
  type        = number
  default     = 1

}

variable "database_server_count" {
  description = "Number of database servers to create"
  type        = number
  default     = 1

}

# Locals
locals {
  resource_prefix = "${var.project_name}-${var.environment}"
  common_labels = merge(
    var.tags,
    {
      "project"     = var.project_name
      "environment" = var.environment
    }
  )
}

# SSH Key Management
resource "hcloud_ssh_key" "landing_zone_key" {
  name       = "${local.resource_prefix}-ssh-key"
  public_key = file(var.ssh_public_key_path)
  labels     = local.common_labels
}

# Network Configuration
resource "hcloud_network" "main" {
  name     = "${local.resource_prefix}-network"
  ip_range = "172.16.0.0/16"
  labels   = local.common_labels
}

# Management Subnet (for bastion, management tools)
resource "hcloud_network_subnet" "management" {
  type         = "cloud"
  network_id   = hcloud_network.main.id
  network_zone = var.network_zone
  ip_range     = "172.16.0.0/24"
}

# Application Subnet (for app servers, databases)
resource "hcloud_network_subnet" "application" {
  type         = "cloud"
  network_id   = hcloud_network.main.id
  network_zone = var.network_zone
  ip_range     = "172.16.1.0/24"
}

# Services Subnet (for shared services)
resource "hcloud_network_subnet" "services" {
  type         = "cloud"
  network_id   = hcloud_network.main.id
  network_zone = var.network_zone
  ip_range     = "172.16.2.0/24"
}

# DMZ Subnet (for public-facing services)
resource "hcloud_network_subnet" "dmz" {
  type         = "cloud"
  network_id   = hcloud_network.main.id
  network_zone = var.network_zone
  ip_range     = "172.16.10.0/24"
}

# Firewall Rules
# Bastion/Management Firewall
resource "hcloud_firewall" "bastion" {
  name   = "${local.resource_prefix}-bastion-fw"
  labels = local.common_labels

  # SSH access
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "22"
    source_ips = var.allowed_ssh_ips
  }

  # WireGuard VPN
  rule {
    direction  = "in"
    protocol   = "udp"
    port       = "51820"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  # ICMP (ping)
  rule {
    direction  = "in"
    protocol   = "icmp"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  # Consul ports from private network
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "8300"
    source_ips = ["172.16.0.0/16"]
  }

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "8301"
    source_ips = ["172.16.0.0/16"]
  }

  rule {
    direction  = "in"
    protocol   = "udp"
    port       = "8301"
    source_ips = ["172.16.0.0/16"]
  }

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "8500"
    source_ips = ["172.16.0.0/16", "192.168.100.0/24"]
  }

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "8502"
    source_ips = ["172.16.0.0/16"]
  }

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "8600"
    source_ips = ["172.16.0.0/16"]
  }

  rule {
    direction  = "in"
    protocol   = "udp"
    port       = "8600"
    source_ips = ["172.16.0.0/16"]
  }

  # Allow all outbound
  rule {
    direction       = "out"
    protocol        = "tcp"
    port            = "any"
    destination_ips = ["0.0.0.0/0", "::/0"]
  }

  rule {
    direction       = "out"
    protocol        = "udp"
    port            = "any"
    destination_ips = ["0.0.0.0/0", "::/0"]
  }

  rule {
    direction       = "out"
    protocol        = "icmp"
    destination_ips = ["0.0.0.0/0", "::/0"]
  }
}

# Application Firewall (restrictive)
resource "hcloud_firewall" "application" {
  name   = "${local.resource_prefix}-app-fw"
  labels = local.common_labels

  # HTTP/HTTPS from anywhere (adjust as needed)
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "80"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "443"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  # SSH only from private network
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "22"
    source_ips = ["172.16.0.0/16"]
  }

  # Consul ports from private network
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "8301"
    source_ips = ["172.16.0.0/16"]
  }

  rule {
    direction  = "in"
    protocol   = "udp"
    port       = "8301"
    source_ips = ["172.16.0.0/16"]
  }

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "8502"
    source_ips = ["172.16.0.0/16"]
  }

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "8600"
    source_ips = ["172.16.0.0/16"]
  }

  rule {
    direction  = "in"
    protocol   = "udp"
    port       = "8600"
    source_ips = ["172.16.0.0/16"]
  }

  # Envoy sidecar mesh traffic
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "20000"
    source_ips = ["172.16.0.0/16"]
  }

  # ICMP (ping)
  rule {
    direction  = "in"
    protocol   = "icmp"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  # Allow all outbound
  rule {
    direction       = "out"
    protocol        = "tcp"
    port            = "any"
    destination_ips = ["0.0.0.0/0", "::/0"]
  }

  rule {
    direction       = "out"
    protocol        = "udp"
    port            = "any"
    destination_ips = ["0.0.0.0/0", "::/0"]
  }

  rule {
    direction       = "out"
    protocol        = "icmp"
    destination_ips = ["0.0.0.0/0", "::/0"]
  }
}

# Database Firewall (most restrictive)
resource "hcloud_firewall" "database" {
  name   = "${local.resource_prefix}-db-fw"
  labels = local.common_labels

  # PostgreSQL from private network only
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "5432"
    source_ips = ["172.16.0.0/16"]
  }

  # MySQL from private network only
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "3306"
    source_ips = ["172.16.0.0/16"]
  }

  # MongoDB from private network only
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "27017"
    source_ips = ["172.16.0.0/16"]
  }

  # Redis from private network only
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "6379"
    source_ips = ["172.16.0.0/16"]
  }

  # SSH only from management subnet
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "22"
    source_ips = ["172.16.0.0/24"]
  }

  # Consul ports from private network
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "8301"
    source_ips = ["172.16.0.0/16"]
  }

  rule {
    direction  = "in"
    protocol   = "udp"
    port       = "8301"
    source_ips = ["172.16.0.0/16"]
  }

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "8502"
    source_ips = ["172.16.0.0/16"]
  }

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "8600"
    source_ips = ["172.16.0.0/16"]
  }

  rule {
    direction  = "in"
    protocol   = "udp"
    port       = "8600"
    source_ips = ["172.16.0.0/16"]
  }

  # Envoy sidecar mesh traffic
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "20000"
    source_ips = ["172.16.0.0/16"]
  }

  # ICMP (ping) from private network
  rule {
    direction  = "in"
    protocol   = "icmp"
    source_ips = ["172.16.0.0/16"]
  }

  # Allow outbound to private network
  rule {
    direction       = "out"
    protocol        = "tcp"
    port            = "any"
    destination_ips = ["172.16.0.0/16"]
  }

  rule {
    direction       = "out"
    protocol        = "udp"
    port            = "any"
    destination_ips = ["172.16.0.0/16"]
  }

  # Allow outbound HTTPS for updates
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

# Placement Groups for high availability
resource "hcloud_placement_group" "management" {
  name   = "${local.resource_prefix}-management-pg"
  type   = "spread"
  labels = local.common_labels
}

resource "hcloud_placement_group" "application" {
  name   = "${local.resource_prefix}-application-pg"
  type   = "spread"
  labels = local.common_labels
}

resource "hcloud_placement_group" "database" {
  name   = "${local.resource_prefix}-database-pg"
  type   = "spread"
  labels = local.common_labels
}

# application servers and database servers would be defined similarly

resource "hcloud_server" "application" {
  count              = var.application_server_count
  name               = "${local.resource_prefix}-app-${count.index + 1}"
  server_type        = "cx22"
  image              = "ubuntu-24.04"
  location           = var.primary_location
  ssh_keys           = [hcloud_ssh_key.landing_zone_key.id]
  firewall_ids       = [hcloud_firewall.application.id]
  placement_group_id = hcloud_placement_group.application.id
  labels             = merge(local.common_labels, { "role" = "application" })

  network {
    network_id = hcloud_network.main.id
  }

  user_data = <<-EOF
    #cloud-config
    package_update: true
    package_upgrade: true
    packages:
      - unzip
      - jq
      - nginx
    
    write_files:
      - path: /etc/consul.d/client.hcl
        owner: root:root
        permissions: '0644'
        content: |
          datacenter = "${var.environment}"
          data_dir = "/opt/consul"
          server = false
          retry_join = ["172.16.0.10"]
          
          bind_addr = "{{ GetPrivateIP }}"
          advertise_addr = "{{ GetPrivateIP }}"
          
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
            
            tags = ["${var.environment}", "web-server", "instance-${count.index + 1}"]
            
            meta = {
              version = "1.0.0"
              instance = "${count.index + 1}"
            }
            
            connect {
              sidecar_service {
                port = 20000
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
                id       = "web-http"
                name     = "HTTP health check"
                http     = "http://127.0.0.1:80/"
                interval = "10s"
                timeout  = "2s"
              }
            ]
          }
      
      - path: /var/www/html/index.html
        owner: root:root
        permissions: '0644'
        content: |
          <!DOCTYPE html>
          <html>
          <head><title>Web Server ${count.index + 1}</title></head>
          <body>
            <h1>Landing Zone Web Server ${count.index + 1}</h1>
            <p>Instance: ${local.resource_prefix}-app-${count.index + 1}</p>
            <p>Environment: ${var.environment}</p>
            <p>Consul Service Mesh: Enabled</p>
          </body>
          </html>
    
    users:
      - name: admin
        groups: sudo
        shell: /bin/bash
        sudo: ['ALL=(ALL) NOPASSWD:ALL']
        ssh_authorized_keys:
          - ${file(var.ssh_public_key_path)}
    
    runcmd:
      # Install Consul
      - |
        CONSUL_VERSION="1.17.0"
        cd /tmp
        wget -q https://releases.hashicorp.com/consul/$${CONSUL_VERSION}/consul_$${CONSUL_VERSION}_linux_amd64.zip
        unzip consul_$${CONSUL_VERSION}_linux_amd64.zip
        mv consul /usr/local/bin/
        rm consul_$${CONSUL_VERSION}_linux_amd64.zip
      
      # Install Envoy (for Connect sidecar)
      - |
        curl -sL https://func-e.io/install.sh | bash -s -- -b /usr/local/bin
        /usr/local/bin/func-e use 1.28.0
        cp /root/.func-e/versions/1.28.0/bin/envoy /usr/local/bin/
      
      # Create Consul user and directories
      - useradd --system --home /etc/consul.d --shell /bin/false consul || true
      - mkdir -p /opt/consul /etc/consul.d
      - chown -R consul:consul /opt/consul /etc/consul.d
      
      # Create Consul systemd service
      - |
        cat > /etc/systemd/system/consul.service <<CONSUL_SVC
        [Unit]
        Description=Consul Agent
        Documentation=https://www.consul.io/
        After=network-online.target
        Wants=network-online.target
        
        [Service]
        Type=notify
        User=consul
        Group=consul
        ExecStart=/usr/local/bin/consul agent -config-dir=/etc/consul.d/
        ExecReload=/bin/kill -HUP \$$MAINPID
        KillMode=process
        KillSignal=SIGTERM
        Restart=on-failure
        LimitNOFILE=65536
        
        [Install]
        WantedBy=multi-user.target
        CONSUL_SVC
      
      # Start Consul
      - systemctl daemon-reload
      - systemctl enable consul
      - systemctl start consul
      
      # Configure nginx
      - systemctl enable nginx
      - systemctl start nginx
      
      # Wait for Consul to be ready
      - sleep 15
      
      # Start sidecar proxy
      - |
        cat > /etc/systemd/system/consul-sidecar.service <<SIDECAR_SVC
        [Unit]
        Description=Consul Connect Sidecar Proxy for web
        After=consul.service
        Requires=consul.service
        
        [Service]
        Type=simple
        ExecStart=/usr/local/bin/consul connect envoy -sidecar-for web-${count.index + 1} -admin-bind 127.0.0.1:19000
        Restart=always
        RestartSec=5
        
        [Install]
        WantedBy=multi-user.target
        SIDECAR_SVC
      
      - systemctl daemon-reload
      - systemctl enable consul-sidecar
      - systemctl start consul-sidecar
      
      # Set hostname
      - hostnamectl set-hostname ${local.resource_prefix}-app-${count.index + 1}
  EOF
}

resource "hcloud_server" "database" {
  count              = var.database_server_count
  name               = "${local.resource_prefix}-db-${count.index + 1}"
  server_type        = "cx22"
  image              = "ubuntu-24.04"
  location           = var.primary_location
  ssh_keys           = [hcloud_ssh_key.landing_zone_key.id]
  firewall_ids       = [hcloud_firewall.database.id]
  placement_group_id = hcloud_placement_group.database.id
  labels             = merge(local.common_labels, { "role" = "database" })

  network {
    network_id = hcloud_network.main.id
  }

  user_data = <<-EOF
    #cloud-config
    package_update: true
    package_upgrade: true
    packages:
      - postgresql
      - unzip
      - jq
    write_files:
      - path: /etc/consul.d/client.hcl
        owner: root:root
        permissions: '0644'
        content: |
          datacenter = "${var.environment}"
          data_dir = "/opt/consul"
          server = false
          retry_join = ["172.16.0.10"]
          
          bind_addr = "{{ GetPrivateIP }}"
          advertise_addr = "{{ GetPrivateIP }}"
          
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
            
            tags = ["${var.environment}", "database", "postgresql", "instance-${count.index + 1}"]
            
            meta = {
              version = "16"
              instance = "${count.index + 1}"
            }
            
            connect {
              sidecar_service {
                port = 20000
                proxy {}
              }
            }
            
            checks = [
              {
                id       = "postgres-tcp"
                name     = "PostgreSQL TCP Check"
                tcp      = "127.0.0.1:5432"
                interval = "10s"
                timeout  = "2s"
              }
            ]
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
          # Ensure postgres listens on the private network and localhost
          if grep -q '^#listen_addresses' "$$PGCONF_DIR/postgresql.conf" 2>/dev/null; then
            sed -i "s/^#listen_addresses.*/listen_addresses = '172.16.0.0\/16,localhost'/" "$$PGCONF_DIR/postgresql.conf"
          elif grep -q '^listen_addresses' "$$PGCONF_DIR/postgresql.conf" 2>/dev/null; then
            sed -i "s/^listen_addresses.*/listen_addresses = '172.16.0.0\/16,localhost'/" "$$PGCONF_DIR/postgresql.conf"
          else
            echo "listen_addresses = '172.16.0.0/16,localhost'" >> "$$PGCONF_DIR/postgresql.conf"
          fi
          # Add PG HBA entry to allow private network access with md5 (append if not present)
          if ! grep -q '^host\s\+all\s\+all\s\+172.16.0.0/16\s\+md5' "$$PGCONF_DIR/pg_hba.conf" 2>/dev/null; then
            echo "host    all             all             172.16.0.0/16            md5" >> "$$PGCONF_DIR/pg_hba.conf"
          fi
          # Restart postgres to apply changes
          systemctl restart postgresql
          # Create credentials file and random passwords
          CREDFILE=/root/postgres-credentials.txt
          umask 077
          : > "$$CREDFILE"
          POSTGRES_PASS=$$(openssl rand -hex 16)
          APP_USER="app_user"
          APP_DB="app_db"
          APP_PASS=$$(openssl rand -hex 16)
          # Set postgres superuser password and create application user/database
          sudo -u postgres psql -v ON_ERROR_STOP=1 <<SQL
          ALTER USER postgres WITH PASSWORD '$${POSTGRES_PASS}';
          CREATE USER $${APP_USER} WITH ENCRYPTED PASSWORD '$${APP_PASS}';
          CREATE DATABASE $${APP_DB} WITH OWNER $${APP_USER};
          SQL
          # Persist credentials for operator retrieval (secure file)
          {
            echo "postgres:$${POSTGRES_PASS}"
            echo "$${APP_USER}:$${APP_PASS}"
            echo "database:$${APP_DB}"
          } >> "$$CREDFILE"
          chmod 600 "$$CREDFILE"
          echo "PostgreSQL configured. Credentials saved to $$CREDFILE"

    bootcmd:
      - [ bash, -lc, "/usr/local/bin/setup-postgres.sh" ]
    
    users:
      - name: admin
        groups: sudo
        shell: /bin/bash
        sudo: ['ALL=(ALL) NOPASSWD:ALL']
        ssh_authorized_keys:
          - ${file(var.ssh_public_key_path)}
    
    runcmd:
      # Install Consul
      - |
        CONSUL_VERSION="1.17.0"
        cd /tmp
        wget -q https://releases.hashicorp.com/consul/$${CONSUL_VERSION}/consul_$${CONSUL_VERSION}_linux_amd64.zip
        unzip consul_$${CONSUL_VERSION}_linux_amd64.zip
        mv consul /usr/local/bin/
        rm consul_$${CONSUL_VERSION}_linux_amd64.zip
      
      # Install Envoy
      - |
        curl -sL https://func-e.io/install.sh | bash -s -- -b /usr/local/bin
        /usr/local/bin/func-e use 1.28.0
        cp /root/.func-e/versions/1.28.0/bin/envoy /usr/local/bin/
      
      # Create Consul user and directories
      - useradd --system --home /etc/consul.d --shell /bin/false consul || true
      - mkdir -p /opt/consul /etc/consul.d
      - chown -R consul:consul /opt/consul /etc/consul.d
      
      # Create Consul systemd service
      - |
        cat > /etc/systemd/system/consul.service <<CONSUL_SVC
        [Unit]
        Description=Consul Agent
        Documentation=https://www.consul.io/
        After=network-online.target
        Wants=network-online.target
        
        [Service]
        Type=notify
        User=consul
        Group=consul
        ExecStart=/usr/local/bin/consul agent -config-dir=/etc/consul.d/
        ExecReload=/bin/kill -HUP \$$MAINPID
        KillMode=process
        KillSignal=SIGTERM
        Restart=on-failure
        LimitNOFILE=65536
        
        [Install]
        WantedBy=multi-user.target
        CONSUL_SVC
      
      # Start Consul
      - systemctl daemon-reload
      - systemctl enable consul
      - systemctl start consul
      
      # Wait for Consul to be ready
      - sleep 15
      
      # Start sidecar proxy
      - |
        cat > /etc/systemd/system/consul-sidecar.service <<SIDECAR_SVC
        [Unit]
        Description=Consul Connect Sidecar Proxy for postgres
        After=consul.service postgresql.service
        Requires=consul.service
        
        [Service]
        Type=simple
        ExecStart=/usr/local/bin/consul connect envoy -sidecar-for postgres-${count.index + 1} -admin-bind 127.0.0.1:19000
        Restart=always
        RestartSec=5
        
        [Install]
        WantedBy=multi-user.target
        SIDECAR_SVC
      
      - systemctl daemon-reload
      - systemctl enable consul-sidecar
      - systemctl start consul-sidecar
      
      # Set hostname
      - hostnamectl set-hostname ${local.resource_prefix}-db-${count.index + 1}
  EOF

}

# Bastion Host
resource "hcloud_server" "bastion" {
  name               = "${local.resource_prefix}-bastion"
  server_type        = "cx22"
  image              = "ubuntu-24.04"
  location           = var.primary_location
  ssh_keys           = [hcloud_ssh_key.landing_zone_key.id]
  firewall_ids       = [hcloud_firewall.bastion.id]
  placement_group_id = hcloud_placement_group.management.id
  labels             = merge(local.common_labels, { "role" = "bastion" })

  network {
    network_id = hcloud_network.main.id
    ip         = "172.16.0.10"
  }

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
      - jq
    
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
          
          acl {
            enabled = false
            default_policy = "allow"
            enable_token_persistence = true
          }
    
    users:
      - name: admin
        groups: sudo
        shell: /bin/bash
        sudo: ['ALL=(ALL) NOPASSWD:ALL']
        ssh_authorized_keys:
          - ${file(var.ssh_public_key_path)}
    
    runcmd:
      # Enable IP forwarding
      - sysctl -w net.ipv4.ip_forward=1
      - sysctl -w net.ipv6.conf.all.forwarding=1
      - sed -i '/^#net.ipv4.ip_forward=1/s/^#//' /etc/sysctl.conf
      - sed -i '/^#net.ipv6.conf.all.forwarding=1/s/^#//' /etc/sysctl.conf
      
      # Configure fail2ban
      - systemctl enable fail2ban
      - systemctl start fail2ban
      
      # Setup basic UFW rules (WireGuard + Consul)
      - ufw allow 51820/udp
      - ufw allow 22/tcp
      - ufw allow 8500/tcp
      - ufw allow 8501/tcp
      - ufw allow 8502/tcp
      - ufw allow 8600/tcp
      - ufw allow 8600/udp
      - ufw allow 8300/tcp
      - ufw allow 8301/tcp
      - ufw allow 8301/udp
      - ufw allow 8302/tcp
      - ufw allow 8302/udp
      - ufw --force enable
      
      # Generate WireGuard keys
      - |
        if [ ! -f /etc/wireguard/wg0.conf ]; then
          umask 077
          wg genkey | tee /etc/wireguard/privatekey | wg pubkey > /etc/wireguard/publickey
          PRIVKEY=`cat /etc/wireguard/privatekey`
          PUBKEY=`cat /etc/wireguard/publickey`
          cat > /etc/wireguard/wg0.conf <<WGEOF
        [Interface]
        Address = 192.168.100.1/24
        ListenPort = 51820
        PrivateKey = $$PRIVKEY
        PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
        PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE
        WGEOF
          chmod 600 /etc/wireguard/wg0.conf
          systemctl enable wg-quick@wg0
          systemctl start wg-quick@wg0
          
          # Save keys to file for easy retrieval
          echo "WireGuard Public Key: $$PUBKEY" > /root/wireguard-info.txt
          echo "Server Public IP: `curl -s ifconfig.me`" >> /root/wireguard-info.txt
        fi
      
      # Install Consul
      - |
        CONSUL_VERSION="1.17.0"
        cd /tmp
        wget -q https://releases.hashicorp.com/consul/$${CONSUL_VERSION}/consul_$${CONSUL_VERSION}_linux_amd64.zip
        unzip consul_$${CONSUL_VERSION}_linux_amd64.zip
        mv consul /usr/local/bin/
        rm consul_$${CONSUL_VERSION}_linux_amd64.zip
        consul version
      
      # Create Consul user and directories
      - useradd --system --home /etc/consul.d --shell /bin/false consul || true
      - mkdir -p /opt/consul /etc/consul.d
      - chown -R consul:consul /opt/consul /etc/consul.d
      
      # Create Consul systemd service
      - |
        cat > /etc/systemd/system/consul.service <<CONSUL_SVC
        [Unit]
        Description=Consul Service Discovery and Configuration
        Documentation=https://www.consul.io/
        After=network-online.target
        Wants=network-online.target
        
        [Service]
        Type=notify
        User=consul
        Group=consul
        ExecStart=/usr/local/bin/consul agent -config-dir=/etc/consul.d/
        ExecReload=/bin/kill -HUP \$$MAINPID
        KillMode=process
        KillSignal=SIGTERM
        Restart=on-failure
        LimitNOFILE=65536
        
        [Install]
        WantedBy=multi-user.target
        CONSUL_SVC
      
      # Start Consul
      - systemctl daemon-reload
      - systemctl enable consul
      - systemctl start consul
      
      # Wait for Consul to be ready
      - sleep 10
      
      # Create helper script for intentions
      - |
        cat > /usr/local/bin/setup-consul-intentions.sh <<'INTENTIONS'
        #!/bin/bash
        # Wait for Consul to be fully ready
        until consul members > /dev/null 2>&1; do
          echo "Waiting for Consul..."
          sleep 5
        done
        
        echo "Setting up Consul service mesh intentions..."
        
        # Default deny (uncomment when ready for zero-trust)
        # consul intention create -deny '*' '*'
        
        # Allow web to api
        consul intention create -allow -replace web api || true
        
        # Allow api to postgres
        consul intention create -allow -replace api postgres || true
        
        # Allow bastion monitoring
        consul intention create -allow -replace bastion '*' || true
        
        echo "Consul intentions configured"
        consul intention list
        INTENTIONS
        chmod +x /usr/local/bin/setup-consul-intentions.sh
      
      # Set hostname
      - hostnamectl set-hostname ${local.resource_prefix}-bastion
      
      # Save Consul info
      - |
        sleep 5
        echo "Consul UI: http://$$(curl -s ifconfig.me):8500" >> /root/consul-info.txt
        echo "Consul Datacenter: ${var.environment}" >> /root/consul-info.txt
        echo "" >> /root/consul-info.txt
        echo "Run '/usr/local/bin/setup-consul-intentions.sh' to configure service mesh policies" >> /root/consul-info.txt
  EOF
}

# Outputs
output "network_id" {
  description = "ID of the main network"
  value       = hcloud_network.main.id
}

output "network_name" {
  description = "Name of the main network"
  value       = hcloud_network.main.name
}

output "network_ip_range" {
  description = "IP range of the main network"
  value       = hcloud_network.main.ip_range
}

output "subnet_management_ip_range" {
  description = "Management subnet IP range"
  value       = hcloud_network_subnet.management.ip_range
}

output "subnet_application_ip_range" {
  description = "Application subnet IP range"
  value       = hcloud_network_subnet.application.ip_range
}

output "subnet_services_ip_range" {
  description = "Services subnet IP range"
  value       = hcloud_network_subnet.services.ip_range
}

output "subnet_dmz_ip_range" {
  description = "DMZ subnet IP range"
  value       = hcloud_network_subnet.dmz.ip_range
}

output "bastion_public_ip" {
  description = "Public IP address of the bastion host"
  value       = hcloud_server.bastion.ipv4_address
}

output "bastion_private_ip" {
  description = "Private IP address of the bastion host"
  value       = [for net in hcloud_server.bastion.network : net.ip][0]
}

output "bastion_server_id" {
  description = "ID of the bastion server"
  value       = hcloud_server.bastion.id
}

output "ssh_key_id" {
  description = "ID of the SSH key"
  value       = hcloud_ssh_key.landing_zone_key.id
}

output "firewall_ids" {
  description = "Map of firewall names to IDs"
  value = {
    bastion     = hcloud_firewall.bastion.id
    application = hcloud_firewall.application.id
    database    = hcloud_firewall.database.id
  }
}

output "placement_group_ids" {
  description = "Map of placement group names to IDs"
  value = {
    management  = hcloud_placement_group.management.id
    application = hcloud_placement_group.application.id
    database    = hcloud_placement_group.database.id
  }
}

output "bastion_ssh_command" {
  description = "SSH command to connect to bastion"
  value       = "ssh -i ${var.ssh_public_key_path} admin@${hcloud_server.bastion.ipv4_address}"
}

output "wireguard_info_command" {
  description = "Command to retrieve WireGuard configuration from bastion"
  value       = "ssh -i ${var.ssh_public_key_path} admin@${hcloud_server.bastion.ipv4_address} 'cat /root/wireguard-info.txt && cat /etc/wireguard/wg0.conf'"
}

output "resource_prefix" {
  description = "Prefix used for all resources"
  value       = local.resource_prefix
}

# Consul Outputs
output "consul_ui_url" {
  description = "URL to access Consul UI"
  value       = "http://${hcloud_server.bastion.ipv4_address}:8500/ui"
}

output "consul_datacenter" {
  description = "Consul datacenter name"
  value       = var.environment
}

output "consul_server_ip" {
  description = "Consul server IP (bastion)"
  value       = "172.16.0.10"
}

output "consul_management_commands" {
  description = "Common Consul management commands"
  value       = <<-EOT
    # Check cluster status
    ssh -i ${var.ssh_public_key_path} admin@${hcloud_server.bastion.ipv4_address} 'consul members'
    
    # List services
    ssh -i ${var.ssh_public_key_path} admin@${hcloud_server.bastion.ipv4_address} 'consul catalog services'
    
    # View intentions
    ssh -i ${var.ssh_public_key_path} admin@${hcloud_server.bastion.ipv4_address} 'consul intention list'
    
    # Setup service mesh policies
    ssh -i ${var.ssh_public_key_path} admin@${hcloud_server.bastion.ipv4_address} '/usr/local/bin/setup-consul-intentions.sh'
    
    # Use management script
    ./consul-manage.sh ${hcloud_server.bastion.ipv4_address}
    
    # Access Consul UI
    Open: http://${hcloud_server.bastion.ipv4_address}:8500/ui
  EOT
}

output "application_server_ips" {
  description = "Private IPs of application servers"
  value       = [for s in hcloud_server.application : [for net in s.network : net.ip][0]]
}

output "database_server_ips" {
  description = "Private IPs of database servers"
  value       = [for s in hcloud_server.database : [for net in s.network : net.ip][0]]
}

output "service_mesh_summary" {
  description = "Consul Service Mesh deployment summary"
  value       = <<-EOT
    ╔════════════════════════════════════════════════════════════╗
    ║           Consul Service Mesh Enabled                      ║
    ╚════════════════════════════════════════════════════════════╝
    
    📊 Consul Server:    ${hcloud_server.bastion.ipv4_address}:8500
    🌐 Datacenter:       ${var.environment}
    🔒 Service Mesh:     Enabled (mTLS ready)
    
    📋 Registered Services:
       • web       (${var.application_server_count} instance${var.application_server_count > 1 ? "s" : ""})
       • postgres  (${var.database_server_count} instance${var.database_server_count > 1 ? "s" : ""})
    
    🎯 Next Steps:
       1. Configure service intentions (access policies):
          ssh admin@${hcloud_server.bastion.ipv4_address} '/usr/local/bin/setup-consul-intentions.sh'
       
       2. Access Consul UI:
          http://${hcloud_server.bastion.ipv4_address}:8500/ui
       
       3. Check service health:
          ./consul-manage.sh ${hcloud_server.bastion.ipv4_address}
       
       4. Enable zero-trust networking:
          ssh admin@${hcloud_server.bastion.ipv4_address} "consul intention create -deny '*' '*'"
          ssh admin@${hcloud_server.bastion.ipv4_address} "consul intention create -allow web postgres"
    
    📚 Documentation:
       • MICRO-SEGMENTATION-GUIDE.md (Option 3)
       • SERVICE-MESH-VMS.md
  EOT
}
