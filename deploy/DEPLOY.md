# Booth Deployment Runbook — Toughbook Workload Selector

This is the operator guide for AUSA. It covers two ways to deploy, a VM test
you can run on a Fedora laptop beforehand, and a booth-day checklist.

**Architecture:** the RHEL **tablet** is the control plane — it serves the web
UI and runs Ansible, which SSHes to the **Toughbook target** and switches its
bootc image. The big workload images live in a **registry** (on the tablet, or
on your peer's box). Everything sits on your own **travel-router LAN** with
static IPs. The tablet browser runs full-screen against `http://localhost/`.

```
[ RHEL tablet ]  --http-->  you (kiosk browser)
     |  web UI + Ansible
     |  ssh + bootc switch
     v
[ Toughbook target ]  --pull image-->  [ registry :5000 ]
```

Default IPs (edit to match the booth): tablet `192.168.8.100` (web UI +
registry `:5000`), toughbook targets `192.168.8.101` and `192.168.8.102`.
A selected workload is applied to every target in the inventory.

---

## Option A — Container image (primary, offline-proof)

You bake the control app into one image on your Fedora laptop, ship it on the
shared drive, and your peer loads and runs it on the tablet. No `dnf`/`galaxy`
at the booth.

### 1. Build + save  (on your Fedora laptop, online)

```
./deploy/build-image.sh
```

Produces `workload-selector.tar`. Copy it to the shared drive.

### 2. Load  (peer, on the tablet)

```
podman load -i workload-selector.tar
```

### 3. Configure + run  (peer, on the tablet)

Edit `deploy/container/workload-selector.container` for the booth IPs and
creds, then install it as a system service (quadlet):

```
sudo cp deploy/container/workload-selector.container /etc/containers/systemd/
```
```
sudo systemctl daemon-reload
```
```
sudo systemctl start workload-selector
```

> Prefer a one-liner instead of the quadlet? This is equivalent:
> ```
> sudo podman run -d --name workload-selector --network host --restart always \
>   -e TARGET_IPS=192.168.8.101,192.168.8.102 -e TARGET_SSH_USER=core \
>   -e TARGET_SSH_PASS=edge -e TARGET_BECOME_PASS=edge \
>   -e REGISTRY_HOST=192.168.8.100:5000 -e OKP_ACCESS_KEY \
>   localhost/workload-selector:latest
> ```

### 4. Registry (only if the tablet hosts it)

If your peer's registry is on a different box, skip this and just point
`REGISTRY_HOST` at that box. To run the registry on the tablet:

```
sudo cp deploy/container/flightgear-registry.container /etc/containers/systemd/
```
```
sudo systemctl daemon-reload && sudo systemctl start flightgear-registry
```

Then your peer pushes the bootc workload images into `TABLET_IP:5000`.

---

## Option B — Host install (fallback)

No container; installs straight onto the tablet. More steps at the venue, so
do step 1 on hotel Wi-Fi the night before.

### 1. Bootstrap  (peer, on the tablet, online)

```
./deploy/bootstrap.sh
```

### 2. Configure

Edit `deploy/vars.yml` for the booth IPs, user, and creds.

### 3. Deploy

```
sudo ansible-playbook deploy/site.yml
```

This installs nginx + gunicorn + the systemd service, renders `inventory.ini`,
sets the SELinux boolean, opens the firewall, and (optionally) starts the
registry.

---

## Kiosk + preflight (both options)

Full-screen the browser and disable sleep (peer, on the tablet, in the GUI):

```
./deploy/kiosk-setup.sh
```

Then the **GO / NO-GO** check before any customer walks up:

```
./deploy/preflight.sh
```

It verifies: web app answering, registry up with images, target pinging, and
Ansible can actually log in. Green `>> GO` means demo-ready.

---

## Test on a Fedora laptop first (recommended this week)

You can prove the whole chain except the real bootc switch without the tablet:

1. **Control app** — build and run the container right on your Fedora laptop:
   ```
   ./deploy/build-image.sh
   ```
   ```
   podman load -i workload-selector.tar
   ```
   ```
   podman run -d --name ws --network host \
     -e TARGET_IP=<your-target-vm-ip> -e REGISTRY_HOST=127.0.0.1:5000 \
     localhost/workload-selector:latest
   ```
2. **Target** — spin a RHEL/Fedora VM (libvirt or your homelab) with sshd and a
   `core` / `edge` login to stand in for the Toughbook.
3. **Registry** — `podman run -d -p 5000:5000 registry:2`, then push any image
   tagged `bootc-flightgear:cop` so preflight's catalog check passes.
4. Run `./deploy/preflight.sh` and click the buttons at `http://localhost/`.

**For a full green run on a non-bootc target**, run the app with mock playbooks
— they log in for real (so SSH/creds/network are genuinely tested) but skip the
image swap and the reboot:
```
podman run -d --name ws --network host \
  -e TARGET_IP=<your-target-vm-ip> \
  -e MOCK_MODE=true \
  localhost/workload-selector:latest
```

What the laptop test proves: web UI, allow-list, Ansible login, reboot path,
kiosk, preflight. What it can't prove without your peer's images: the actual
`bootc` image swap — test that end-to-end with him and a real bootc target
(your homelab, if handy). The same mock toggle is a booth fallback if the
images aren't staged in time.

---

## Booth-day checklist

- [ ] Travel router up; tablet `.200` and target `.100` on static IPs
- [ ] `workload-selector` service running (`systemctl status workload-selector`)
- [ ] Registry reachable and holding the workload tags
- [ ] `./deploy/preflight.sh` shows `>> GO`
- [ ] Kiosk browser full-screen, tablet sleep disabled
- [ ] Known-good recovery image (`base`) confirmed working once

**If a workload button fails mid-demo:** the terminal area now shows the real
error and the target is NOT rebooted. Re-run `preflight.sh` — it will point at
the broken link (LAN, registry, or login).
