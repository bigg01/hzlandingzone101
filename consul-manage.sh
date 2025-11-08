#!/bin/bash
# Consul Service Mesh Management Script

set -euo pipefail

BASTION_IP="${1:-}"
SSH_KEY="${2:-./id_ed25519_hetzner_cloud_k3s}"

if [ -z "$BASTION_IP" ]; then
    echo "Usage: $0 <bastion-ip> [ssh-key-path]"
    echo ""
    echo "Example: $0 91.98.27.105"
    exit 1
fi

echo "================================================"
echo "Consul Service Mesh Management"
echo "================================================"
echo ""

# Function to run command on bastion
run_on_bastion() {
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no admin@"$BASTION_IP" "$@"
}

# Check Consul cluster status
echo "1. Checking Consul Cluster Status..."
run_on_bastion "consul members" || echo "Failed to get Consul members"
echo ""

# List all services
echo "2. Registered Services..."
run_on_bastion "consul catalog services" || echo "Failed to list services"
echo ""

# Check service health
echo "3. Service Health Status..."
run_on_bastion "consul catalog nodes -service=web" | head -10 || echo "No web services found"
run_on_bastion "consul catalog nodes -service=postgres" | head -10 || echo "No postgres services found"
echo ""

# List intentions
echo "4. Current Service Intentions (Access Policies)..."
run_on_bastion "consul intention list" || echo "No intentions configured"
echo ""

echo "================================================"
echo "Management Commands"
echo "================================================"
echo ""
echo "Configure service mesh policies:"
echo "  ssh admin@$BASTION_IP 'sudo bash /usr/local/bin/setup-consul-intentions.sh'"
echo ""
echo "View Consul UI:"
echo "  http://$BASTION_IP:8500/ui"
echo ""
echo "Check service connectivity:"
echo "  ssh admin@$BASTION_IP 'consul intention check web postgres'"
echo ""
echo "Add new intention (allow web → api):"
echo "  ssh admin@$BASTION_IP 'consul intention create -allow web api'"
echo ""
echo "Enable zero-trust (deny all by default):"
echo "  ssh admin@$BASTION_IP 'consul intention create -deny \"*\" \"*\"'"
echo ""
echo "View service configuration:"
echo "  ssh admin@$BASTION_IP 'consul catalog nodes -service=web -detailed'"
echo ""
echo "Check Envoy proxy stats on app server:"
echo "  ssh -J admin@$BASTION_IP admin@<app-server-ip> 'curl -s localhost:19000/stats | grep upstream'"
echo ""
