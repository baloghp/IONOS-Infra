# Ansible (IONOS)

Run commands from **this directory** so `ansible.cfg` is used:

```bash
cd ansible
ansible all -m ping
ansible-playbook playbooks/site.yml
```

Ansible uses the Tailscale SSH aliases as managed hosts:

```text
ts-ionos-backend
ts-ionos-frontend
ts-ionos-infra
```

The direct public-IP aliases `ionos-backend`, `ionos-frontend`, and `ionos-infra` remain manual backup access during bootstrap and are not used by the inventory.

WireGuard mesh (Phase 1 — after IONOS firewall allows UDP `51820`):

```bash
ansible-playbook playbooks/wireguard.yml
```

Host firewall / nftables (Phase 1 Step 1.6 — keep a Tailscale SSH session open):

```bash
ansible-playbook playbooks/firewall.yml
```

Frontend gateway (Phase 2 — requires SSL files in `files/frontend/ssl/`):

```bash
ansible-playbook playbooks/docker.yml --limit frontend
ansible-playbook playbooks/gateway.yml
ansible-playbook playbooks/firewall.yml --limit frontend
```

Validate all starter playbooks:

```bash
ansible-playbook --syntax-check playbooks/site.yml playbooks/hardening.yml playbooks/wireguard.yml playbooks/firewall.yml playbooks/docker.yml playbooks/gateway.yml playbooks/backend.yml playbooks/infra.yml playbooks/apps.yml playbooks/update-containers.yml
```

Current layout:

```text
ansible/
  ansible.cfg
  inventory/
    hosts.yml
    group_vars/all.yml
  host_vars/
  playbooks/
    site.yml
    hardening.yml
    wireguard.yml
    docker.yml
    gateway.yml
    backend.yml
    infra.yml
    apps.yml
    update-containers.yml
  roles/
    base/
    ssh/
    firewall/
    wireguard/
    docker/
    caddy/
    postgres/
    valkey/
    openbao/
    monitoring/
```

Background and layout: `Plan/01-ansible-intro.md`. Hosts: `Plan/IONOS Servers.md`.
