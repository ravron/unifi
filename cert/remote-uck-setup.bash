set -eux

if [[ $SHELL != '/bin/bash' ]]; then
    echo 'wrong shell'
    exit 1
fi

if [[ -d ~/.acme.sh ]]; then
    echo "~/.achme.sh already exists. delete before attempting to install again"
    # exit 1
fi

if (( $# != 2 )); then
    echo "didn't get expected AWS key"
    exit 1
fi

if [[ -x ~/.acme.sh/acme.sh ]]; then
    ~/.acme.sh/acme.sh --upgrade
else
    # Subshell to automatically pop cd and rm working dir
    (
    # Make a working dir
    tmpdir=$(mktemp -d)
    trap "rm -rf $tmpdir" EXIT
    cd $tmpdir

    # Get acme.sh
    curl --silent \
        --output acme.tar.gz \
        'https://codeload.github.com/acmesh-official/acme.sh/tar.gz/master'

    tar -xf acme.tar.gz
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

cat <<EOF >~/.acme.sh/reload.bash
#!/bin/bash

set -eux

cd /etc/ssl/private

(
trap 'rm -f cloudkey.p12' EXIT

openssl pkcs12 \\
    -export \\
    -in /etc/ssl/private/cloudkey.crt \\
    -inkey /etc/ssl/private/cloudkey.key \\
    -out /etc/ssl/private/cloudkey.p12 \\
    -name unifi \\
    -password pass:aircontrolenterprise

keytool -importkeystore \\
    -deststorepass aircontrolenterprise \\
    -destkeypass aircontrolenterprise \\
    -destkeystore unifi.keystore.jks \\
    -srckeystore cloudkey.p12 \\
    -srcstoretype PKCS12 \\
    -srcstorepass aircontrolenterprise \\
    -alias unifi \\
    -noprompt
)

chown root:ssl-cert cloudkey.crt cloudkey.key unifi.keystore.jks.md5
chown unifi:ssl-cert unifi.keystore.jks

chmod 640 cloudkey.crt cloudkey.key unifi.keystore.jks unifi.keystore.jks.md5

/usr/sbin/nginx -t
service unifi restart
EOF

chmod +x ~/.acme.sh/reload.bash

set +x
export AWS_ACCESS_KEY_ID="$1"
export AWS_SECRET_ACCESS_KEY="$2"
set -x

~/.acme.sh/acme.sh \
    --issue \
    --dns dns_aws \
    -d unifi.ravron.com \
    --pre-hook 'tar -zcvf ~/latest-tls-backup.tgz /etc/ssl/private/*' \
    --reloadcmd "~/.acme.sh/reload.bash" \
    --fullchain-file "/etc/ssl/private/cloudkey.crt" \
    --key-file "/etc/ssl/private/cloudkey.key" \
    --accountemail 'ravron@posteo.net'
