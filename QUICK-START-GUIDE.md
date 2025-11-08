# 🚀 Quick Start Guide - Makefile Commands

Visual guide to get started with the Hetzner Landing Zone using Make commands.

## 🎯 Your First 5 Minutes

```bash
# 1. See all available commands
make help

# 2. Quick setup (generates SSH keys, creates config)
make quick-start

# 3. Add your Hetzner API token
vim terraform.tfvars

# 4. Preview what will be created
make plan

# 5. Deploy!
make apply
```

## 📊 Visual Command Map

```
┌─────────────────────────────────────────────────────────────┐
│                    MAKEFILE COMMANDS                         │
└─────────────────────────────────────────────────────────────┘

┌─────────────────┐   ┌─────────────────┐   ┌─────────────────┐
│   🔧 SETUP      │   │  ⚙️  TERRAFORM  │   │  📊 INFO        │
├─────────────────┤   ├─────────────────┤   ├─────────────────┤
│ quick-start     │   │ plan            │   │ info            │
│ init            │   │ apply           │   │ output          │
│ generate-ssh-key│   │ destroy         │   │ list-ips        │
│ setup-vars      │   │ validate        │   │ mesh-summary    │
│                 │   │ fmt             │   │ cost            │
└─────────────────┘   └─────────────────┘   └─────────────────┘

┌─────────────────┐   ┌─────────────────┐   ┌─────────────────┐
│  🔐 SSH/ACCESS  │   │  🕸️  CONSUL     │   │  📝 MONITORING  │
├─────────────────┤   ├─────────────────┤   ├─────────────────┤
│ ssh-bastion     │   │ consul-status   │   │ health-check    │
│ test-ssh        │   │ consul-services │   │ logs-bastion    │
│ wireguard-info  │   │ consul-setup    │   │ logs-app        │
│                 │   │ open-consul-ui  │   │ logs-db         │
└─────────────────┘   └─────────────────┘   └─────────────────┘
```

## 🎮 Interactive Workflows

### Workflow 1: First Deployment

```
START
  ↓
┌──────────────────┐
│ make quick-start │ ← Generates keys, creates config
└──────────────────┘
  ↓
┌──────────────────┐
│ Edit tfvars file │ ← Add your Hetzner API token
└──────────────────┘
  ↓
┌──────────────────┐
│   make plan      │ ← Preview changes (IMPORTANT!)
└──────────────────┘
  ↓
┌──────────────────┐
│   make apply     │ ← Deploy infrastructure
└──────────────────┘
  ↓
┌──────────────────┐
│   make info      │ ← Verify deployment
└──────────────────┘
  ↓
SUCCESS! 🎉
```

### Workflow 2: Daily Operations

```
┌─────────────────────┐
│  make health-check  │ ← Check everything is OK
└─────────────────────┘
         ↓
    ┌────┴────┐
    │   OK?   │
    └────┬────┘
         │ NO
         ↓
┌─────────────────────┐
│    make debug       │ ← Get debug info
└─────────────────────┘
         ↓
┌─────────────────────┐
│  make logs-bastion  │ ← Check logs
└─────────────────────┘
         ↓
┌─────────────────────┐
│ make consul-status  │ ← Check Consul
└─────────────────────┘
```

### Workflow 3: Consul Management

```
┌────────────────────────┐
│ make open-consul-ui    │ ← Open UI in browser
└────────────────────────┘
         ↓
┌────────────────────────┐
│ make consul-services   │ ← List services
└────────────────────────┘
         ↓
┌────────────────────────┐
│ make consul-intentions │ ← View policies
└────────────────────────┘
         ↓
┌────────────────────────┐
│ make consul-setup      │ ← Configure policies
└────────────────────────┘
```

## 🎨 Command Cheat Sheet

### Most Used Commands

| Command | Description | When to Use |
|---------|-------------|-------------|
| `make help` | Show all commands | Starting point |
| `make quick-start` | Complete setup | First time only |
| `make plan` | Preview changes | Before apply |
| `make apply` | Deploy infra | After plan looks good |
| `make info` | Show details | Anytime |
| `make ssh-bastion` | SSH to bastion | Access servers |
| `make consul-status` | Check Consul | Verify mesh |
| `make open-consul-ui` | Open UI | Monitor services |
| `make health-check` | Check health | Regular checks |
| `make logs-bastion` | View logs | Troubleshooting |

### One-Liners for Common Tasks

```bash
# Check if everything is running
make health-check

# Quick deployment info
make info

# Access bastion
make ssh-bastion

# Open Consul dashboard
make open-consul-ui

# See all IPs
make list-ips

# View recent logs
make logs-bastion

# Check what you have deployed
make state-list

# Estimate costs
make cost
```

## 🔄 Update & Maintenance

```bash
# Before making changes
make state-backup           # Backup current state
make plan                   # Preview changes

# Make your changes in *.tf files

make validate              # Check syntax
make fmt                   # Format code
make plan                  # Review plan
make apply                 # Apply changes

# After changes
make health-check          # Verify everything works
```

## 🆘 Troubleshooting Flow

```
┌───────────────┐
│ Problem? 🤔   │
└───────┬───────┘
        ↓
┌───────────────┐
│  make debug   │ ← Start here
└───────┬───────┘
        ↓
┌───────────────┐
│ make test-ssh │ ← Test connectivity
└───────┬───────┘
        ↓
    ┌───┴────┐
    │ Works? │
    └───┬────┘
        │ NO
        ↓
┌──────────────────┐
│ make logs-bastion│ ← Check logs
└──────────────────┘
        ↓
┌──────────────────┐
│make consul-status│ ← Check Consul
└──────────────────┘
```

## 💡 Pro Tips

### Tip 1: Always Preview
```bash
make plan    # ALWAYS run this first
make apply   # Then apply if it looks good
```

### Tip 2: Regular Health Checks
```bash
# Add to your routine
make health-check
make consul-services
```

### Tip 3: Save State Before Changes
```bash
make state-backup  # Before any changes
```

### Tip 4: Use Logs for Debug
```bash
make logs-bastion  # Bastion logs
make logs-app      # App logs
make logs-db       # DB logs
```

### Tip 5: Documentation is Your Friend
```bash
make docs          # List all docs
make help          # Show all commands
```

## 🎯 Quick Reference by Scenario

### "I want to deploy"
```bash
make quick-start
# Edit terraform.tfvars
make plan
make apply
```

### "I want to check status"
```bash
make info
make health-check
make consul-status
```

### "I want to access servers"
```bash
make ssh-bastion
make list-ips
```

### "I want to see logs"
```bash
make logs-bastion
make logs-app
make logs-db
```

### "Something is wrong"
```bash
make debug
make test-ssh
make health-check
make logs-bastion
```

### "I want to monitor Consul"
```bash
make open-consul-ui
make consul-status
make consul-services
make mesh-summary
```

## 📱 Mobile-Friendly Commands

Essential commands you might need remotely:

```bash
make info              # Quick status
make health-check      # Health check
make ssh-bastion       # Access server
make consul-ui         # Get UI URL
make logs-bastion      # Quick logs
```

## 🎓 Learning Path

1. **Day 1**: Setup and Deploy
   ```bash
   make quick-start
   make plan
   make apply
   ```

2. **Day 2**: Explore and Monitor
   ```bash
   make info
   make open-consul-ui
   make health-check
   ```

3. **Day 3**: SSH and Logs
   ```bash
   make ssh-bastion
   make logs-bastion
   make list-ips
   ```

4. **Week 2**: Advanced Management
   ```bash
   make consul-setup
   make state-backup
   make wireguard-info
   ```

## 🏆 Best Practices

✅ **DO**
- Run `make plan` before `make apply`
- Use `make state-backup` before changes
- Check `make health-check` regularly
- Read docs with `make docs`

❌ **DON'T**
- Skip `make plan`
- Use `auto-apply` unless you're sure
- Ignore logs when troubleshooting
- Forget to backup state

---

## 🚀 Ready to Start?

```bash
# Your first command should be:
make help

# Then:
make quick-start

# Happy deploying! 🎉
```

---

**Quick Help**: Run `make help` anytime  
**Full Docs**: See `MAKEFILE-COMMANDS.md`  
**Issues**: Check `README.md` troubleshooting section
