# detection-lab

KVM/libvirt detection engineering lab: Wazuh all-in-one server, an Ubuntu 24.04 endpoint with auditd, and (later) a Windows 11 endpoint with Sysmon, all on `10.10.10.0/24`.

- Plan and decisions: [docs/PLAN.md](docs/PLAN.md)
- One-time host setup (sudo, done by hand): [docs/host-setup.md](docs/host-setup.md)
- Ground rules: [CLAUDE.md](CLAUDE.md)

## Quick start

```bash
make preflight   # venv + collections + read-only host checks
```

More targets arrive as each phase is implemented: `make help`.
