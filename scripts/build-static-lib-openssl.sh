#!/usr/bin/env bash
set -o pipefail

# Defined to avoid relative-pathing issues
SELF_PATH=$(cd $(dirname "$0"); pwd)
TMP_PATH="${SELF_PATH}/../tmp"

########################################################################################################################
### GET SCRIPT PARAMETERS ###
########################################################################################################################
FLAG_HELP=$1

########################################################################################################################
### DEFINE SCRIPT PARAMETERS ###
########################################################################################################################
LAST_RELEASE=""
# export OPENSSL_BUILD_DIR

########################################################################################################################
### DEFINE SCRIPT FUNCTIONS ###
########################################################################################################################
function usage() {
    echo -e "################################################################"
    echo -e "Usage: bash build-static-lib-zlib.sh"
    echo -e "Dependencies:"
    echo -e "  Environment variables:"
    echo -e "    TARGET_BUILD: target you want to build for."
    echo -e "    ARCH_BUILD: architecture that you want to build."
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

    echo -e "TARGET_BUILD: ${TARGET_BUILD}"
    echo -e "ARCH_BUILD: ${ARCH_BUILD}"
}

#
function check_env() {
    echo -e "\n================ Check env variables ================\n"

    # Don't allow empty variables from this point
    if [ -z "${TARGET_BUILD}" ]; then
      echo "[X] Check env variables fails.";
      return 1
    fi

    if [ -z "${ARCH_BUILD}" ]; then
      echo "[X] Check env variables fails.";
      return 1
    fi

    echo -e "[ok] Check env variables passed."

    return 0
}

#
function get_last_openssl_release() {
    echo -e "\n================ Get last release ================\n"
    local FUNC_EXIT_CODE=0

    # Get last release tag
    LAST_RELEASE=$(git ls-remote --tags "https://github.com/openssl/openssl.git" | \
      awk '{print $2}' | \
      grep -E -i '[[:digit:]]{1,3}\.[[:digit:]]{1,3}(\.[[:digit:]]{1,3})?$' | \
      sed 's#refs/tags/##' | \
      sort --version-sort | \
      tail -n1 | xargs)
    if [ -z "${LAST_RELEASE}" ]; then
        echo -e "[X] Get last release tag of OpenSSL repository fails."
        return 2
    fi

    # Create temporary directory
    mkdir -p "${TMP_PATH}" || FUNC_EXIT_CODE=$?
    if [ $FUNC_EXIT_CODE -ne 0 ]; then
        echo -e "[X] Creation of temporary directory fails."
        return $FUNC_EXIT_CODE
    fi

    # Move to temporary directory
    cd "${TMP_PATH}" || FUNC_EXIT_CODE=$?
    if [ $FUNC_EXIT_CODE -ne 0 ]; then
        echo -e "[X] Moving to temporary directory fails."
        return $FUNC_EXIT_CODE
    fi

    # Download the package
    wget --timestamping --quiet "https://github.com/openssl/openssl/archive/refs/tags/${LAST_RELEASE}.tar.gz" || FUNC_EXIT_CODE=$?
    if [ $FUNC_EXIT_CODE -ne 0 ]; then
        echo -e "[X] Download of '${LAST_RELEASE}.tar.gz' fails."
        return $FUNC_EXIT_CODE
    fi

    # Uncompress the last release
    tar -xvf "${LAST_RELEASE}.tar.gz" || FUNC_EXIT_CODE=$?
    if [ $FUNC_EXIT_CODE -ne 0 ]; then
        echo -e "[X] Untar of '${LAST_RELEASE}.tar.gz' fails."
        return $FUNC_EXIT_CODE
    fi

    # Remove old temporary directory
    rm -rf "${LAST_RELEASE}" || FUNC_EXIT_CODE=$?
    if [ $FUNC_EXIT_CODE -ne 0 ]; then
        echo -e "[X] Remove old uncompressed directory '${LAST_RELEASE}' fails."
        return $FUNC_EXIT_CODE
    fi

    # Rename directory because of the prefix
    mv "openssl-${LAST_RELEASE}" "${LAST_RELEASE}" || FUNC_EXIT_CODE=$?
    if [ $FUNC_EXIT_CODE -ne 0 ]; then
        echo -e "[X] Rename directory to '${LAST_RELEASE}' fails."
        return $FUNC_EXIT_CODE
    fi

    # Move to inner directory
    cd "${LAST_RELEASE}" || FUNC_EXIT_CODE=$?
    if [ $FUNC_EXIT_CODE -ne 0 ]; then
        echo -e "[X] Moving to child directory fails."
        return $FUNC_EXIT_CODE
    fi

    return 0
}

# Build binary files according to the architecture and target
function build_static_library() {
    echo -e "\n================ Build static library ================\n"
    local  FUNC_EXIT_CODE=0
    local TARGET="${TARGET_BUILD}_${ARCH_BUILD}"

    export OPENSSL_BUILD_DIR="${SELF_PATH}/../libs/build/${LAST_RELEASE}"

    mkdir -p "${OPENSSL_BUILD_DIR}" || FUNC_EXIT_CODE=$?
    if [ $FUNC_EXIT_CODE -ne 0 ]; then
      echo -e "[X] Creation of directory for building OPENSSL fails."
      return $FUNC_EXIT_CODE
    fi

    case "${TARGET}" in

      linux_x86_64)
        build_linux_x86_64 || FUNC_EXIT_CODE=$?
        ;;

      linux_aarch64)
        build_linux_aarch64 || FUNC_EXIT_CODE=$?
        ;;

      *)
        printf "%s" "[X] Env variable ARCH_BUILD not defined"
        return 1
        ;;
    esac

    if [ $FUNC_EXIT_CODE -ne 0 ]; then
        echo -e "[X] Build in '${ARCH_BUILD}' fails."
        return $FUNC_EXIT_CODE
    fi

    return 0
}

#
# Ref: https://github.com/openssl/openssl/blob/master/Configure
function build_linux_x86_64() {

    CFLAGS='-std=c18 -O2 -Wall -Wextra -Wpedantic -Wconversion'
    ./Configure --prefix="${OPENSSL_BUILD_DIR}" -static || FUNC_EXIT_CODE=$?
    if [ $FUNC_EXIT_CODE -ne 0 ]; then
      echo -e "[X] Execution of configuration script fails."
      return $FUNC_EXIT_CODE
    fi

    make -j"$(nproc)" || FUNC_EXIT_CODE=$?
    if [ $FUNC_EXIT_CODE -ne 0 ]; then
        echo -e "[X] Execution of makefile fails."
        return $FUNC_EXIT_CODE
    fi

    # Use of install_sw instead of install to avoid building documentation
    make -j"$(nproc)" install_sw || FUNC_EXIT_CODE=$?
    if [ $FUNC_EXIT_CODE -ne 0 ]; then
        echo -e "[X] Execution of makefile install stage fails."
        return $FUNC_EXIT_CODE
    fi

    return $FUNC_EXIT_CODE
}

#
function build_linux_aarch64() {

    CFLAGS='-std=c18 -O2 -Wall -Wextra -Wpedantic -Wconversion'
    ./Configure linux-aarch64 --prefix="${OPENSSL_BUILD_DIR}" -static || FUNC_EXIT_CODE=$?
    if [ $FUNC_EXIT_CODE -ne 0 ]; then
      echo -e "[X] Execution of configuration script fails."
      return $FUNC_EXIT_CODE
    fi

    make -j"$(nproc)" CC="aarch64-linux-gnu-gcc" || FUNC_EXIT_CODE=$?
    if [ $FUNC_EXIT_CODE -ne 0 ]; then
        echo -e "[X] Execution of makefile fails."
        return $FUNC_EXIT_CODE
    fi

    # Use of install_sw instead of install to avoid building documentation
    make -j"$(nproc)" install_sw CC="aarch64-linux-gnu-gcc" || FUNC_EXIT_CODE=$?
    if [ $FUNC_EXIT_CODE -ne 0 ]; then
        echo -e "[X] Execution of makefile install stage fails."
        return $FUNC_EXIT_CODE
    fi

    return $FUNC_EXIT_CODE
}

#
function main() {
    echo -e "################################################################"
    echo -e "#### Build static library openssl script ####"
    local FUNC_EXIT_CODE=0

    show_env

    check_env || FUNC_EXIT_CODE=$?
    if [ $FUNC_EXIT_CODE -ne 0 ]; then
        return $FUNC_EXIT_CODE
    fi

    get_last_openssl_release || FUNC_EXIT_CODE=$?
    if [ $FUNC_EXIT_CODE -ne 0 ]; then
        if [ $FUNC_EXIT_CODE -eq 1 ]; then
            return 0
        fi
        return $FUNC_EXIT_CODE
    fi

    build_static_library || FUNC_EXIT_CODE=$?
    if [ $FUNC_EXIT_CODE -ne 0 ]; then
        return $FUNC_EXIT_CODE
    fi

    echo -e "\n#### End of: Build static library openssl script ####"
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
    echo -e "[X] Script 'build-static-lib-openssl.sh' fails, exit code: ${EXIT_CODE}."
    exit $EXIT_CODE
fi

exit 0
