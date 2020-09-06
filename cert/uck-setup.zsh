#!/usr/bin/env zsh

set -eu

KEY_ID=$(aws configure get profile.acme.aws_access_key_id)
SECRET_KEY=$(aws configure get profile.acme.aws_secret_access_key)

ssh uck 'bash -s' < remote-uck-setup.bash "$KEY_ID" "$SECRET_KEY"
