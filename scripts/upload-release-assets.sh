#!/usr/bin/env bash
set -o pipefail

# Defined to avoid relative-pathing issues
SELF_PATH=$(cd "$(dirname "$0")" || echo "."; pwd)
TMP_PATH="${SELF_PATH}/../tmp"

########################################################################################################################
### GET SCRIPT PARAMETERS ###
########################################################################################################################
FLAG_HELP=$1

########################################################################################################################
### DEFINE SCRIPT FUNCTIONS ###
########################################################################################################################
function usage() {
    echo -e "################################################################"
    echo -e "Usage: bash upload-release-assets.sh"
    echo -e "Dependencies:"
    echo -e "  Environment variables:"
    echo -e "    GITHUB_TOKEN: xxx."
    echo -e "    RELEASE_UPLOAD_URL: xxx."
    echo -e "    ARTIFACTS_LOCAL_PATH: xxx."
    echo -e "  Flags: (without flags)"
    echo -e "Optionals:"
    echo -e "  Environment variables: (without env variables)"
    echo -e "  Flags:"
    echo -e "    --help,-h: show the script usage."
    echo -e "################################################################"
}

#
function show_env() {
    echo -e "\n================ Show env variables ================\n"

    echo -e "RELEASE_UPLOAD_URL: ${RELEASE_UPLOAD_URL}"
    echo -e "ARTIFACTS_LOCAL_PATH: ${ARTIFACTS_LOCAL_PATH}"
}

#
function check_env() {
    echo -e "\n================ Check env variables ================\n"

    # Don't allow empty variables from this point
    if [ -z "${RELEASE_UPLOAD_URL}" ]; then
      echo "[X] Check env variables fails.";
      return 1
    fi

    if [ -z "${GITHUB_TOKEN}" ]; then
      echo "[X] Check env variables fails.";
      return 1
    fi

    if [ -z "${ARTIFACTS_LOCAL_PATH}" ]; then
      echo "[X] Check env variables fails.";
      return 1
    fi

    echo -e "[ok] Check env variables passed."

    return 0
}

function upload_assets() {

    RELEASE_UPLOAD_URL=$(echo "${RELEASE_UPLOAD_URL}" | sed -e 's#{?name,label}##g' | xargs)

    curl \
        -X POST \
        -H "Accept: application/vnd.github+json" \
        -H "Authorization: Bearer ${GITHUB_TOKEN}"\
        -H "X-GitHub-Api-Version: 2022-11-28" \
        -H "Content-Type: application/octet-stream" \
        "${RELEASE_UPLOAD_URL}"?name=haproxy-linux_x86_64 \
        --data-binary "@${ARTIFACTS_LOCAL_PATH}/haproxy-linux_x86_64"

    curl \
        -X POST \
        -H "Accept: application/vnd.github+json" \
        -H "Authorization: Bearer ${GITHUB_TOKEN}"\
        -H "X-GitHub-Api-Version: 2022-11-28" \
        -H "Content-Type: application/octet-stream" \
        "${RELEASE_UPLOAD_URL}"?name=haproxy-linux_aarch64 \
        --data-binary "@${ARTIFACTS_LOCAL_PATH}/haproxy-linux_aarch64"

  return 0
}

#
function main() {
    echo -e "################################################################"
    echo -e "#### Build binaries script ####"
    local FUNC_EXIT_CODE=0

    show_env

    check_env || FUNC_EXIT_CODE=$?
    if [ $FUNC_EXIT_CODE -ne 0 ]; then
        return $FUNC_EXIT_CODE
    fi

    upload_assets || FUNC_EXIT_CODE=$?
    if [ $FUNC_EXIT_CODE -ne 0 ]; then
        return $FUNC_EXIT_CODE
    fi

    echo -e "\n#### End of: Build binaries script ####"
    echo -e "################################################################"

    return 0
}
########################################################################################################################
### SCRIPT FUNCTIONS EXECUTION ###
########################################################################################################################
if [ "${FLAG_HELP}" == "--help" ] ||
   [ "${FLAG_HELP}" == "-h" ]; then
    usage
    exit 0
fi

main
EXIT_CODE=$?
if [ $EXIT_CODE -ne 0 ]; then
    echo -e "[X] Script 'upload-release-assets.sh' fails, exit code: ${EXIT_CODE}."
    exit $EXIT_CODE
fi

exit 0
