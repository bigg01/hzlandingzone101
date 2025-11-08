.PHONY: help init plan apply destroy validate fmt check clean ssh-bastion wireguard-info cost

# Colors for output
BLUE := \033[0;34m
GREEN := \033[0;32m
RED := \033[0;31m
YELLOW := \033[1;33m
NC := \033[0m # No Color

help: ## Show this help message
	@echo "$(BLUE)Hetzner Landing Zone - Terraform Commands$(NC)"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(GREEN)%-20s$(NC) %s\n", $$1, $$2}'

init: ## Initialize Terraform
	@echo "$(BLUE)Initializing Terraform...$(NC)"
	terraform init

validate: ## Validate Terraform configuration
	@echo "$(BLUE)Validating Terraform configuration...$(NC)"
	terraform validate

fmt: ## Format Terraform files
	@echo "$(BLUE)Formatting Terraform files...$(NC)"
	terraform fmt -recursive

check: validate fmt ## Run validation and formatting
	@echo "$(GREEN)Configuration check complete!$(NC)"

plan: ## Show Terraform execution plan
	@echo "$(BLUE)Planning Terraform deployment...$(NC)"
	terraform plan

apply: ## Apply Terraform configuration
	@echo "$(YELLOW)Applying Terraform configuration...$(NC)"
	terraform apply

auto-apply: ## Apply without confirmation (use with caution!)
	@echo "$(RED)Auto-applying Terraform configuration...$(NC)"
	terraform apply -auto-approve

destroy: ## Destroy all Terraform resources
	@echo "$(RED)Destroying Terraform resources...$(NC)"
	terraform destroy

auto-destroy: ## Destroy without confirmation (use with caution!)
	@echo "$(RED)Auto-destroying Terraform resources...$(NC)"
	terraform destroy -auto-approve

output: ## Show all Terraform outputs
	@echo "$(BLUE)Terraform outputs:$(NC)"
	terraform output

ssh-bastion: ## SSH to bastion host
	@echo "$(BLUE)Connecting to bastion host...$(NC)"
	@terraform output -raw bastion_ssh_command | sh

wireguard-info: ## Get WireGuard configuration from bastion
	@echo "$(BLUE)Retrieving WireGuard configuration...$(NC)"
	@terraform output -raw wireguard_info_command | sh

clean: ## Clean Terraform cache and state backups
	@echo "$(YELLOW)Cleaning Terraform files...$(NC)"
	rm -rf .terraform/
	rm -f .terraform.lock.hcl
	rm -f *.tfstate.backup
	@echo "$(GREEN)Cleanup complete!$(NC)"

cost: ## Estimate monthly costs
	@echo "$(BLUE)Estimated Monthly Costs:$(NC)"
	@echo "  Bastion Host (cx22):     ~€5.29"
	@echo "  Application Servers:      €5.29 per instance"
	@echo "  Database Servers:         €5.29 per instance"
	@echo "  Network:                  Free"
	@echo "  Firewalls:                Free"
	@echo "  Placement Groups:         Free"
	@echo "  Consul Service Mesh:      Free (self-hosted)"
	@echo "  $(GREEN)Base Total:               ~€5.29 + servers$(NC)"

consul-status: ## Check Consul service mesh status
	@echo "$(BLUE)Checking Consul status...$(NC)"
	@BASTION_IP=$$(terraform output -raw bastion_public_ip 2>/dev/null); \
	if [ -z "$$BASTION_IP" ]; then \
		echo "$(RED)Error: Could not get bastion IP$(NC)"; \
		exit 1; \
	fi; \
	ssh -i ./id_ed25519_hetzner_cloud_k3s -o StrictHostKeyChecking=no admin@$$BASTION_IP 'consul members'

consul-services: ## List registered Consul services
	@echo "$(BLUE)Registered Consul services:$(NC)"
	@BASTION_IP=$$(terraform output -raw bastion_public_ip 2>/dev/null); \
	ssh -i ./id_ed25519_hetzner_cloud_k3s -o StrictHostKeyChecking=no admin@$$BASTION_IP 'consul catalog services'

consul-intentions: ## Show Consul service intentions (access policies)
	@echo "$(BLUE)Consul service intentions:$(NC)"
	@BASTION_IP=$$(terraform output -raw bastion_public_ip 2>/dev/null); \
	ssh -i ./id_ed25519_hetzner_cloud_k3s -o StrictHostKeyChecking=no admin@$$BASTION_IP 'consul intention list'

consul-setup: ## Setup Consul service mesh policies
	@echo "$(BLUE)Configuring Consul service mesh...$(NC)"
	@BASTION_IP=$$(terraform output -raw bastion_public_ip 2>/dev/null); \
	ssh -i ./id_ed25519_hetzner_cloud_k3s -o StrictHostKeyChecking=no admin@$$BASTION_IP 'sudo /usr/local/bin/setup-consul-intentions.sh'

consul-ui: ## Get Consul UI URL
	@terraform output -raw consul_ui_url

consul-manage: ## Run Consul management script
	@echo "$(BLUE)Running Consul management script...$(NC)"
	@BASTION_IP=$$(terraform output -raw bastion_public_ip 2>/dev/null); \
	./consul-manage.sh $$BASTION_IP

info: ## Show deployment information
	@echo "$(BLUE)Landing Zone Information:$(NC)"
	@echo ""
	@echo "Network Details:"
	@terraform output network_name
	@terraform output network_ip_range
	@echo ""
	@echo "Bastion Host:"
	@terraform output bastion_public_ip
	@terraform output bastion_private_ip
	@echo ""
	@echo "Subnets:"
	@terraform output subnet_management_ip_range
	@terraform output subnet_application_ip_range
	@terraform output subnet_services_ip_range
	@terraform output subnet_dmz_ip_range
	@echo ""
	@echo "$(BLUE)Service Mesh:$(NC)"
	@terraform output consul_ui_url
	@echo ""
	@echo "Application Servers:"
	@terraform output application_server_ips
	@echo ""
	@echo "Database Servers:"
	@terraform output database_server_ips

mesh-summary: ## Show service mesh deployment summary
	@terraform output -raw service_mesh_summary

test-ssh: ## Test SSH connection to bastion
	@echo "$(BLUE)Testing SSH connection...$(NC)"
	@BASTION_IP=$$(terraform output -raw bastion_public_ip 2>/dev/null); \
	if [ -z "$$BASTION_IP" ]; then \
		echo "$(RED)Error: Could not get bastion IP. Has the infrastructure been deployed?$(NC)"; \
		exit 1; \
	fi; \
	echo "Testing connection to $$BASTION_IP..."; \
	ssh -i ./id_ed25519_hetzner_cloud_k3s -o ConnectTimeout=5 -o StrictHostKeyChecking=no admin@$$BASTION_IP "echo '$(GREEN)SSH connection successful!$(NC)'" || \
	echo "$(RED)SSH connection failed!$(NC)"

setup-vars: ## Create terraform.tfvars from example
	@if [ -f terraform.tfvars ]; then \
		echo "$(YELLOW)terraform.tfvars already exists. Skipping...$(NC)"; \
	else \
		echo "$(BLUE)Creating terraform.tfvars from example...$(NC)"; \
		cp terraform.tfvars.example terraform.tfvars; \
		echo "$(GREEN)Created! Please edit terraform.tfvars with your values.$(NC)"; \
	fi

generate-ssh-key: ## Generate SSH key pair
	@if [ -f ./id_ed25519_hetzner_cloud_k3s ]; then \
		echo "$(YELLOW)SSH key already exists. Skipping...$(NC)"; \
	else \
		echo "$(BLUE)Generating SSH key pair...$(NC)"; \
		ssh-keygen -t ed25519 -f ./id_ed25519_hetzner_cloud_k3s -C "hetzner-landing-zone" -N ""; \
		echo "$(GREEN)SSH key generated!$(NC)"; \
	fi

quick-start: generate-ssh-key setup-vars init ## Quick setup for new deployments
	@echo "$(GREEN)Quick start complete!$(NC)"
	@echo "$(YELLOW)Next steps:$(NC)"
	@echo "  1. Edit terraform.tfvars with your Hetzner API token"
	@echo "  2. Run 'make plan' to preview changes"
	@echo "  3. Run 'make apply' to deploy"

open-consul-ui: ## Open Consul UI in browser
	@echo "$(BLUE)Opening Consul UI...$(NC)"
	@CONSUL_URL=$$(terraform output -raw consul_ui_url 2>/dev/null); \
	if [ -z "$$CONSUL_URL" ]; then \
		echo "$(RED)Error: Could not get Consul UI URL$(NC)"; \
		exit 1; \
	fi; \
	echo "Opening $$CONSUL_URL..."; \
	xdg-open "$$CONSUL_URL" 2>/dev/null || open "$$CONSUL_URL" 2>/dev/null || echo "Please open: $$CONSUL_URL"

logs-bastion: ## View bastion host logs
	@echo "$(BLUE)Fetching bastion logs...$(NC)"
	@BASTION_IP=$$(terraform output -raw bastion_public_ip 2>/dev/null); \
	ssh -i ./id_ed25519_hetzner_cloud_k3s -o StrictHostKeyChecking=no admin@$$BASTION_IP 'sudo journalctl -u consul -n 50 --no-pager'

logs-app: ## View application server logs
	@echo "$(BLUE)Fetching application server logs...$(NC)"
	@APP_IP=$$(terraform output -json application_server_ips | jq -r '.[0]' 2>/dev/null); \
	BASTION_IP=$$(terraform output -raw bastion_public_ip 2>/dev/null); \
	if [ -z "$$APP_IP" ] || [ "$$APP_IP" = "null" ]; then \
		echo "$(RED)No application servers found$(NC)"; \
		exit 1; \
	fi; \
	ssh -i ./id_ed25519_hetzner_cloud_k3s -o StrictHostKeyChecking=no -J admin@$$BASTION_IP admin@$$APP_IP 'sudo journalctl -u consul -n 50 --no-pager'

logs-db: ## View database server logs
	@echo "$(BLUE)Fetching database server logs...$(NC)"
	@DB_IP=$$(terraform output -json database_server_ips | jq -r '.[0]' 2>/dev/null); \
	BASTION_IP=$$(terraform output -raw bastion_public_ip 2>/dev/null); \
	if [ -z "$$DB_IP" ] || [ "$$DB_IP" = "null" ]; then \
		echo "$(RED)No database servers found$(NC)"; \
		exit 1; \
	fi; \
	ssh -i ./id_ed25519_hetzner_cloud_k3s -o StrictHostKeyChecking=no -J admin@$$BASTION_IP admin@$$DB_IP 'sudo journalctl -u consul -n 50 --no-pager'

health-check: ## Check health of all services
	@echo "$(BLUE)Checking service health...$(NC)"
	@BASTION_IP=$$(terraform output -raw bastion_public_ip 2>/dev/null); \
	echo "Consul Cluster:"; \
	ssh -i ./id_ed25519_hetzner_cloud_k3s -o StrictHostKeyChecking=no admin@$$BASTION_IP 'consul members' || echo "$(RED)Failed$(NC)"; \
	echo ""; \
	echo "Registered Services:"; \
	ssh -i ./id_ed25519_hetzner_cloud_k3s -o StrictHostKeyChecking=no admin@$$BASTION_IP 'consul catalog services' || echo "$(RED)Failed$(NC)"; \
	echo ""; \
	echo "Service Health:"; \
	ssh -i ./id_ed25519_hetzner_cloud_k3s -o StrictHostKeyChecking=no admin@$$BASTION_IP 'consul catalog nodes -detailed' || echo "$(RED)Failed$(NC)"

list-ips: ## List all server IPs
	@echo "$(BLUE)Server IP Addresses:$(NC)"
	@echo "Bastion (Public):  $$(terraform output -raw bastion_public_ip 2>/dev/null)"
	@echo "Bastion (Private): $$(terraform output -raw bastion_private_ip 2>/dev/null)"
	@echo ""
	@echo "Application Servers:"
	@terraform output -json application_server_ips 2>/dev/null | jq -r '.[]' | nl -w2 -s'. '
	@echo ""
	@echo "Database Servers:"
	@terraform output -json database_server_ips 2>/dev/null | jq -r '.[]' | nl -w2 -s'. '

state-list: ## List all Terraform state resources
	@echo "$(BLUE)Terraform State Resources:$(NC)"
	@terraform state list

state-backup: ## Backup Terraform state
	@echo "$(BLUE)Backing up Terraform state...$(NC)"
	@cp terraform.tfstate terraform.tfstate.backup.$$(date +%Y%m%d_%H%M%S)
	@echo "$(GREEN)State backed up!$(NC)"

docs: ## Generate/view documentation
	@echo "$(BLUE)Available Documentation:$(NC)"
	@echo ""
	@ls -1 *.md 2>/dev/null | sed 's/^/  - /'
	@echo ""
	@echo "$(YELLOW)Quick Links:$(NC)"
	@echo "  - README.md                    - Main documentation"
	@echo "  - README-REFACTORING.md        - Code refactoring guide"
	@echo "  - REFACTORING-SUMMARY.md       - Quick refactoring reference"
	@echo "  - CONSUL-QUICKSTART.md         - Consul setup guide"
	@echo "  - CONSUL-UI-FIX.md             - Consul UI access fix"
	@echo "  - FIX-SUMMARY.md               - Recent fixes summary"

debug: ## Show debug information
	@echo "$(BLUE)Debug Information:$(NC)"
	@echo ""
	@echo "Terraform Version:"
	@terraform version
	@echo ""
	@echo "SSH Key Status:"
	@ls -lh ./id_ed25519_hetzner_cloud_k3s* 2>/dev/null || echo "$(RED)SSH keys not found$(NC)"
	@echo ""
	@echo "Config Files:"
	@ls -lh terraform.tfvars 2>/dev/null || echo "$(YELLOW)terraform.tfvars not found$(NC)"
	@echo ""
	@echo "Terraform State:"
	@ls -lh terraform.tfstate 2>/dev/null || echo "$(YELLOW)No state file (not deployed yet)$(NC)"
