# Control-plane container for the Toughbook Workload Selector demo.
# Build on your Fedora laptop (online), then `podman save` the result and
# drop it on the shared drive for your peer to `podman load` at the booth.
#
# Contains: Flask app + gunicorn + ansible-core + community.general + ssh.
# Does NOT contain: credentials (rendered from env at runtime) or the big
# bootc workload images (those live in your peer's registry).
FROM registry.access.redhat.com/ubi9/ubi:latest

# sshpass comes from EPEL; the build host is online so this is fine.
RUN dnf -y install \
        python3 python3-pip openssh-clients \
        https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm \
    && dnf -y install sshpass \
    && dnf -y clean all

WORKDIR /app
COPY requirements.txt /app/requirements.txt
RUN pip3 install --no-cache-dir -r /app/requirements.txt ansible-core

# Ansible collection needed by playbooks/switch-image.yml at runtime.
RUN ansible-galaxy collection install community.general containers.podman

COPY app.py /app/app.py
COPY templates/ /app/templates/
COPY static/ /app/static/
COPY playbooks/ /app/playbooks/
COPY deploy/container/entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh

# Don't prompt on unknown target host keys (booth LAN, ephemeral targets).
ENV ANSIBLE_HOST_KEY_CHECKING=false \
    INVENTORY=/app/inventory.ini \
    PORT=80

EXPOSE 80
ENTRYPOINT ["/app/entrypoint.sh"]
