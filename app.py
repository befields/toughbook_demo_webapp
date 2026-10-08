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
# Registry host:port that serves the bootc-flightgear images (the tablet).
REGISTRY_HOST = os.environ.get("REGISTRY_HOST", "192.168.8.100:5000")
# Repo path inside the registry.
IMAGE_REPO = os.environ.get("IMAGE_REPO", "bootc-flightgear")
# Ansible inventory + playbook locations (relative to this file by default).
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
INVENTORY = os.environ.get("INVENTORY", os.path.join(BASE_DIR, "inventory.ini"))
PLAYBOOK_DIR = os.path.join(BASE_DIR, "playbooks")
# Which playbooks to run. For a laptop/VM rehearsal with no bootc target, set
# SWITCH_PLAYBOOK=mock-switch.yml and REBOOT_PLAYBOOK=mock-reboot.yml for a full
# green run. Leave unset for the real booth demo.
SWITCH_PLAYBOOK = os.environ.get("SWITCH_PLAYBOOK", "switch-image.yml")
REBOOT_PLAYBOOK = os.environ.get("REBOOT_PLAYBOOK", "reboot.yml")

# Allow-list of workload tags. These match the buttons in templates/index.html.
# Edit this one list (or set WORKLOADS="f22,b52,f35,..." in the environment)
# to add/remove workloads — nothing else in the app needs to change.
_default_workloads = "f22,b52,f35,f35-fixed,base"
WORKLOADS = [
    w.strip() for w in os.environ.get("WORKLOADS", _default_workloads).split(",") if w.strip()
]


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
    # Defaults to every host in the inventory (both toughbooks).
    cmd = [
        "ansible-playbook",
        "-i", INVENTORY,
        os.path.join(PLAYBOOK_DIR, playbook),
    ]
    if extra_args:
        cmd.extend(extra_args)

    app.logger.info("Running: %s", shlex.join(cmd))
    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=290,  # stay under the nginx 300s proxy timeout
        )
    except subprocess.TimeoutExpired:
        return False, "Playbook timed out after 290s (check the target and network)."
    except FileNotFoundError:
        return False, "ansible-playbook not found. Is the venv active / PATH correct?"

    output = (result.stdout or "") + (result.stderr or "")
    # returncode 0 == success. Anything else is a real failure the UI must see.
    return result.returncode == 0, output.strip()


@app.route("/")
def home():
    return render_template("index.html", workloads=WORKLOADS, targets=TARGET_IPS)


@app.route("/workload/<workload>", methods=["POST"])
def execute_workload(workload):
    if workload not in WORKLOADS:
        return (
            jsonify(ok=False,
                    output=f"Rejected unknown workload '{workload}'. "
                           f"Allowed: {', '.join(WORKLOADS)}"),
            400,
        )
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


@app.route("/healthz")
def healthz():
    return jsonify(ok=True, targets=TARGET_IPS, registry=REGISTRY_HOST,
                   workloads=WORKLOADS)


if __name__ == "__main__":
    # Dev only. In the booth this is served by gunicorn via systemd (debug OFF).
    app.run(host="127.0.0.1", port=8000, debug=False)
