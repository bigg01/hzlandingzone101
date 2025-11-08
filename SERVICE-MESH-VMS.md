# Service Mesh for VMs: Cilium & Istio

## Quick Answer

**Yes, both can work with VMs, but with different approaches:**

| Feature | Cilium | Istio |
|---------|--------|-------|
| **VM Support** | ✅ Yes (Native or via K8s) | ✅ Yes (VM integration) |
| **Agent Required** | Yes (cilium-agent) | Yes (envoy proxy) |
| **Complexity** | Medium | High |
| **Best Use Case** | Network policies, eBPF | Full service mesh features |
| **eBPF Benefits** | ✅ Yes | ❌ No |
| **Without K8s** | Possible but limited | Not recommended |

## Architecture Comparison

### Traditional Networking (What you have now)
```
┌─────────────┐         ┌─────────────┐
│   VM Web    │────────▶│   VM API    │
│  172.16.1.10│         │ 172.16.1.20 │
└─────────────┘         └─────────────┘
     │                       │
     │  iptables/UFW         │  iptables/UFW
     │  rules                │  rules
     └───────────────────────┘
```

### With Cilium (eBPF-based)
```
┌─────────────────────────────┐
│        VM Web               │
│    ┌──────────────┐         │
│    │ Application  │         │
│    └──────┬───────┘         │
│           │                 │
│    ┌──────▼───────┐         │
│    │ Cilium Agent │ eBPF    │
│    │   + eBPF     │         │
│    └──────┬───────┘         │
│           │                 │
└───────────┼─────────────────┘
            │
            │ Identity-based
            │ mTLS optional
            │
┌───────────▼─────────────────┐
│        VM API               │
│    ┌──────────────┐         │
│    │ Cilium Agent │         │
│    └──────┬───────┘         │
│           │                 │
│    ┌──────▼───────┐         │
│    │ Application  │         │
│    └──────────────┘         │
└─────────────────────────────┘
```

### With Istio (Sidecar proxy)
```
┌─────────────────────────────┐
│        VM Web               │
│    ┌──────────────┐         │
│    │ Application  │         │
│    │ :8080        │         │
│    └──────┬───────┘         │
│           │ localhost       │
│    ┌──────▼───────┐         │
│    │ Envoy Proxy  │ mTLS    │
│    │ (Sidecar)    │         │
│    └──────┬───────┘         │
└───────────┼─────────────────┘
            │
            │ Encrypted mTLS
            │ Policy enforcement
            │
┌───────────▼─────────────────┐
│        VM API               │
│    ┌──────────────┐         │
│    │ Envoy Proxy  │         │
│    │ (Sidecar)    │         │
│    └──────┬───────┘         │
│           │ localhost       │
│    ┌──────▼───────┐         │
│    │ Application  │         │
│    │ :8080        │         │
│    └──────────────┘         │
└─────────────────────────────┘
```

---

## Option 1: Cilium for VMs

### 1A. Cilium Standalone (No Kubernetes)

**Pros:**
- eBPF-based (kernel-level, extremely fast)
- Identity-based security
- API-aware filtering (HTTP, gRPC, Kafka)
- Deep visibility

**Cons:**
- Less mature VM support without K8s
- Complex initial setup
- Requires modern kernel (5.10+)

#### Installation on Ubuntu VMs

**On each VM:**

```bash
# Install Cilium agent
curl -LO https://github.com/cilium/cilium/releases/latest/download/cilium-linux-amd64.tar.gz
tar xzvf cilium-linux-amd64.tar.gz
sudo mv cilium /usr/local/bin/

# Install Cilium agent daemon
cat > /etc/systemd/system/cilium.service <<EOF
[Unit]
Description=Cilium Agent
After=network.target

[Service]
Type=notify
ExecStart=/usr/local/bin/cilium-agent \
  --enable-ipv4=true \
  --enable-ipv6=false \
  --tunnel=vxlan \
  --datapath-mode=veth \
  --kvstore=consul \
  --kvstore-opt=consul.address=172.16.0.10:8500
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable cilium
systemctl start cilium
```

**Network Policy Example:**

```yaml
# allow-web-to-api.yaml
apiVersion: "cilium.io/v2"
kind: CiliumNetworkPolicy
metadata:
  name: "allow-web-to-api"
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

**Problem:** Without Kubernetes, policy management is manual and complex.

### 1B. Cilium with Kubernetes (Recommended)

**Better approach:** Run a lightweight K3s cluster, but deploy VMs as Cilium endpoints.

#### Setup K3s Cluster

```bash
# On bastion (control plane)
curl -sfL https://get.k3s.io | sh -s - \
  --flannel-backend=none \
  --disable-network-policy \
  --disable=traefik

# Install Cilium via Helm
helm repo add cilium https://helm.cilium.io/
helm install cilium cilium/cilium \
  --namespace kube-system \
  --set operator.replicas=1
```

#### Register VMs as Cilium Endpoints

**On each VM:**

```bash
# Install Cilium CLI
CILIUM_CLI_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt)
curl -L --remote-name-all https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-linux-amd64.tar.gz
sudo tar xzvfC cilium-linux-amd64.tar.gz /usr/local/bin
rm cilium-linux-amd64.tar.gz

# Join VM to Cilium mesh
# Get join token from K8s cluster
kubectl -n kube-system get secret cilium-external-workloads -o yaml

# On VM, configure Cilium agent
cat > /etc/cilium/config.yaml <<EOF
cluster-name: production
cluster-id: 1
kvstore: etcd
kvstore-opt:
  etcd.config: /var/lib/cilium/etcd-config.yaml
enable-external-workloads: true
EOF

# Start Cilium agent
systemctl start cilium
```

#### Network Policy with VM Endpoints

```yaml
apiVersion: "cilium.io/v2"
kind: CiliumNetworkPolicy
metadata:
  name: "vm-web-to-vm-api"
spec:
  endpointSelector:
    matchLabels:
      host: vm-web-1
      role: web
  egress:
  # Allow to API VMs
  - toEndpoints:
    - matchLabels:
        role: api
    toPorts:
    - ports:
      - port: "8080"
        protocol: TCP
      rules:
        http:
        - method: "GET|POST"
          path: "/api/.*"
  
  # Allow to database VMs
  - toEndpoints:
    - matchLabels:
        role: database
    toPorts:
    - ports:
      - port: "5432"
        protocol: TCP
```

#### Terraform Integration for Cilium

```terraform
# Add to main.tf
resource "hcloud_server" "application" {
  # ... existing config ...
  
  user_data = <<-EOF
    #cloud-config
    runcmd:
      # Install Cilium agent
      - curl -L https://github.com/cilium/cilium/releases/latest/download/cilium-linux-amd64.tar.gz | tar xz -C /usr/local/bin
      
      # Configure Cilium
      - mkdir -p /etc/cilium
      - |
        cat > /etc/cilium/config.yaml <<CILIUM_EOF
        cluster-name: ${var.environment}
        cluster-id: 1
        kvstore: etcd
        kvstore-opt:
          etcd.config: /var/lib/cilium/etcd-config.yaml
        enable-external-workloads: true
        labels:
          - host=${local.resource_prefix}-app-${count.index + 1}
          - role=application
          - environment=${var.environment}
        CILIUM_EOF
      
      # Start Cilium
      - systemctl enable cilium
      - systemctl start cilium
  EOF
}
```

---

## Option 2: Istio for VMs

### 2A. Istio with VM Integration (Requires K8s)

**Architecture:**
1. Run Istio control plane in Kubernetes
2. VMs join the mesh as "workload entries"
3. Envoy proxy runs on each VM

**Pros:**
- Full service mesh features (traffic management, retries, circuit breaking)
- mTLS between all services
- Rich observability (Kiali, Jaeger, Grafana)
- Mature VM support

**Cons:**
- Requires Kubernetes cluster
- Resource overhead (Envoy on each VM)
- Complex setup
- Higher learning curve

#### Setup Istio Control Plane

```bash
# Install Istio on K3s cluster
curl -L https://istio.io/downloadIstio | sh -
cd istio-*
export PATH=$PWD/bin:$PATH

# Install with VM support
istioctl install --set profile=default \
  --set values.pilot.env.PILOT_ENABLE_WORKLOAD_ENTRY_AUTOREGISTRATION=true \
  --set values.pilot.env.PILOT_ENABLE_WORKLOAD_ENTRY_HEALTHCHECKS=true
```

#### Prepare VM Integration

```bash
# Create namespace for VMs
kubectl create namespace vm-services

# Label namespace for Istio injection
kubectl label namespace vm-services istio-injection=enabled

# Create WorkloadGroup for VMs
cat <<EOF | kubectl apply -f -
apiVersion: networking.istio.io/v1beta1
kind: WorkloadGroup
metadata:
  name: app-servers
  namespace: vm-services
spec:
  metadata:
    labels:
      app: myapp
      version: v1
  template:
    serviceAccount: app-service-account
    network: vm-network
EOF

# Create ServiceAccount
kubectl create serviceaccount app-service-account -n vm-services
```

#### Configure VM to Join Istio Mesh

**Generate VM configuration files:**

```bash
# Create working directory
mkdir -p vm-files

# Generate files for VM
istioctl x workload entry configure \
  -f workloadgroup.yaml \
  -o vm-files \
  --clusterID Kubernetes \
  --autoregister
```

**On each VM:**

```bash
# Copy generated files to VM
scp -r vm-files/* admin@172.16.1.10:/tmp/

# SSH to VM
ssh admin@172.16.1.10

# Install Istio sidecar (on VM)
sudo mkdir -p /etc/certs
sudo cp /tmp/root-cert.pem /etc/certs/root-cert.pem
sudo mkdir -p /var/run/secrets/tokens
sudo cp /tmp/istio-token /var/run/secrets/tokens/istio-token

# Install and configure Envoy
curl -LO https://storage.googleapis.com/istio-release/releases/1.20.0/deb/istio-sidecar.deb
sudo dpkg -i istio-sidecar.deb

# Copy Envoy configuration
sudo cp /tmp/cluster.env /var/lib/istio/envoy/cluster.env
sudo cp /tmp/mesh.yaml /etc/istio/config/mesh

# Start Istio services
sudo systemctl start istio
```

#### Define Service for VMs

```yaml
# vm-app-service.yaml
apiVersion: v1
kind: Service
metadata:
  name: app-service
  namespace: vm-services
spec:
  ports:
  - port: 8080
    name: http
    targetPort: 8080
  selector:
    app: myapp
---
apiVersion: networking.istio.io/v1beta1
kind: WorkloadEntry
metadata:
  name: app-vm-1
  namespace: vm-services
spec:
  address: 172.16.1.10
  labels:
    app: myapp
    version: v1
  serviceAccount: app-service-account
```

#### Network Policy with Istio

```yaml
# authorization-policy.yaml
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  name: allow-web-to-api
  namespace: vm-services
spec:
  selector:
    matchLabels:
      app: api
  action: ALLOW
  rules:
  - from:
    - source:
        principals: ["cluster.local/ns/vm-services/sa/web-service-account"]
    to:
    - operation:
        methods: ["GET", "POST"]
        paths: ["/api/*"]
---
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: default
  namespace: vm-services
spec:
  mtls:
    mode: STRICT  # Require mTLS between all services
```

#### Traffic Management

```yaml
# virtual-service.yaml
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: api-service
  namespace: vm-services
spec:
  hosts:
  - api-service
  http:
  - match:
    - uri:
        prefix: /api/v1
    route:
    - destination:
        host: api-service
        subset: v1
      weight: 90
    - destination:
        host: api-service
        subset: v2
      weight: 10  # Canary 10% to v2
    timeout: 3s
    retries:
      attempts: 3
      perTryTimeout: 1s
```

---

## Option 3: Consul Service Mesh (Best for VMs!)

**Actually, Consul is better suited for VMs than Cilium/Istio:**

### Why Consul is Better for Pure VM Environments

| Feature | Consul | Cilium | Istio |
|---------|--------|--------|-------|
| **VM-first design** | ✅ Yes | ❌ No | ❌ No |
| **No K8s required** | ✅ Yes | ⚠️ Limited | ❌ No |
| **Service discovery** | ✅ Built-in | ⚠️ Via K8s | ⚠️ Via K8s |
| **Learning curve** | Medium | Medium-High | High |
| **mTLS** | ✅ Yes | ✅ Yes | ✅ Yes |

### Consul Setup for Your VMs

#### Install Consul Server (on Bastion)

```bash
# Install Consul
curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo apt-key add -
sudo apt-add-repository "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main"
sudo apt-get update && sudo apt-get install consul

# Configure Consul server
sudo mkdir -p /etc/consul.d
cat > /etc/consul.d/server.hcl <<EOF
datacenter = "hetzner-nbg1"
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
EOF

# Start Consul
sudo systemctl enable consul
sudo systemctl start consul
```

#### Install Consul Client (on Application VMs)

```bash
# On each VM
sudo apt-get install consul

# Configure client
cat > /etc/consul.d/client.hcl <<EOF
datacenter = "hetzner-nbg1"
data_dir = "/opt/consul"
server = false
bind_addr = "172.16.1.10"  # This VM's IP
retry_join = ["172.16.0.10"]  # Bastion IP

connect {
  enabled = true
}
EOF

# Start Consul
sudo systemctl enable consul
sudo systemctl start consul
```

#### Register Services

```bash
# On web server VM
cat > /etc/consul.d/web-service.json <<EOF
{
  "service": {
    "name": "web",
    "port": 80,
    "connect": {
      "sidecar_service": {
        "proxy": {
          "upstreams": [
            {
              "destination_name": "api",
              "local_bind_port": 8080
            }
          ]
        }
      }
    }
  }
}
EOF

consul reload
consul connect proxy -sidecar-for web &
```

#### Service Intentions (Access Control)

```bash
# Allow web to call API
consul intention create web api

# Deny all other connections
consul intention create -deny '*' '*'
```

---

## Comparison: Which to Choose?

### For Your Hetzner VM Setup

| Scenario | Recommendation |
|----------|----------------|
| **Pure VMs, no containers** | **Consul** |
| **Planning to use K8s later** | **Cilium** (best performance) |
| **Need advanced traffic management** | **Istio** (most features) |
| **Simple network policies** | **UFW + iptables** (what you have) |
| **Medium complexity, VM-first** | **Consul** (sweet spot) |

### Decision Matrix

```
Simple                        Complex
│                              │
UFW/iptables ─── Consul ─── Cilium ─── Istio
│                              │
No agent        Light agent    Full mesh
Fast            Medium         Feature-rich
```

### Realistic Recommendation for Your Setup

**Short term (Now):**
```
✅ Use UFW + Hetzner Firewalls (you have this)
✅ Add Ansible for automation
✅ Implement micro-segmentation manually
```

**Medium term (3-6 months):**
```
✅ Add Consul for service discovery
✅ Enable Consul Connect for mTLS
✅ Use Consul intentions for policies
```

**Long term (6+ months):**
```
If moving to containers:
  ✅ Deploy K3s
  ✅ Install Cilium for networking
  ✅ Keep VMs in Cilium mesh as external workloads

If staying on VMs:
  ✅ Continue with Consul
  ✅ Consider Nomad for orchestration
```

---

## Practical Example: Consul for Your VMs

### Terraform Integration

```terraform
# Add to main.tf
resource "hcloud_server" "application" {
  # ... existing config ...
  
  user_data = templatefile("${path.module}/cloud-init/consul-client.yaml", {
    consul_server = "172.16.0.10"
    service_name  = "application"
    service_port  = 8080
    datacenter    = var.environment
  })
}
```

### cloud-init/consul-client.yaml

```yaml
#cloud-config
packages:
  - consul

write_files:
  - path: /etc/consul.d/client.hcl
    content: |
      datacenter = "${datacenter}"
      data_dir = "/opt/consul"
      server = false
      bind_addr = "{{ GetPrivateIP }}"
      retry_join = ["${consul_server}"]
      connect {
        enabled = true
      }
  
  - path: /etc/consul.d/${service_name}.json
    content: |
      {
        "service": {
          "name": "${service_name}",
          "port": ${service_port},
          "connect": {
            "sidecar_service": {}
          }
        }
      }

runcmd:
  - systemctl enable consul
  - systemctl start consul
```

---

## Summary

**Can Cilium/Istio work with VMs?** 
- **Yes**, but they require Kubernetes for full functionality.

**Should you use them for pure VMs?**
- **Probably not** - they're designed for containers.

**Better alternatives for VMs:**
1. **Consul** - VM-native, excellent service mesh
2. **UFW + Hetzner Firewalls** - Simple, works today
3. **Cilium/Istio** - Only if you're running K8s

**My recommendation for your setup:**
```
Phase 1: UFW + Hetzner Firewalls (now) ✅
Phase 2: Add Consul (when ready for service mesh)
Phase 3: Cilium (if/when you adopt Kubernetes)
```

---

Last Updated: November 8, 2025
