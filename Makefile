SHELL := /bin/bash
.DEFAULT_GOAL := help

VENV            := .venv
ANSIBLE_BIN     := $(VENV)/bin
VAULT_PASS_FILE := .secrets/vault-pass
VAULT_ARGS      := $(if $(wildcard $(VAULT_PASS_FILE)),--vault-password-file $(VAULT_PASS_FILE),)

# Keep pip from writing its cache to ~/.cache (CLAUDE.md rule 2).
export PIP_NO_CACHE_DIR := 1
export PIP_DISABLE_PIP_VERSION_CHECK := 1
export LIBVIRT_DEFAULT_URI := qemu:///system

.PHONY: help venv collections dirs preflight network clean-venv

help: ## Show targets
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-12s %s\n", $$1, $$2}'

venv: $(ANSIBLE_BIN)/ansible-playbook ## Create .venv with ansible-core

$(ANSIBLE_BIN)/ansible-playbook: requirements.txt
	python3 -m venv --system-site-packages $(VENV)
	$(VENV)/bin/python -m pip install -r requirements.txt
	@touch $@

collections: venv ## Install Ansible collections into ./collections
	$(ANSIBLE_BIN)/ansible-galaxy collection install -r requirements.yml -p collections

dirs:
	@mkdir -p .ansible/tmp .ssh .secrets tmp images
	@chmod 700 .ssh .secrets

preflight: collections dirs ## Read-only host checks (phase 1)
	$(ANSIBLE_BIN)/ansible-playbook playbooks/00-preflight.yml $(VAULT_ARGS)

network: collections dirs ## Lab network + storage pool (phase 2)
	$(ANSIBLE_BIN)/ansible-playbook playbooks/10-network.yml $(VAULT_ARGS)

clean-venv: ## Remove .venv and ./collections
	rm -rf $(VENV) collections
