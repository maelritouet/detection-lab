# Detection Lab

Detection engineering lab on a Fedora host with KVM/libvirt:

- Wazuh all-in-one server (Ubuntu 24.04)
- Linux endpoint (Ubuntu 24.04) with auditd + Wazuh agent
- Windows 11 endpoint with Sysmon + Wazuh agent

All guests sit on one libvirt NAT network, `10.10.10.0/24`. Linux VMs are built and configured with Ansible from this repo.

## Hard rules

These are not negotiable. If a task can't be done within them, stop and ask.

### 1. Attack tooling never runs on the host

- Never download, store, build, or execute attack tooling on the Fedora host. This covers Atomic Red Team, Caldera agents, Mimikatz, Impacket, Metasploit, C2 implants, malware samples, payload generators, and similar tools.
- Never run scanners or attack traffic (nmap, masscan, brute-forcers, etc.) from the host against the lab network or anything else.
- Attack tooling is fetched and run **only inside lab VMs**, by a command executed in the VM (e.g. over SSH/WinRM), never by staging it on the host first.
- The repo may hold detection content (Wazuh rules, decoders, Sysmon/auditd configs) and *references* to tests (IDs, links, descriptions). It must not hold attack binaries or payloads.
- No attack tooling runs in any VM until the host egress firewall is in place (guests blocked from the host and the LAN; see `docs/PLAN.md`, phase 7). If you can't confirm it's active, stop and ask.

### 2. Never edit anything outside this repo

- Only create, modify, or delete files under this repository directory.
- That includes dotfiles and tool state in `$HOME`, so configure tools to keep their state in the repo:
  - Ansible: `collections_path`, `local_tmp`, and SSH `UserKnownHostsFile` point into the repo (via `ansible.cfg`).
  - SSH keys for the lab are generated inside the repo (gitignored), not in `~/.ssh`.
  - Downloads (cloud images, installers) go to a gitignored directory in the repo.
- Never touch `/etc`, `/var`, `/usr`, `~/.config`, `~/.ssh`, `~/.ansible`, etc. directly. If something seems to require it, stop and ask.
- Temporary files go in a gitignored `tmp/` inside the repo.
**One exception: libvirt objects.** This repo's playbooks may create, change, and delete libvirt networks, storage volumes, domains, and snapshots on `qemu:///system`, as long as they go **through the libvirt API** (`virsh`, `virt-install`, `community.libvirt`). Disks live in libvirt's default pool (`/var/lib/libvirt/images`). Never write, copy, or chmod files in that directory directly. Use `virsh vol-upload` / `vol-create-as` instead.

### 3. Ask before any command that uses sudo on the host

- Before running any command that elevates privileges **on the Fedora host**, stop and ask for explicit approval. This covers `sudo`, `su`, `pkexec`, `run0`, `doas`, and Ansible `become` on any task that runs on the host (`hosts: localhost`, `connection: local`, `delegate_to: localhost`).
- Privilege escalation **inside lab VMs** (e.g. Ansible `become: true` on `wazuh-server` or `ubuntu-ep`) doesn't need approval. Those VMs are disposable and snapshotted.
- Never put `become: true` at play level in a play that also has host-side tasks. Keep host and guest plays separate so a VM-only `become` can't reach the host.
- When asking, give the exact command, what it changes, and why it's needed.
- One approval covers one command. Don't batch extra privileged steps into an approved command, and don't reuse an earlier approval.
- Never write wrappers, aliases, sudoers entries, or scripts that hide or skip this prompt.

## Conventions

- Secrets (Wazuh admin password, agent enrollment password) live in Ansible Vault or gitignored files, never in plaintext in tracked files.
- Pin versions (Wazuh, Ubuntu image) in inventory vars. Don't use "latest".
- Playbooks must be idempotent: a second run should report no changes.
