# Makefile Commands Reference

Complete guide to all available `make` commands for the Hetzner Landing Zone project.

## Quick Reference

Run `make help` to see all available commands with descriptions.

## Command Categories

### 🚀 Setup & Initialization

#### `make quick-start`
Complete setup for new deployments. Automatically:
- Generates SSH key pair if not exists
- Creates `terraform.tfvars` from example
- Initializes Terraform

```bash
make quick-start
```

**After running:**
1. Edit `terraform.tfvars` with your Hetzner API token
2. Run `make plan` to preview
3. Run `make apply` to deploy

#### `make generate-ssh-key`
Generate SSH key pair for server access.

```bash
make generate-ssh-key
```

Creates: `id_ed25519_hetzner_cloud_k3s` and `id_ed25519_hetzner_cloud_k3s.pub`

#### `make setup-vars`
Create `terraform.tfvars` from example template.

```bash
make setup-vars
```

#### `make init`
Initialize Terraform and download providers.

```bash
make init
```

---

## 📦 Terraform Operations

#### `make validate`
Validate Terraform configuration syntax.

```bash
make validate
```

#### `make fmt`
Format all Terraform files to canonical style.

```bash
make fmt
```

#### `make check`
Run both validation and formatting.

```bash
make check
```

#### `make plan`
Show Terraform execution plan without applying changes.

```bash
make plan
```

**Use this before apply to review changes!**

#### `make apply`
Deploy infrastructure (will prompt for confirmation).

```bash
make apply
```

#### `make auto-apply`
Deploy without confirmation prompt (use with caution).

```bash
make auto-apply
```

⚠️ **Dangerous**: Skips confirmation. Use only in automation.

#### `make destroy`
Destroy all infrastructure (will prompt for confirmation).

```bash
make destroy
```

#### `make auto-destroy`
Destroy without confirmation (use with extreme caution).

```bash
make auto-destroy
```

⚠️ **Very Dangerous**: Immediately destroys everything.

#### `make output`
Show all Terraform outputs.

```bash
make output
```

---

## 📊 Information & Monitoring

#### `make info`
Show comprehensive deployment information.

```bash
make info
```

Displays:
- Network details
- Bastion host IPs
- Subnet ranges
- Consul UI URL
- Server IPs

#### `make list-ips`
List all server IP addresses.

```bash
make list-ips
```

Shows public and private IPs for all servers.

#### `make mesh-summary`
Display Consul service mesh deployment summary.

```bash
make mesh-summary
```

Shows:
- Registered services
- Service instances
- Next steps
- Documentation links

#### `make cost`
Estimate monthly infrastructure costs.

```bash
make cost
```

Shows approximate Hetzner Cloud costs per component.

#### `make state-list`
List all resources in Terraform state.

```bash
make state-list
```

#### `make state-backup`
Backup current Terraform state file.

```bash
make state-backup
```

Creates timestamped backup: `terraform.tfstate.backup.YYYYMMDD_HHMMSS`

---

## 🔐 SSH & Access

#### `make ssh-bastion`
SSH to bastion host using Terraform output.

```bash
make ssh-bastion
```

Automatically uses correct SSH key and IP address.

#### `make test-ssh`
Test SSH connection to bastion.

```bash
make test-ssh
```

Verifies connectivity without opening interactive session.

#### `make wireguard-info`
Retrieve WireGuard VPN configuration from bastion.

```bash
make wireguard-info
```

Shows:
- WireGuard public key
- Server public IP
- Configuration file contents

---

## 🕸️ Consul Service Mesh

#### `make consul-status`
Check Consul cluster member status.

```bash
make consul-status
```

Shows:
- All cluster nodes
- Node status (alive/failed)
- Roles (server/client)

#### `make consul-services`
List all registered Consul services.

```bash
make consul-services
```

Shows services like:
- `consul`
- `web`
- `postgres`
- `*-sidecar-proxy`

#### `make consul-intentions`
View service mesh access policies (intentions).

```bash
make consul-intentions
```

Shows which services can communicate with each other.

#### `make consul-setup`
Configure Consul service mesh policies.

```bash
make consul-setup
```

Runs the setup script to establish service intentions.

#### `make consul-ui`
Get Consul UI URL.

```bash
make consul-ui
```

#### `make open-consul-ui`
Open Consul UI in default browser.

```bash
make open-consul-ui
```

Automatically opens `http://<bastion-ip>:8500/ui`

#### `make consul-manage`
Run Consul management script.

```bash
make consul-manage
```

Interactive menu for Consul operations.

#### `make health-check`
Comprehensive health check of all services.

```bash
make health-check
```

Checks:
- Consul cluster status
- Registered services
- Node details

---

## 📝 Logs & Debugging

#### `make logs-bastion`
View Consul logs from bastion host.

```bash
make logs-bastion
```

Shows last 50 log entries from Consul service.

#### `make logs-app`
View Consul logs from application server.

```bash
make logs-app
```

Connects through bastion as jump host.

#### `make logs-db`
View Consul logs from database server.

```bash
make logs-db
```

Connects through bastion as jump host.

#### `make debug`
Show comprehensive debug information.

```bash
make debug
```

Displays:
- Terraform version
- SSH key status
- Configuration files
- State file status

---

## 📚 Documentation

#### `make docs`
List all available documentation files.

```bash
make docs
```

Shows all `.md` files with quick links to important docs.

#### `make help`
Show all make commands with descriptions.

```bash
make help
```

**This should be your first command!**

---

## 🧹 Maintenance

#### `make clean`
Clean Terraform cache and backup files.

```bash
make clean
```

Removes:
- `.terraform/` directory
- `.terraform.lock.hcl`
- `*.tfstate.backup` files

⚠️ **Warning**: Does not remove main state file. Use `make state-backup` first!

---

## Example Workflows

### First Time Setup

```bash
# 1. Quick setup
make quick-start

# 2. Edit configuration
vim terraform.tfvars  # Add your Hetzner token

# 3. Preview deployment
make plan

# 4. Deploy
make apply

# 5. Verify
make info
make consul-status
```

### Daily Operations

```bash
# Check infrastructure
make info
make health-check

# View logs
make logs-bastion
make logs-app

# Access Consul UI
make open-consul-ui

# SSH to bastion
make ssh-bastion
```

### Making Changes

```bash
# 1. Backup state
make state-backup

# 2. Edit Terraform files
vim main.tf

# 3. Validate changes
make validate
make fmt

# 4. Preview
make plan

# 5. Apply
make apply

# 6. Verify
make info
make health-check
```

### Troubleshooting

```bash
# Debug information
make debug

# Test connectivity
make test-ssh

# Check logs
make logs-bastion
make logs-app
make logs-db

# Check Consul
make consul-status
make consul-services
make health-check
```

### Cleanup

```bash
# 1. Backup state
make state-backup

# 2. Destroy infrastructure
make destroy

# 3. Clean local files (optional)
make clean
```

---

## Tips & Best Practices

### 1. Always Use `make plan` First
```bash
make plan  # Review changes
make apply # Apply only if plan looks good
```

### 2. Regular Backups
```bash
# Before major changes
make state-backup
```

### 3. Health Monitoring
```bash
# Regular health checks
make health-check
make consul-status
```

### 4. Log Review
```bash
# Check logs regularly
make logs-bastion
make logs-app
make logs-db
```

### 5. Documentation
```bash
# See all docs
make docs

# Always check the README
cat README.md
```

---

## Command Dependencies

Some commands require infrastructure to be deployed:

| Command | Requires Deployment | Notes |
|---------|-------------------|-------|
| `make init` | ❌ No | Can run anytime |
| `make plan` | ❌ No | Shows what will be created |
| `make apply` | ❌ No | Creates infrastructure |
| `make ssh-bastion` | ✅ Yes | Needs bastion IP |
| `make consul-status` | ✅ Yes | Needs running Consul |
| `make logs-*` | ✅ Yes | Needs servers running |
| `make health-check` | ✅ Yes | Needs Consul running |
| `make destroy` | ✅ Yes | Needs existing resources |

---

## Environment Variables

Some commands use these variables:

- `BASTION_IP`: Automatically extracted from Terraform output
- `APP_IP`: First application server IP
- `DB_IP`: First database server IP
- `CONSUL_URL`: Consul UI URL

You don't need to set these manually; commands handle them automatically.

---

## Color Coding

Make commands use colors for clarity:

- 🔵 **Blue**: Informational messages
- 🟢 **Green**: Success messages
- 🟡 **Yellow**: Warnings
- 🔴 **Red**: Errors

---

## Getting Help

```bash
# Show all commands
make help

# Read documentation
make docs

# Debug issues
make debug

# Check status
make info
```

---

**Last Updated**: November 8, 2025  
**Version**: 2.0 (Refactored)  
**Terraform Version**: >= 1.5.0
