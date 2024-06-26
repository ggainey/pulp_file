#!/usr/bin/env bash
# coding=utf-8

# WARNING: DO NOT EDIT!
#
# This file was generated by plugin_template, and is managed by it. Please use
# './plugin-template --github pulp_file' to update this file.
#
# For more info visit https://github.com/pulp/plugin_template

set -mveuo pipefail

# make sure this script runs at the repo root
cd "$(dirname "$(realpath -e "$0")")"/../../..

source .github/workflows/scripts/utils.sh

export POST_SCRIPT=$PWD/.github/workflows/scripts/post_script.sh
export POST_DOCS_TEST=$PWD/.github/workflows/scripts/post_docs_test.sh
export FUNC_TEST_SCRIPT=$PWD/.github/workflows/scripts/func_test_script.sh

# Needed for both starting the service and building the docs.
# Gets set in .github/settings.yml, but doesn't seem to inherited by
# this script.
export DJANGO_SETTINGS_MODULE=pulpcore.app.settings
export PULP_SETTINGS=$PWD/.ci/ansible/settings/settings.py

export PULP_URL="https://pulp"

if [[ "$TEST" = "docs" ]]; then
  if [[ "$GITHUB_WORKFLOW" == "File CI" ]]; then
    towncrier build --yes --version 4.0.0.ci
  fi
  exit
fi

REPORTED_STATUS="$(pulp status)"

echo "machine pulp
login admin
password password
" | cmd_user_stdin_prefix bash -c "cat >> ~pulp/.netrc"
# Some commands like ansible-galaxy specifically require 600
cmd_prefix bash -c "chmod 600 ~pulp/.netrc"

# Generate and install binding
pushd ../pulp-openapi-generator
# Use app_label to generate api.json and package to produce the proper package name.

if [ "$(jq -r '.domain_enabled' <<<"$REPORTED_STATUS")" = "true" ]
then
  # Workaround: Domains are not supported by the published bindings.
  # Generate new bindings for all packages.
  for item in $(jq -r '.versions[] | tojson' <<<"$REPORTED_STATUS")
  do
    echo $item
    COMPONENT="$(jq -r '.component' <<<"$item")"
    VERSION="$(jq -r '.version' <<<"$item")"
    MODULE="$(jq -r '.module' <<<"$item")"
    PACKAGE="${MODULE%%.*}"
    cmd_prefix pulpcore-manager openapi --bindings --component "${COMPONENT}" > api.json
    ./gen-client.sh api.json "${COMPONENT}" python "${PACKAGE}"
    cmd_prefix pip3 install "/root/pulp-openapi-generator/${PACKAGE}-client"
    sudo rm -rf "./${PACKAGE}-client"
  done
else
  # Sadly: Different pulpcore-versions aren't either...
  for item in $(jq -r '.versions[]| tojson' <<<"$REPORTED_STATUS")
  do
    echo $item
    COMPONENT="$(jq -r '.component' <<<"$item")"
    VERSION="$(jq -r '.version' <<<"$item")"
    MODULE="$(jq -r '.module' <<<"$item")"
    PACKAGE="${MODULE%%.*}"
    cmd_prefix pulpcore-manager openapi --bindings --component "${COMPONENT}" > api.json
    ./gen-client.sh api.json "${COMPONENT}" python "${PACKAGE}"
    cmd_prefix pip3 install "/root/pulp-openapi-generator/${PACKAGE}-client"
    sudo rm -rf "./${PACKAGE}-client"
  done
fi
popd

# At this point, this is a safeguard only, so let's not make too much fuzz about the old status format.
echo "$REPORTED_STATUS" | jq -r '.versions[]|select(.package)|(.package|sub("_"; "-")) + "-client==" + .version' > bindings_requirements.txt
cmd_stdin_prefix bash -c "cat > /tmp/unittest_requirements.txt" < unittest_requirements.txt
cmd_stdin_prefix bash -c "cat > /tmp/functest_requirements.txt" < functest_requirements.txt
cmd_stdin_prefix bash -c "cat > /tmp/bindings_requirements.txt" < bindings_requirements.txt
cmd_prefix pip3 install -r /tmp/unittest_requirements.txt -r /tmp/functest_requirements.txt -r /tmp/bindings_requirements.txt

CERTIFI=$(cmd_prefix python3 -c 'import certifi; print(certifi.where())')
cmd_prefix bash -c "cat /etc/pulp/certs/pulp_webserver.crt >> '$CERTIFI'"

# check for any uncommitted migrations
echo "Checking for uncommitted migrations..."

# Run unit tests.

if [ -f "$POST_SCRIPT" ]; then
  source "$POST_SCRIPT"
fi
