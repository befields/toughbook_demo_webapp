import os
import shlex
import subprocess

from flask import Flask, jsonify, render_template, request

app = Flask(__name__)

# --- Configuration (override with environment variables, no code edits) ---
# The Toughbook target(s) on the booth LAN. Comma-separated for multiple units.
# (TARGET_IP, singular, is still accepted as a fallback.)
_targets = os.environ.get("TARGET_IPS") or os.environ.get("TARGET_IP", "192.168.8.101,192.168.8.102")
TARGET_IPS = [t.strip() for t in _targets.split(",") if t.strip()]
# Registry host:port that serves the bootc mission images (the tablet).
REGISTRY_HOST = os.environ.get("REGISTRY_HOST", "192.168.8.100:5000")
# Repo path inside the registry.
IMAGE_REPO = os.environ.get("IMAGE_REPO", "bootc-flightgear")
# Ansible inventory + playbook locations (relative to this file by default).
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
INVENTORY = os.environ.get("INVENTORY", os.path.join(BASE_DIR, "inventory.ini"))
PLAYBOOK_DIR = os.path.join(BASE_DIR, "playbooks")

# MOCK_MODE=true runs labeled rehearsal playbooks that log in to the target for
# real but do NOT switch images, reboot, or start containers. For laptop/VM tests.
MOCK = os.environ.get("MOCK_MODE", "").lower() in ("1", "true", "yes")
SWITCH_PLAYBOOK = os.environ.get("SWITCH_PLAYBOOK", "mock-switch.yml" if MOCK else "switch-image.yml")
REBOOT_PLAYBOOK = os.environ.get("REBOOT_PLAYBOOK", "mock-reboot.yml" if MOCK else "reboot.yml")
OKP_DEPLOY_PLAYBOOK = os.environ.get("OKP_DEPLOY_PLAYBOOK", "mock-okp.yml" if MOCK else "okp-deploy.yml")
OKP_REMOVE_PLAYBOOK = os.environ.get("OKP_REMOVE_PLAYBOOK", "mock-okp.yml" if MOCK else "okp-remove.yml")
# Offline Knowledge Portal image as the Toughbooks see it (pre-staged or in the tablet registry).
OKP_IMAGE = os.environ.get("OKP_IMAGE", f"{REGISTRY_HOST}/rhokp-rhel9:latest")
OKP_PORT = os.environ.get("OKP_PORT", "8090")
# The access key is read from OKP_ACCESS_KEY by the playbook itself (never put on a command line).
OKP_ENABLED = bool(os.environ.get("OKP_ACCESS_KEY")) or MOCK

# Mission catalog. "id" is the image tag in the registry. Only ids listed in
# WORKLOADS are shown and allowed (allow-list).
CATALOG = [
    {"id": "cop", "label": "Tactical COP", "desc": "Common operating picture — friendly/OPFOR tracks, MGRS grid, graphics", "icon": "map", "version": "COP v1.3"},
    {"id": "cuas", "label": "Counter-UAS", "desc": "Air picture — radar scope, drone tracks, AI classification, defeat status", "icon": "radar", "version": "C-UAS v2.4"},
    {"id": "isr", "label": "ISR · Edge AI", "desc": "Drone full-motion video with on-device object detection", "icon": "eye", "version": "ISR v1.8"},
    {"id": "netops", "label": "Network Ops", "desc": "Tactical mesh, SATCOM reachback, disconnected (DDIL) operations", "icon": "net", "version": "NETOPS v3.1"},
    {"id": "sustain", "label": "Sustainment", "desc": "LOGSTAT by unit, days of supply, convoy tracker", "icon": "box", "version": "LOG v2.2"},
    {"id": "cop-degraded", "label": "COP v1.2 (faulty)", "desc": "Bad build: stale data feed & broken map — show rollback/fix", "icon": "warn", "version": "COP v1.2", "fault": True},
    {"id": "home", "label": "Standby", "desc": "Known-good base screen — device awaiting mission", "icon": "home", "version": "BASE v1.0"},
    # FlightGear images (built from the flightgear-kiosk-demo repo, same registry repo)
    {"id": "f22", "label": "F-22 Flight Sim", "desc": "FlightGear F-22 scenario — full 3D flight simulator workload", "icon": "jet", "version": "FLIGHTGEAR"},
    {"id": "b52", "label": "B-52 Flight Sim", "desc": "FlightGear B-52 scenario — full 3D flight simulator workload", "icon": "jet", "version": "FLIGHTGEAR"},
    {"id": "f35", "label": "F-35 (faulty)", "desc": "Bad build of the F-35 scenario — show rollback/fix", "icon": "jet", "version": "FLIGHTGEAR", "fault": True},
    {"id": "f35-fixed", "label": "F-35 (fixed)", "desc": "Corrected F-35 scenario — the fix for the faulty build", "icon": "jet", "version": "FLIGHTGEAR"},
    {"id": "base", "label": "Kiosk Base", "desc": "Original kiosk base image the Toughbooks were installed from", "icon": "home", "version": "BASE"},
]
# Default buttons = TACEDGE set. Use deploy/use-demo.sh (or WORKLOADS=...) for FlightGear or both.
_default_workloads = "cop,cuas,isr,netops,sustain,cop-degraded,home"
WORKLOADS = [w.strip() for w in os.environ.get("WORKLOADS", _default_workloads).split(",") if w.strip()]
_known = {c["id"]: c for c in CATALOG}
VISIBLE = [_known.get(w, {"id": w, "label": w.upper(), "desc": "Custom image", "icon": "box", "version": w}) for w in WORKLOADS]


def _resolve_target():
    """Read the optional 'target' field: 'all' (default) or one target IP.
    Returns (limit_args, label) or (None, None) if the target is invalid."""
    target = (request.form.get("target") or "all").strip()
    if target == "all":
        return [], "all targets"
    if target in TARGET_IPS:
        return ["--limit", target], target
    return None, None


def _run_playbook(playbook, extra_args=None):
    """Run an Ansible playbook and return (ok, combined_output)."""
    cmd = ["ansible-playbook", "-i", INVENTORY, os.path.join(PLAYBOOK_DIR, playbook)]
    if extra_args:
        cmd.extend(extra_args)
    app.logger.info("Running: %s", shlex.join(cmd))
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=290)  # under the 300s proxy timeout
    except subprocess.TimeoutExpired:
        return False, "Playbook timed out after 290s (check the target and network)."
    except FileNotFoundError:
        return False, "ansible-playbook not found. Is the venv active / PATH correct?"
    output = ((result.stdout or "") + (result.stderr or "")).strip()
    return result.returncode == 0, output


@app.route("/")
def home():
    return render_template("index.html", catalog=VISIBLE, targets=TARGET_IPS, okp=OKP_ENABLED, mock=MOCK)


@app.route("/workload/<workload>", methods=["POST"])
def execute_workload(workload):
    if workload not in WORKLOADS:
        return jsonify(ok=False, output=f"Rejected unknown workload '{workload}'. Allowed: {', '.join(WORKLOADS)}"), 400
    limit_args, label = _resolve_target()
    if limit_args is None:
        return jsonify(ok=False, output="Rejected unknown target."), 400
    image_tag = f"{REGISTRY_HOST}/{IMAGE_REPO}:{workload}"
    ok, output = _run_playbook(
        SWITCH_PLAYBOOK,
        ["--extra-vars", f"bootc_image_tag={workload} target_image={image_tag}"] + limit_args,
    )
    return jsonify(ok=ok, output=f"[{label}] {output}"), (200 if ok else 500)


@app.route("/reboot", methods=["POST"])
def reboot_system():
    limit_args, label = _resolve_target()
    if limit_args is None:
        return jsonify(ok=False, output="Rejected unknown target."), 400
    ok, output = _run_playbook(REBOOT_PLAYBOOK, limit_args)
    return jsonify(ok=ok, output=f"[{label}] {output}"), (200 if ok else 500)


@app.route("/app/okp/<action>", methods=["POST"])
def okp(action):
    """Deploy or remove the Red Hat Offline Knowledge Portal container on the Toughbook(s).
    No reboot: this is an application container on top of the image-mode OS."""
    if action not in ("deploy", "remove"):
        return jsonify(ok=False, output="Unknown action."), 400
    if not OKP_ENABLED:
        return jsonify(ok=False, output="OKP_ACCESS_KEY is not set on the controller — Field Docs disabled."), 400
    limit_args, label = _resolve_target()
    if limit_args is None:
        return jsonify(ok=False, output="Rejected unknown target."), 400
    pb = OKP_DEPLOY_PLAYBOOK if action == "deploy" else OKP_REMOVE_PLAYBOOK
    ok, output = _run_playbook(pb, ["--extra-vars", f"okp_image={OKP_IMAGE} okp_port={OKP_PORT} okp_action={action}"] + limit_args)
    return jsonify(ok=ok, output=f"[{label}] {output}"), (200 if ok else 500)


@app.route("/healthz")
def healthz():
    return jsonify(ok=True, targets=TARGET_IPS, registry=REGISTRY_HOST, workloads=WORKLOADS, okp=OKP_ENABLED, mock=MOCK)


if __name__ == "__main__":
    # Dev only. In the booth this is served by gunicorn (debug OFF).
    app.run(host="127.0.0.1", port=8000, debug=False)
