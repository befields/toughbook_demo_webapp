# Toughbook Demo Web Application

A touchscreen "Workload Selector" for the FlightGear bootc kiosk demo. Buttons
on a tablet trigger Ansible playbooks that switch a Panasonic Toughbook to a
different bootc image (F22 / B52 / F35 / base) and reboot it. Companion to
[flightgear-kiosk-demo](https://github.com/rlucente-se-jboss/flightgear-kiosk-demo).

## How it works

The RHEL **tablet** is the control plane: it serves this Flask app and runs
Ansible, which SSHes to the **Toughbook target** and runs
`community.general.bootc_manage` to switch its image. Images are served from a
**registry** (on the tablet or a peer's box). Everything runs on a private
**travel-router LAN** with static IPs; the tablet shows the UI full-screen.

## Deploying

**New to this? Start with [`deploy/PEER-SETUP.md`](deploy/PEER-SETUP.md)** — a plain, step-by-step booth guide for the person setting up the tablet.

Full reference (options, host install, auto-start): [`deploy/DEPLOY.md`](deploy/DEPLOY.md).

Two supported paths:

- **Container image (primary)** — build on a laptop with `./deploy/build-image.sh`,
  ship the tarball on a shared drive, `podman load` + run on the tablet. Nothing
  to install at the venue.
- **Host install (fallback)** — `./deploy/bootstrap.sh` then
  `sudo ansible-playbook deploy/site.yml` on the tablet.

Both finish with `./deploy/kiosk-setup.sh` (full-screen + no sleep) and
`./deploy/preflight.sh` (GO / NO-GO check).

## Configuration

All knobs are environment variables / `deploy/vars.yml` — no code edits:

| Setting | Default | Meaning |
|---|---|---|
| `TARGET_IPS` | `192.168.8.101,192.168.8.102` | Toughbook(s) being re-imaged (comma-separated) |
| `REGISTRY_HOST` | `192.168.8.100:5000` | registry serving the images (on the tablet) |
| `IMAGE_REPO` | `bootc-flightgear` | image repo name |
| `WORKLOADS` | `cop,cuas,isr,netops,sustain,cop-degraded,home` | which mission buttons show (allow-list); unknown tags get a generic card |
| `MOCK_MODE` | `false` | `true` = rehearsal playbooks (log in, but no switch/reboot/containers) |
| `OKP_ACCESS_KEY` | — | enables the Field Docs (Offline Knowledge Portal) buttons |
| `TARGET_SSH_USER` / `TARGET_SSH_PASS` / `TARGET_BECOME_PASS` | `core` / `edge` / `edge` | target login (rendered into `inventory.ini`, never committed) |

## Notes for this fork (booth hardening, Oct 2026)

Changes from the original so it survives a live booth:
- Workload input is validated against the `WORKLOADS` allow-list.
- Playbook failures now surface in the UI (HTTP 500 + real output) instead of
  reporting a fake "success"; the target is not rebooted on a failed switch.
- Flask debug mode off; served by gunicorn.
- All IPs/creds are config, not hardcoded source. Credentials are rendered at
  deploy time and git-ignored (`inventory.ini`).
- One-shot container build and host deploy, plus kiosk and preflight scripts.

## Troubleshooting

- **502 / blank page** — the app container/service isn't up, or nginx can't
  reach gunicorn. On a host install, confirm the SELinux boolean:
  `sudo setsebool -P httpd_can_network_connect on`.
- **Button fails immediately** — run `./deploy/preflight.sh`; it names the
  broken link (LAN, registry, or SSH login).
- **"no tags" from preflight** — the registry is up but your peer hasn't pushed
  the workload images yet.
- **Logs** — container: `podman logs workload-selector`; host:
  `journalctl -u workload-selector -f`.

## License

MIT.
