# Plan: automating the Linux VMs

Status: **approved for implementation** (2026-11-25). Windows 11 is out of scope for this plan.

## Decisions

| # | Topic | Decision |
|---|---|---|
| 1 | VM disk location | libvirt default pool (`/var/lib/libvirt/images`), managed only through the libvirt API |
| 2 | Network isolation | NAT during build; host egress firewall (guests can't reach the host or LAN) before any attack testing |
| 3 | Sudo rule scope | Host only. `become` inside lab VMs doesn't need approval |
| 4 | Version control | git, remote repo `detection-lab` |

## Repo layout

```
Detection-Lab/
├── CLAUDE.md
├── README.md
├── ansible.cfg              # collections_path, local_tmp, UserKnownHostsFile → repo
├── requirements.yml         # community.libvirt, community.general, ansible.posix
├── Makefile                 # preflight / up / provision / snapshot / destroy
├── .gitignore
├── inventory/
│   ├── hosts.yml            # lab VMs + per-VM IP, MAC, sizing (host NOT listed)
│   ├── vault.example.yml    # template for the encrypted vault
│   └── group_vars/
│       ├── all/main.yml     # network, image + Wazuh version pins
│       ├── all/vault.yml    # Ansible Vault: Wazuh admin pw, enrollment pw
│       ├── wazuh_server.yml
│       └── linux_endpoints.yml
├── playbooks/
│   ├── site.yml
│   ├── 00-preflight.yml
│   ├── 10-network.yml
│   ├── 20-vms.yml
│   ├── 30-wazuh-server.yml
│   ├── 40-linux-agents.yml
│   ├── 50-snapshot.yml
│   ├── 60-egress-firewall.yml   # host-side, needs sudo (see phase 7)
│   └── 99-destroy.yml
├── roles/
│   ├── lab_network/
│   ├── lab_vm/
│   ├── wazuh_server/
│   ├── wazuh_agent_linux/
│   └── auditd/
├── detections/{rules,decoders}/   # later
├── windows/                       # later
└── docs/
    ├── PLAN.md
    ├── architecture.md
    └── host-setup.md
```

Gitignored: `.venv/`, `collections/`, `images/`, `tmp/`, `.secrets/`, `.ssh/`, `.ansible/`.

## Address plan

| Host | IP | MAC | vCPU / RAM / disk |
|---|---|---|---|
| host bridge `virbr-detlab` | 10.10.10.1 | — | — |
| wazuh-server | 10.10.10.10 | 52:54:00:10:10:10 | 4 / 8 GB / 60 GB |
| ubuntu-ep | 10.10.10.20 | 52:54:00:10:10:20 | 2 / 2 GB / 20 GB |
| win11-ep (later) | 10.10.10.30 | 52:54:00:10:10:30 | 2–4 / 6 GB / 64 GB |

IPs come from libvirt DHCP reservations keyed on fixed MACs. Both are defined in the inventory, the only source of truth.

## Phases

### 0. Host setup (one time; sudo; you run it)
Written up in `docs/host-setup.md`:
1. `sudo dnf install @virtualization python3-libvirt python3-lxml xorriso`
2. Enable the modular libvirt daemon sockets (`virtqemud`, `virtnetworkd`, `virtstoraged`).
3. `sudo usermod -aG libvirt $USER`, then log out and back in. Note: being in this group is effectively root on the host.

No sudo needed after that:
- `python3 -m venv --system-site-packages .venv`, then `pip install ansible-core`
- `ansible-galaxy collection install -r requirements.yml` (into `./collections`)

### 1. Preflight (`00-preflight.yml`, read-only)
- Tools present, `qemu:///system` reachable without sudo.
- 10.10.10.0/24 doesn't collide with existing routes (Docker, Podman, VPN).
- Enough free RAM and pool space.

### 2. Network + storage pool (`10-network.yml`, `make network`) ✅ done 2026-11-26
- `community.libvirt.virt_net`: network `detlab`, NAT mode, bridge `virbr-detlab`, DNS domain `detlab.internal`, DHCP reservations from the inventory, autostart.
- `community.libvirt.virt_pool`: `default` dir pool at `/var/lib/libvirt/images` (this host had none), autostart.
- Gotcha: `virt_net`/`virt_pool` `command: define` is **create-only**, so later template edits are ignored. DHCP reservations are synced with `command: modify` instead, and the role fails if the live subnet, bridge or forward mode drifts from the inventory.

### 3. VMs (`20-vms.yml`, role `lab_vm`)
1. Download the pinned Ubuntu 24.04 cloud image to `images/` and verify it against Canonical's `SHA256SUMS`.
2. `virsh vol-upload` the base image into the default pool. Create per-VM overlays with `vol-create-as --backing-vol`.
3. Generate the lab SSH keypair in `.secrets/`.
4. Render cloud-init: hostname, `lab` user + key, `qemu-guest-agent`, timezone.
5. `virt-install --import --cloud-init … --mac …`, skipped if the domain already exists.
6. Wait for SSH, then `cloud-init status --wait`.

### 4. Wazuh server (`30-wazuh-server.yml`)
1. Download the official assisted installer for the pinned version **on the VM** (correct `packages.wazuh.com/<major>.x/` path).
2. Run `bash wazuh-install.sh -a` with `creates:` so a rerun doesn't reinstall.
3. Fetch `wazuh-install-files.tar` into `.secrets/` and put the admin password in Vault.
4. Turn on password-based agent enrollment (`authd` `use_password`).
5. Pin the Wazuh packages (`apt-mark hold`).
6. Verify: ports 443, 1514, 1515 and 55000 respond.

### 5. Linux endpoint (`40-linux-agents.yml`)
1. `auditd` role: install `auditd`, `audispd-plugins`, deploy a curated `audit.rules` (execve + targeted watches), and run `augenrules --load`.
2. `wazuh_agent_linux` role: add the Wazuh apt repo, install the agent pinned to the manager's version, and set `WAZUH_MANAGER`, `WAZUH_AGENT_NAME`, `WAZUH_REGISTRATION_PASSWORD`. Add `<localfile>` for `/var/log/audit/audit.log` (format `audit`) and start the service.
3. Enrollment check: poll `GET /agents?name=ubuntu-ep` on the manager API until the agent is `active`. Optionally confirm that a harmless command's audit event reaches the indexer.

### 6. Baseline snapshots (`50-snapshot.yml`)
Shut down cleanly, then `virsh snapshot-create-as <vm> baseline`. `99-destroy.yml` tears down domains, volumes and the network (with an explicit confirmation prompt).

### 7. Egress firewall (`60-egress-firewall.yml`, **host sudo, ask first**)
Required before any attack tooling runs in a VM (CLAUDE.md rule 1).
- Guests → internet: allowed.
- Guests → RFC1918 ranges outside 10.10.10.0/24 (home LAN): blocked.
- Guests → host (10.10.10.1): only DHCP and DNS allowed.
- Host → guests (SSH, dashboard 443, API 55000): allowed.
- To be done with firewalld policy objects on the `libvirt` zone. The exact mechanism gets confirmed against Fedora's current libvirt/firewalld behavior during implementation.
- Verified from inside `ubuntu-ep`: internet reachable, LAN gateway and host SSH unreachable.

## Order of work
1. Scaffold: `ansible.cfg`, inventory, `.gitignore`, `docs/host-setup.md`.
2. Phase 0 (you), then phases 1 → 3 and verify both VMs boot.
3. Phase 4, verify the dashboard is reachable from the host.
4. Phase 5, verify the agent is active and audit events are visible.
5. Phases 6 and 7.
