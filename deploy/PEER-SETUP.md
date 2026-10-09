# Booth Setup — TACEDGE Mission Controller (Quick Start)

Follow these steps **in order, on the tablet**. Each step says what to run and
what you should see. If a step doesn't look right, stop and call Benny.

**What this demo is:** the tablet is the *mission controller*. Tapping a mission
switches the Toughbooks to a different **bootc (RHEL image mode) image** and
reboots them into it — Tactical COP, Counter-UAS, ISR, Network Ops,
Sustainment, a deliberately *faulty* COP build (to show rollback), and a
Standby screen. A second button type deploys **Red Hat Offline Knowledge
Portal** as a container on the Toughbooks — no reboot.

---

## Before you start — confirm these are true

- [ ] **Tablet** is RHEL, on the travel-router network as **192.168.8.100**, with the local registry running on port **5000**.
- [ ] **Toughbooks** are on as **192.168.8.101** and **192.168.8.102**, installed from the kiosk **base** image (`192.168.8.100:5000/bootc-flightgear:base` — the same base the FlightGear demo used).
- [ ] You have **internet for first-time setup** (hotel Wi-Fi is fine; not needed at the booth afterward).
- [ ] You have from Benny: `rhokp.tar` (Offline Knowledge Portal image) and the **OKP access key** (sent privately).

---

## Step 1 — Get the files

    git clone https://github.com/befields/toughbook_demo_webapp.git
    cd toughbook_demo_webapp

## Step 2 — Get the controller app image  (pick ONE)

**A) Build it** (needs internet): `./deploy/build-image.sh` — wait for `Done`.

**B) Benny's prebuilt file**: `podman load -i workload-selector.tar`

Check: `podman images | grep workload-selector` shows one line.

## Step 3 — Build the mission images and push them to the registry

    ./missions/build-missions.sh

This builds 7 small images on top of the `base` image and pushes them to
`192.168.8.100:5000/bootc-flightgear`. Each is only a few MB on top of base, so it's quick.

Check:

    curl -s http://192.168.8.100:5000/v2/bootc-flightgear/tags/list

You should see `cop`, `cuas`, `isr`, `netops`, `sustain`, `cop-degraded`, `home` (plus `base`).

> If the `base` image is missing, see `missions/Containerfile.base` (needs a subscribed RHEL host to build).

## Step 4 — Put the Field Docs image in the registry

    podman load -i rhokp.tar
    podman tag registry.redhat.io/offline-knowledge-portal/rhokp-rhel9:latest 192.168.8.100:5000/rhokp-rhel9:latest
    podman push --tls-verify=false 192.168.8.100:5000/rhokp-rhel9:latest

## Step 5 — Store the access key as a secret (one time only)

Benny sends you the Offline Knowledge Portal access key privately (Signal, in person — never on the shared drive).
You store it **once** in podman's secret store on the tablet. After this, nobody ever types it again.

Run this, then **paste the key and press Enter** (nothing shows on screen — that's on purpose):

    read -rs K && printf '%s' "$K" | podman secret create okp_key - && unset K

Check it's stored (you'll see the name, never the key):

    podman secret ls

You should see a line with `okp_key`.

> Made a mistake? `podman secret rm okp_key` and run the command again.

## Step 5b — Start the controller

    podman run -d --name ws --network host \
      -e TARGET_IPS=192.168.8.101,192.168.8.102 \
      -e TARGET_SSH_USER=core -e TARGET_SSH_PASS=edge -e TARGET_BECOME_PASS=edge \
      -e REGISTRY_HOST=192.168.8.100:5000 \
      --secret okp_key,type=env,target=OKP_ACCESS_KEY \
      -e PORT=8080 \
      localhost/workload-selector:latest

The `--secret` line hands the key to the controller at startup. It is not in the
image, not in git, and not in the command you typed.

Check: `podman ps` shows `ws` as `Up`, and

    curl -s http://localhost:8080/healthz

shows `"okp":true` (that means Field Docs is enabled).

> Redo it? `podman rm -f ws` first, then re-run Step 5b. The secret stays — you don't redo Step 5.

## Step 6 — Pre-load Field Docs onto the Toughbooks (do this the night before)

The portal image is ~9.5 GB — copy it to both Toughbooks ahead of time so the live tap is fast:

    podman exec ws ansible-playbook -i /app/inventory.ini /app/playbooks/okp-prestage.yml

Takes a while per device. Let it finish.

## Step 7 — GO / NO-GO check

    WEB_URL=http://localhost:8080/healthz ./deploy/preflight.sh

You want **`>> GO`**. A **[FAIL]** line tells you what's wrong. **[SKIP]** on the Ansible line is fine.

## Step 8 — Kiosk mode on the tablet

    ./deploy/kiosk-setup.sh

Then open Firefox to **http://localhost:8080/**.

---

## Running the demo

1. **Pick a target** at the top: ALL UNITS, UNIT 1 or UNIT 2.
2. **Tap a mission card.** A panel shows *Switch image → Reboot → Mission online*. The Toughbook reboots into that mission (about 1–2 minutes).
3. **Rollback story:** tap **COP v1.2 (faulty)** — the Toughbook comes up with a stale-data/broken-map COP. Then tap **Tactical COP** — fixed, same device, one tap.
4. **Field Docs:** tap **DEPLOY** under Field Apps — no reboot. On the Toughbook, tap **DOCS** in the top bar to open Red Hat docs offline.

## How the Toughbooks get their images

You never touch the Toughbooks during the demo. When you tap a mission, the
controller (Ansible) logs in to each Toughbook and:

1. tells it to trust the tablet registry `192.168.8.100:5000` (plain HTTP on the booth LAN),
2. runs **`bootc switch 192.168.8.100:5000/bootc-flightgear:<mission>`** — the Toughbook pulls only the small layers it doesn't already have,
3. reboots it into the new image.

## Manual control on a Toughbook (backup if the tablet is down)

Open a terminal on the Toughbook (or `ssh core@192.168.8.101`, password `edge`).

See what's running and what's staged:

    sudo bootc status

Switch to a mission by hand (example: Counter-UAS), then reboot:

    sudo bootc switch 192.168.8.100:5000/bootc-flightgear:cuas
    sudo systemctl reboot

Go back to the previous image (instant rollback), then reboot:

    sudo bootc rollback
    sudo systemctl reboot

> If a manual `bootc switch` fails with *"server gave HTTP response to HTTPS client"*, the Toughbook doesn't trust the tablet registry yet. Tap any mission once from the controller (it installs the trust setting), or create `/etc/containers/registries.conf.d/999-tacedge-registry.conf` with `[[registry]]`, `location = "192.168.8.100:5000"`, `insecure = true`.

## If something breaks

- **Controller page won't load:** `podman restart ws`, refresh the browser.
- **See what it's doing:** `podman logs ws` — or tap **SHOW ANSIBLE OUTPUT** in the panel.
- **A mission failed:** the panel shows the real error and the Toughbook is NOT rebooted. Re-run preflight.
- **Field Docs buttons greyed out:** the controller didn't get the key. Check `podman secret ls` shows `okp_key`, then redo Step 5b.

## After the show — teardown (do this before anyone packs up)

The access key is tied to Benny's Red Hat account. Remove every copy:

1. On the controller, select **ALL UNITS** and tap **REMOVE** under Field Apps (stops the portal on both Toughbooks).
2. On the tablet, remove the controller:

        podman rm -f ws

3. On the tablet, delete the secret:

        podman secret rm okp_key

4. Confirm it's gone (no `okp_key` line):

        podman secret ls

5. Text Benny "teardown done".

The portal **image** can stay on the devices — it holds no key. If you also want the disk space back, on each Toughbook: `sudo podman rmi 192.168.8.100:5000/rhokp-rhel9:latest`.

*Deeper reference (host install, auto-start on boot, VM rehearsal) is in `DEPLOY.md`.*
