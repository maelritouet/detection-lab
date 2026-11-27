# Host setup (phase 0)

One-time setup of the Fedora host. **Every command marked `sudo` is for you to run yourself**, in your own terminal (CLAUDE.md rule 3). Nothing else in this repo needs root on the host, except the egress firewall later (phase 7).

## 1. Install virtualization tools

```bash
sudo dnf install @virtualization python3-libvirt python3-lxml xorriso
```

| Package | Why |
|---|---|
| `@virtualization` | QEMU/KVM, libvirt daemons, `virsh`, `virt-install`, `qemu-img`, `virt-manager` (handy for the Windows console later) |
| `python3-libvirt` | Python bindings used by the `community.libvirt` Ansible collection |
| `python3-lxml` | XML handling for `community.libvirt.virt_net` |
| `xorriso` | builds the cloud-init seed ISO |

## 2. Enable the libvirt daemons

Fedora uses modular libvirt daemons, which start on demand via sockets. This is usually already enabled after step 1, and running it again is harmless:

```bash
sudo systemctl enable --now virtqemud.socket virtnetworkd.socket virtstoraged.socket \
  virtnodedevd.socket virtnwfilterd.socket virtsecretd.socket
```

## 3. Let your user manage libvirt without sudo or password prompts

Required. Without it, polkit still lets `wheel` members in, but **asks for the admin password on every libvirt connection** (each `virsh` call and each Ansible task). The only passwordless rule (`/usr/share/polkit-1/rules.d/50-libvirt.rules`) is for the `libvirt` group.

```bash
sudo usermod -aG libvirt "$USER"
```

Then **log out and back in**. A new terminal tab isn't enough, and VS Code must be restarted too, because group membership is only read at login.

> **Trade-off:** members of `libvirt` can control `qemu:///system`, which can attach host files and devices to VMs. That's effectively root on the host. It's the standard setup for a single-user lab machine, and it's what lets every playbook after this step run without sudo.

## 4. Verify (no sudo)

```bash
id -nG | tr ' ' '\n' | grep -x libvirt          # prints "libvirt" (if not, you haven't logged out/in yet)
virsh -c qemu:///system version                  # prints library + hypervisor versions
virt-host-validate qemu                          # every line should be PASS (a WARN about IOMMU is fine)
```

## 5. Ansible (no sudo, everything stays in the repo)

From the repo root:

```bash
make preflight
```

This creates `.venv/` (with `--system-site-packages`, so it picks up `python3-libvirt`), installs `ansible-core` without writing a pip cache in `$HOME`, installs the Ansible collections into `./collections`, and then runs the read-only preflight checks.
