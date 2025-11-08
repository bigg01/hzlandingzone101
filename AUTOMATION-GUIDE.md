# VM Automation & Configuration Management Guide

## Overview

Your infrastructure is deployed, now you need to **automate configuration, deployments, and ongoing management**. This guide covers tools that work well with Hetzner Cloud VMs.

## Quick Comparison

| Tool | Best For | Complexity | Agent Required | Learning Curve |
|------|----------|------------|----------------|----------------|
| **cloud-init** | Initial setup | Low | No | Easy |
| **Ansible** | Config management | Low-Medium | No (SSH) | Easy |
| **Terraform + Provisioners** | Infrastructure + config | Medium | No | Medium |
| **Packer** | Custom images | Medium | No | Medium |
| **Salt** | Large scale, fast | Medium-High | Yes | Medium-High |
| **Puppet** | Enterprise, compliance | High | Yes | High |
| **Chef** | Complex workflows | High | Yes | High |
| **NixOS** | Declarative OS | Medium-High | No | High |

## Recommended Stack for Your Setup

```
┌─────────────────────────────────────────────┐
│  Terraform                                  │
│  Infrastructure Provisioning                │
│  (What you have now)                        │
└─────────────────┬───────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────────┐
│  cloud-init                                 │
│  Initial Bootstrap                          │
│  (You're already using this)                │
└─────────────────┬───────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────────┐
│  Ansible                                    │
│  Configuration Management                   │
│  + Application Deployment                   │
│  (Recommended to add)                       │
└─────────────────┬───────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────────┐
│  Packer (Optional)                          │
│  Custom Images                              │
│  (For faster deployment)                    │
└─────────────────────────────────────────────┘
```

---

## 1. Cloud-init (You're Already Using This!)

**What you have now:**
- Basic package installation
- User creation
- WireGuard setup on bastion
- PostgreSQL configuration on database servers

**How to extend it:**

### Add Configuration Files

```yaml
#cloud-config
write_files:
  - path: /etc/myapp/config.yaml
    owner: root:root
    permissions: '0644'
    content: |
      database:
        host: 172.16.2.10
        port: 5432
        name: app_db
      redis:
        host: 172.16.2.20
        port: 6379
  
  - path: /etc/systemd/system/myapp.service
    owner: root:root
    permissions: '0644'
    content: |
      [Unit]
      Description=My Application
      After=network.target
      
      [Service]
      Type=simple
      User=admin
      WorkingDirectory=/opt/myapp
      ExecStart=/opt/myapp/bin/start
      Restart=always
      
      [Install]
      WantedBy=multi-user.target

runcmd:
  - systemctl daemon-reload
  - systemctl enable myapp
  - systemctl start myapp
```

**Limitations:**
- ❌ Runs only once at first boot
- ❌ Hard to test before deployment
- ❌ No idempotency (can't re-run safely)
- ❌ Complex logic is difficult
- ✅ Good for initial bootstrap only

---

## 2. Ansible (HIGHLY RECOMMENDED)

**Why Ansible is perfect for your setup:**
- ✅ **Agentless** - uses SSH (you already have this configured)
- ✅ **Idempotent** - safe to run multiple times
- ✅ **Simple** - YAML-based, easy to learn
- ✅ **Rich modules** - 3,000+ built-in modules
- ✅ **Ansible Vault** - encrypted secrets management
- ✅ **Works with Terraform** - perfect companion

### Installation

```bash
# On your laptop/bastion
sudo apt install ansible -y

# Or via pip for latest version
pip3 install ansible
```

### Complete Setup Example

#### 1. Create Ansible Inventory

```bash
cd hzlandingzone
mkdir -p ansible/{inventories,playbooks,roles,group_vars,host_vars}
```

**ansible/inventories/production.ini:**
```ini
[bastion]
bastion ansible_host=91.98.27.105

[application]
app-1 ansible_host=172.16.1.10
app-2 ansible_host=172.16.1.11

[database]
db-1 ansible_host=172.16.2.10
db-2 ansible_host=172.16.2.11

[all:vars]
ansible_user=admin
ansible_ssh_private_key_file=./id_ed25519_hetzner_cloud_k3s
ansible_ssh_common_args='-o StrictHostKeyChecking=no'

# For servers behind bastion (via VPN or jump host)
[application:vars]
ansible_ssh_common_args='-o ProxyJump=admin@91.98.27.105 -o StrictHostKeyChecking=no'

[database:vars]
ansible_ssh_common_args='-o ProxyJump=admin@91.98.27.105 -o StrictHostKeyChecking=no'
```

#### 2. Create Ansible Playbooks

**ansible/playbooks/site.yml** (Main playbook):
```yaml
---
- name: Configure all servers
  hosts: all
  become: yes
  
  tasks:
    - name: Update apt cache
      apt:
        update_cache: yes
        cache_valid_time: 3600
    
    - name: Install common packages
      apt:
        name:
          - htop
          - vim
          - curl
          - git
          - tmux
          - net-tools
        state: present
    
    - name: Configure timezone
      timezone:
        name: UTC
    
    - name: Setup NTP
      systemd:
        name: systemd-timesyncd
        enabled: yes
        state: started

- name: Configure bastion
  hosts: bastion
  become: yes
  roles:
    - bastion

- name: Configure application servers
  hosts: application
  become: yes
  roles:
    - common
    - webserver
    - application

- name: Configure database servers
  hosts: database
  become: yes
  roles:
    - common
    - database
```

**ansible/playbooks/deploy-app.yml** (Application deployment):
```yaml
---
- name: Deploy application
  hosts: application
  become: yes
  
  vars:
    app_version: "{{ lookup('env', 'APP_VERSION') | default('latest', true) }}"
    app_repo: "https://github.com/yourorg/yourapp.git"
    app_path: /opt/myapp
    
  tasks:
    - name: Install application dependencies
      apt:
        name:
          - python3
          - python3-pip
          - python3-venv
          - nginx
        state: present
    
    - name: Create application directory
      file:
        path: "{{ app_path }}"
        state: directory
        owner: admin
        group: admin
        mode: '0755'
    
    - name: Clone/update application repository
      git:
        repo: "{{ app_repo }}"
        dest: "{{ app_path }}"
        version: "{{ app_version }}"
      notify: restart application
    
    - name: Install Python dependencies
      pip:
        requirements: "{{ app_path }}/requirements.txt"
        virtualenv: "{{ app_path }}/venv"
        virtualenv_command: python3 -m venv
    
    - name: Copy environment configuration
      template:
        src: templates/app.env.j2
        dest: "{{ app_path }}/.env"
        owner: admin
        group: admin
        mode: '0600'
      notify: restart application
    
    - name: Copy systemd service file
      template:
        src: templates/myapp.service.j2
        dest: /etc/systemd/system/myapp.service
        owner: root
        group: root
        mode: '0644'
      notify:
        - reload systemd
        - restart application
    
    - name: Enable and start application
      systemd:
        name: myapp
        enabled: yes
        state: started
    
    - name: Configure nginx
      template:
        src: templates/nginx-app.conf.j2
        dest: /etc/nginx/sites-available/myapp
        owner: root
        group: root
        mode: '0644'
      notify: reload nginx
    
    - name: Enable nginx site
      file:
        src: /etc/nginx/sites-available/myapp
        dest: /etc/nginx/sites-enabled/myapp
        state: link
      notify: reload nginx
  
  handlers:
    - name: reload systemd
      systemd:
        daemon_reload: yes
    
    - name: restart application
      systemd:
        name: myapp
        state: restarted
    
    - name: reload nginx
      systemd:
        name: nginx
        state: reloaded
```

**ansible/playbooks/update-security.yml** (Security updates):
```yaml
---
- name: Apply security updates
  hosts: all
  become: yes
  serial: 2  # Update 2 servers at a time
  
  tasks:
    - name: Update all packages
      apt:
        update_cache: yes
        upgrade: dist
        autoremove: yes
        autoclean: yes
    
    - name: Check if reboot required
      stat:
        path: /var/run/reboot-required
      register: reboot_required
    
    - name: Reboot if required
      reboot:
        msg: "Reboot initiated by Ansible for updates"
        reboot_timeout: 600
      when: reboot_required.stat.exists
    
    - name: Wait for server to come back
      wait_for_connection:
        delay: 30
        timeout: 300
      when: reboot_required.stat.exists
```

#### 3. Create Ansible Roles

**ansible/roles/common/tasks/main.yml:**
```yaml
---
- name: Install security packages
  apt:
    name:
      - ufw
      - fail2ban
      - unattended-upgrades
    state: present

- name: Configure UFW default policies
  ufw:
    default: deny
    direction: incoming

- name: Allow SSH
  ufw:
    rule: allow
    port: '22'
    proto: tcp

- name: Enable UFW
  ufw:
    state: enabled

- name: Configure unattended upgrades
  template:
    src: 50unattended-upgrades.j2
    dest: /etc/apt/apt.conf.d/50unattended-upgrades
    owner: root
    group: root
    mode: '0644'
```

**ansible/roles/webserver/tasks/main.yml:**
```yaml
---
- name: Install nginx
  apt:
    name: nginx
    state: present

- name: Remove default nginx site
  file:
    path: /etc/nginx/sites-enabled/default
    state: absent
  notify: reload nginx

- name: Configure nginx
  template:
    src: nginx.conf.j2
    dest: /etc/nginx/nginx.conf
  notify: reload nginx

- name: Ensure nginx is running
  systemd:
    name: nginx
    enabled: yes
    state: started
```

#### 4. Create Templates

**ansible/roles/common/templates/50unattended-upgrades.j2:**
```
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}-security";
};
Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::MinimalSteps "true";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
```

#### 5. Create Group Variables

**ansible/group_vars/application.yml:**
```yaml
---
app_environment: production
database_host: 172.16.2.10
database_port: 5432
database_name: app_db
redis_host: 172.16.2.20
redis_port: 6379
```

**ansible/group_vars/all.yml:**
```yaml
---
timezone: UTC
ntp_servers:
  - time.cloudflare.com
  - time.google.com
```

#### 6. Use Ansible Vault for Secrets

```bash
# Create encrypted file
ansible-vault create ansible/group_vars/all/vault.yml

# Content:
# ---
# vault_database_password: "super_secret_password"
# vault_app_secret_key: "another_secret"

# Edit encrypted file
ansible-vault edit ansible/group_vars/all/vault.yml

# Use in playbooks
# database_password: "{{ vault_database_password }}"
```

#### 7. Run Playbooks

```bash
# Test connectivity
ansible all -i ansible/inventories/production.ini -m ping

# Run full configuration
ansible-playbook -i ansible/inventories/production.ini ansible/playbooks/site.yml

# Deploy application
ansible-playbook -i ansible/inventories/production.ini ansible/playbooks/deploy-app.yml

# With vault password
ansible-playbook -i ansible/inventories/production.ini ansible/playbooks/site.yml --ask-vault-pass

# Dry run (check mode)
ansible-playbook -i ansible/inventories/production.ini ansible/playbooks/site.yml --check

# Run on specific hosts
ansible-playbook -i ansible/inventories/production.ini ansible/playbooks/site.yml --limit application
```

### Integrate Ansible with Terraform

**Option 1: Use local-exec provisioner**

Add to your `main.tf`:
```terraform
resource "null_resource" "provision_with_ansible" {
  depends_on = [
    hcloud_server.bastion,
    hcloud_server.application,
    hcloud_server.database
  ]

  provisioner "local-exec" {
    command = <<-EOT
      # Wait for servers to be ready
      sleep 60
      
      # Run Ansible
      ansible-playbook \
        -i ansible/inventories/production.ini \
        ansible/playbooks/site.yml
    EOT
  }

  triggers = {
    server_ids = join(",", concat(
      [hcloud_server.bastion.id],
      hcloud_server.application[*].id,
      hcloud_server.database[*].id
    ))
  }
}
```

**Option 2: Generate inventory from Terraform**

```terraform
# outputs.tf
output "ansible_inventory" {
  value = templatefile("${path.module}/templates/inventory.tpl", {
    bastion_ip = hcloud_server.bastion.ipv4_address,
    app_servers = [
      for s in hcloud_server.application : {
        name = s.name
        ip   = [for net in s.network : net.ip][0]
      }
    ],
    db_servers = [
      for s in hcloud_server.database : {
        name = s.name
        ip   = [for net in s.network : net.ip][0]
      }
    ]
  })
}

# Generate inventory file
resource "local_file" "ansible_inventory" {
  content  = templatefile("${path.module}/templates/inventory.tpl", {
    bastion_ip = hcloud_server.bastion.ipv4_address,
    app_servers = [
      for s in hcloud_server.application : {
        name = s.name
        ip   = [for net in s.network : net.ip][0]
      }
    ],
    db_servers = [
      for s in hcloud_server.database : {
        name = s.name
        ip   = [for net in s.network : net.ip][0]
      }
    ]
  })
  filename = "${path.module}/ansible/inventories/terraform-generated.ini"
}
```

**templates/inventory.tpl:**
```ini
[bastion]
bastion ansible_host=${bastion_ip}

[application]
%{ for server in app_servers ~}
${server.name} ansible_host=${server.ip}
%{ endfor ~}

[database]
%{ for server in db_servers ~}
${server.name} ansible_host=${server.ip}
%{ endfor ~}

[all:vars]
ansible_user=admin
ansible_ssh_private_key_file=./id_ed25519_hetzner_cloud_k3s
ansible_ssh_common_args='-o StrictHostKeyChecking=no'

[application:vars]
ansible_ssh_common_args='-o ProxyJump=admin@${bastion_ip} -o StrictHostKeyChecking=no'

[database:vars]
ansible_ssh_common_args='-o ProxyJump=admin@${bastion_ip} -o StrictHostKeyChecking=no'
```

---

## 3. Packer (Custom Images)

**Use case:** Pre-bake images with your software installed, faster deployment

### Example Packer Template

**packer/ubuntu-app-server.pkr.hcl:**
```hcl
packer {
  required_plugins {
    hcloud = {
      version = ">= 1.0.0"
      source  = "github.com/hashicorp/hcloud"
    }
  }
}

variable "hcloud_token" {
  type      = string
  sensitive = true
}

source "hcloud" "ubuntu" {
  token         = var.hcloud_token
  image         = "ubuntu-24.04"
  location      = "nbg1"
  server_type   = "cx22"
  ssh_username  = "root"
  snapshot_name = "app-server-${formatdate("YYYY-MM-DD-hhmm", timestamp())}"
  snapshot_labels = {
    type    = "app-server"
    version = "1.0"
  }
}

build {
  sources = ["source.hcloud.ubuntu"]

  # Update system
  provisioner "shell" {
    inline = [
      "apt-get update",
      "apt-get upgrade -y",
      "apt-get install -y nginx python3 python3-pip git curl",
    ]
  }

  # Run Ansible for detailed configuration
  provisioner "ansible" {
    playbook_file = "./ansible/playbooks/bake-image.yml"
  }

  # Cleanup
  provisioner "shell" {
    inline = [
      "apt-get clean",
      "rm -rf /tmp/*",
      "rm -rf /var/tmp/*",
      "history -c",
    ]
  }
}
```

**Build and use:**
```bash
# Build image
packer build -var-file=packer.vars.hcl packer/ubuntu-app-server.pkr.hcl

# Use in Terraform
resource "hcloud_server" "application" {
  image = data.hcloud_image.app_server.id  # Use your snapshot
  # ...
}
```

---

## 4. Other Tools

### Salt Stack
```bash
# Master-minion or masterless
# Very fast, good for large scale
# Uses Python like Ansible
# Requires agents (salt-minion)

# Good if you have 100+ servers
```

### Puppet
```bash
# Enterprise-grade
# Strong compliance/auditing
# Steep learning curve
# Agent-based

# Good for: Large orgs, compliance requirements
```

### Chef
```bash
# Ruby-based DSL
# Very powerful but complex
# Agent-based

# Good for: Complex workflows, large teams
```

### NixOS
```bash
# Declarative OS configuration
# Atomic upgrades/rollbacks
# Different paradigm

# Good for: Reproducible systems, dev/prod parity
```

---

## Recommended Workflow

### Initial Setup
```bash
1. Terraform apply → Create infrastructure
2. cloud-init → Bootstrap (packages, users)
3. Ansible → Configure everything else
4. (Optional) Packer → Bake images for faster future deployments
```

### Day 2 Operations
```bash
# Deploy new app version
ansible-playbook -i inventories/prod.ini playbooks/deploy-app.yml \
  -e "app_version=v2.1.0"

# Apply security updates
ansible-playbook -i inventories/prod.ini playbooks/update-security.yml

# Add new database user
ansible-playbook -i inventories/prod.ini playbooks/database.yml \
  -e "db_user=newapp" -e "db_name=newapp_db"

# Rotate secrets
ansible-playbook -i inventories/prod.ini playbooks/rotate-secrets.yml \
  --ask-vault-pass
```

### CI/CD Integration
```yaml
# .github/workflows/deploy.yml
name: Deploy Application

on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Setup Ansible
        run: pip3 install ansible
      
      - name: Deploy to production
        run: |
          ansible-playbook \
            -i ansible/inventories/production.ini \
            ansible/playbooks/deploy-app.yml \
            -e "app_version=${{ github.sha }}"
        env:
          ANSIBLE_VAULT_PASSWORD: ${{ secrets.ANSIBLE_VAULT_PASSWORD }}
```

---

## Next Steps

1. **Start with Ansible today:**
```bash
cd hzlandingzone
mkdir -p ansible/{inventories,playbooks,roles}
# Create basic inventory
# Write simple playbook
# Test on one server
```

2. **Build up gradually:**
- Week 1: Basic playbooks (install packages)
- Week 2: Configuration management (nginx, app config)
- Week 3: Application deployment
- Week 4: CI/CD integration

3. **Consider Packer later:**
- Once your Ansible playbooks are stable
- When you need faster deployment
- When you deploy frequently

---

## Resources

### Ansible
- **Official Docs**: https://docs.ansible.com/
- **Galaxy** (roles): https://galaxy.ansible.com/
- **Molecule** (testing): https://molecule.readthedocs.io/

### Packer
- **Official Docs**: https://www.packer.io/docs
- **Hetzner Plugin**: https://github.com/hashicorp/packer-plugin-hcloud

### Best Practices
- Keep playbooks in Git
- Use Ansible Vault for secrets
- Test in dev environment first
- Use tags for selective runs
- Document your roles
- Keep roles small and focused

---

Last Updated: November 8, 2025
