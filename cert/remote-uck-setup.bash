set -eux

if [[ $SHELL != '/bin/bash' ]]; then
    echo "wrong shell, expected /bin/bash, got $SHELL"
    exit 1
fi

# Do a lazy check to try to prevent accidentally runs on a non-cloud key device
if ! [[ -d /usr/lib/unifi ]]; then
    echo 'this script should only be run on the cloud key'
    exit 1
fi

if (( $# != 2 )); then
    echo "didn't get expected AWS key"
    exit 1
fi

if [[ -x ~/.acme.sh/acme.sh ]]; then
    echo 'existing acme.sh installation found, upgrading'
    ~/.acme.sh/acme.sh --upgrade
else
    echo 'installing acme.sh'
    # Subshell to automatically pop cd and rm working dir
    (
    # Make a working dir
    tmpdir=$(mktemp -d)
    trap "rm -rf $tmpdir" EXIT
    cd $tmpdir

    # Get acme.sh
    curl --silent \
        --location \
        'https://github.com/acmesh-official/acme.sh/archive/master.tar.gz' | \
        tar -xz

    cd acme.sh-master

    # Run installer
    ./acme.sh \
        --debug 3 \
        --install \
        --nocron \
        --noprofile \
        --auto-upgrade
    )
fi

# Create the prehook file
cat <<'EOF' >~/.acme.sh/prehook.bash
#!/bin/bash

set -eux

mkdir -p ~/.acme.sh/backups
cd ~/.acme.sh/backups

tar -zcvf ~/.acme.sh/backups/tls-backup-$(date --iso-8601=seconds).tgz \
    /data/unifi-core/config/unifi-core.crt \
    /data/unifi-core/config/unifi-core.key
EOF

# Create the reload file
cat <<'EOF' >~/.acme.sh/reload.bash
#!/bin/bash

set -eux

service unifi-core reload

cd ~/.acme.sh/backups

# If there are more than five backups, delete all but the most recent 5. Do this
# in the reload hook so that we don't delete backups on failed renewals.
rm -f $(ls -1 tls-backup-*.tgz | head -n -5)
EOF

chmod +x ~/.acme.sh/prehook.bash ~/.acme.sh/reload.bash

set +x
export AWS_ACCESS_KEY_ID="$1"
export AWS_SECRET_ACCESS_KEY="$2"
set -x

# Issue a cert. This won't actually do anything if the cert does not need
# renewal. It will always update the configuration, saving hooks, AWS creds,
# output filepaths, etc. Note there are strict rate limits on production cert
# generation. When testing this script, add `--staging` to the command below.
# Let's Encrypt's staging servers will be used indefinitely until you remove the
# `--staging` option and re-run the setup script.
~/.acme.sh/acme.sh \
    --issue \
    --dns dns_aws \
    --domain unifi.ravron.com \
    --pre-hook ~/.acme.sh/prehook.bash \
    --reloadcmd ~/.acme.sh/reload.bash \
    --fullchain-file /data/unifi-core/config/unifi-core.crt \
    --key-file /data/unifi-core/config/unifi-core.key \
    --accountemail 'ravron@posteo.net' || true

cat <<'EOF' >/etc/systemd/system/acme.service
[Unit]
Description=Renew Let's Encrypt certificates using acme.sh
After=network-online.target

[Service]
Type=oneshot
ExecStart=/root/.acme.sh/acme.sh --cron --home /root/.acme.sh
# acme.sh returns 2 when renewal is skipped (i.e. certs up to date)
SuccessExitStatus=0 2
EOF

# Stop and disable any existing timer
systemctl disable --now acme.timer || true

cat <<'EOF' >/etc/systemd/system/acme.timer
[Unit]
Description=Daily renewal of Let's Encrypt's certificates

[Timer]
OnCalendar=daily
RandomizedDelaySec=1h
Persistent=true

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable --now acme.timer
