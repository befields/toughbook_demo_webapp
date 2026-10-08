# Booth Setup — Toughbook Workload Selector (Quick Start)

Follow these steps **in order, on the tablet**. Each step says what to run and
what you should see. If a step doesn't look right, stop and call Benny.

---

## Before you start — confirm these are true (ask Benny if unsure)

- [ ] The **tablet** is a RHEL machine, powered on, on the travel-router network as **192.168.8.100**.
- [ ] The **two Toughbooks** are powered on as **192.168.8.101** and **192.168.8.102**, are bootc (image-mode) systems, and are allowed to pull images from **192.168.8.100:5000**.
- [ ] The **FlightGear images are already in the registry** at `192.168.8.100:5000`, named `bootc-flightgear`, with tags `f22`, `b52`, `f35`, `f35-fixed`, `base`.
- [ ] You have **internet for first-time setup** (hotel Wi-Fi is fine — you do NOT need internet at the booth afterward).

If any of these aren't true, the demo won't switch images. Check with Benny before continuing.

---

## Step 1 — Get the files

Open a terminal on the tablet and run:

    git clone https://github.com/befields/toughbook_demo_webapp.git
    cd toughbook_demo_webapp

---

## Step 2 — Get the app image  (pick ONE of A or B)

**A) Build it yourself** (needs internet, takes a few minutes):

    ./deploy/build-image.sh

Wait until it prints `Done`.

**B) Use Benny's prebuilt file** (no internet needed): copy `workload-selector.tar`
onto the tablet, then:

    podman load -i workload-selector.tar

**Check it worked** (either way):

    podman images | grep workload-selector

You should see one line listing `workload-selector`.

---

## Step 3 — Start the app

    podman run -d --name ws --network host \
      -e TARGET_IPS=192.168.8.101,192.168.8.102 \
      -e TARGET_SSH_USER=core -e TARGET_SSH_PASS=edge -e TARGET_BECOME_PASS=edge \
      -e REGISTRY_HOST=192.168.8.100:5000 \
      -e WORKLOADS=f22,b52,f35,f35-fixed,base \
      -e PORT=8080 \
      localhost/workload-selector:latest

**Check it's running:**

    podman ps

You should see a line for `ws` that says `Up`.

> Changed any addresses/passwords? Edit the `-e` lines above before running.
> Already ran it once and need to redo it? `podman rm -f ws` first, then re-run.

---

## Step 4 — Check everything is ready (GO / NO-GO)

    WEB_URL=http://localhost:8080/healthz ./deploy/preflight.sh

You want to see **`>> GO`** at the bottom.

- If a line says **[FAIL]**, it tells you what's wrong (network, registry images, or login). Fix that or call Benny.
- If the Ansible line says **[SKIP]**, that's fine here — it just means Ansible isn't installed on the tablet directly (it lives inside the app). The real test is Step 6.

---

## Step 5 — Put the tablet in kiosk mode (full screen, no sleep)

    ./deploy/kiosk-setup.sh

Then open Firefox to:

    http://localhost:8080/

You'll see the **Workload Selector** screen with the workload buttons and a
**Both / Unit 1 / Unit 2** selector at the top.

---

## Step 6 — Test the demo (do this once before a customer is watching)

On the screen: pick **Both** (or a single unit), then tap a workload like **F22**.

- The black box shows progress.
- The selected Toughbook(s) switch to that image and reboot.
- Give it a minute to come back on the new workload.

If that works, you're demo-ready.

---

## If something breaks

- **Page won't load:** `podman restart ws`  (then refresh the browser)
- **See what the app is doing:** `podman logs ws`
- **Re-check readiness:** `WEB_URL=http://localhost:8080/healthz ./deploy/preflight.sh`
- **A button failed:** the black box shows the real error, and the Toughbook is NOT rebooted. Re-run preflight — it points at the broken piece. Call Benny if stuck.

---

*Deeper reference (options, auto-start on boot, the host-install alternative) is in `DEPLOY.md`. You don't need it for a standard booth setup.*
