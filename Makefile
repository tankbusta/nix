.PHONY: help update build switch test boot check show clean gc-user gc-system gc-all

# Get the hostname of the current system
HOSTNAME := $(shell hostname)

help: ## Show this help message
	@echo "NixOS Configuration Management"
	@echo ""
	@echo "Current hostname: $(HOSTNAME)"
	@echo ""
	@echo "Available targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'

update: ## Update all flake inputs
	nix flake update

update-nixpkgs: ## Update only nixpkgs input
	nix flake lock --update-input nixpkgs

update-home: ## Update only home-manager input
	nix flake lock --update-input home-manager

build: ## Build the system configuration
	sudo nixos-rebuild build --flake .#$(HOSTNAME)

switch: ## Build and switch to new configuration
	sudo nixos-rebuild switch --flake .#$(HOSTNAME)

test: ## Build and test configuration (temporary, reverts on reboot)
	sudo nixos-rebuild test --flake .#$(HOSTNAME)

boot: ## Build and set as boot default (activates on next boot)
	sudo nixos-rebuild boot --flake .#$(HOSTNAME)

check: ## Check flake for errors
	nix flake check

show: ## Show flake outputs
	nix flake show

dry-build: ## Show what would be built without building
	nixos-rebuild dry-build --flake .#$(HOSTNAME)

diff: ## Show diff between current and new generation
	nvd diff /run/current-system ./result

gc-user: ## Run garbage collection for user
	nix-collect-garbage -d

gc-system: ## Run garbage collection for system (requires sudo)
	sudo nix-collect-garbage -d

gc-all: gc-user gc-system ## Run garbage collection for both user and system

clean: ## Remove result symlinks
	rm -f result

rebuild: update switch ## Update flake inputs and switch to new configuration

.DEFAULT_GOAL := help
