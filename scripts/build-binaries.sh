#!/usr/bin/env bash
set -o pipefail

########################################################################################################################
### GET SCRIPT PARAMETERS ###
########################################################################################################################
FLAG_HELP=$1

########################################################################################################################
### DEFINE SCRIPT PARAMETERS ###
########################################################################################################################
LAST_REPO_NAME=""
LAST_MINOR=""
LAST_RELEASE=""
OUR_LAST_RELEASE=""

########################################################################################################################
### DEFINE SCRIPT FUNCTIONS ###
########################################################################################################################
function usage() {
    echo -e "################################################################"
    echo -e "Usage: bash build-binaries.sh"
    echo -e "Dependencies:"
    echo -e "  Environment variables:"
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

    echo -e "ARCH_BUILD: ${ARCH_BUILD}"
}

#
function check_env() {
    echo -e "\n================ Check env variables ================\n"

    # Don't allow empty variables from this point
    if [ -z "${ARCH_BUILD}" ]; then
      echo "[X] Check env variables fails.";
      return 1
    fi

    echo -e "[ok] Check env variables passed."

    return 0
}

#
function install_dependencies() {
    echo -e "\n================ Install dependencies ================\n"
    local FUNC_EXIT_CODE=0

    # Update package list
    sudo apt-get update --assume-yes --quiet || FUNC_EXIT_CODE=$?

    if [ $FUNC_EXIT_CODE -ne 0 ]; then
        echo -e "[X] Repository update fails."
        return $FUNC_EXIT_CODE
    fi

    #
    SSL=openssl
    LUA_PACKAGE=$(sudo apt-cache search -q 'lua[0-9].[0-9]-dev' | sort | tail -1)
    export LUA_VERSION=${LUA_PACKAGE/-*}

    sudo apt-get install --assume-yes --quiet \
      linux-headers \
      build-essentials \
      zlib-dev \
      "${SSL}"-dev \
      "${LUA_PACKAGE}" \
      pcre2-dev \
      wget || FUNC_EXIT_CODE=$?

    if [ $FUNC_EXIT_CODE -ne 0 ]; then
        echo -e "[X] Dependencies installation fails."
        return $FUNC_EXIT_CODE
    fi

    return 0
}

#
function check_last_release() {
    echo -e "\n================ Check last release ================\n"
    local FUNC_EXIT_CODE

    # Get the last minor release repository
    LAST_REPO_NAME=$(wget -qO- 'http://git.haproxy.org/?a=project_index' | \
      grep -E -i "haproxy-([[:digit:].]+).git" | \
      cut -d' ' -f1 | \
      sort | \
      tail -n1 | xargs)
    if [ -z "${LAST_REPO_NAME}" ]; then
        echo -e "[X] Get name of haproxy last repository fails."
        return 2
    fi

    # Get last minor version
    LAST_MINOR=$(echo "${LAST_REPO_NAME}" | sed -E 's/haproxy-(.*).git/\1/' | xargs)
    if [ -z "${LAST_MINOR}" ]; then
        echo -e "[X] Get last minor version of haproxy repository fails."
        return 2
    fi

    # Get last release tag
    LAST_RELEASE=$(git ls-remote --heads --tags "http://git.haproxy.org/git/${LAST_REPO_NAME}/" | \
      awk '{print $2}' | \
      grep -E -i 'v[[:digit:]]{1,3}.[[:digit:]]{1,3}(.[[:digit:]]{1,3})?$' | \
      sed 's#refs/tags/v##' | \
      sort  | \
      tail -n1 | xargs)
    if [ -z "${LAST_RELEASE}" ]; then
        echo -e "[X] Get last release tag of haproxy repository fails."
        return 2
    fi

    # Get our last release
    OUR_LAST_RELEASE=$(git ls-remote --heads --tags "https://github.com/prosimcorp/haproxy-bins/" | \
      awk '{print $2}' | \
      grep -E -i 'v[[:digit:]]{1,3}.[[:digit:]]{1,3}(.[[:digit:]]{1,3})?$' | \
      sed 's#refs/tags/v##' | \
      sort | \
      tail -n1 | xargs)
    if [ -z "${OUR_LAST_RELEASE}" ]; then
        echo -e "[X] Get our last release tag of prosimcorp repository fails."
        return 2
    fi

    if [ "${OUR_LAST_RELEASE}" -eq "${LAST_RELEASE}" ]; then
        echo "[ok] Release ${LAST_RELEASE} already exist."
        return 1
    fi

    return 0
}

#
function download_haproxy_code() {
    echo -e "\n================ Download haproxy code ================\n"
    local FUNC_EXIT_CODE=0

    # Download the package
    # Ref: # http://www.haproxy.org/download/2.7/src/haproxy-2.7.1.tar.gz
    wget -q "http://www.haproxy.org/download/${LAST_MINOR}/src/haproxy-${LAST_RELEASE}.tar.gz" || FUNC_EXIT_CODE=$?
    if [ $FUNC_EXIT_CODE -ne 0 ]; then
        echo -e "[X] Download of 'haproxy-${LAST_RELEASE}.tar.gz' fails."
        return $FUNC_EXIT_CODE
    fi

    # Untar the last release
    tar -xvf "haproxy-${LAST_RELEASE}.tar.gz" || FUNC_EXIT_CODE=$?
    if [ $FUNC_EXIT_CODE -ne 0 ]; then
        echo -e "[X] Untar of 'haproxy-${LAST_RELEASE}.tar.gz' fails."
        return $FUNC_EXIT_CODE
    fi

    # Move to inner directory
    cd haproxy-* || FUNC_EXIT_CODE=$?
    if [ $FUNC_EXIT_CODE -ne 0 ]; then
        echo -e "[X] Moving to child directory fails."
        return $FUNC_EXIT_CODE
    fi

    return 0
}

#
function build_binary() {
  echo -e "\n================ Build binary ================\n"
  local  FUNC_EXIT_CODE=0

  case "${ARCH_BUILD}" in

    x86_64)
      build_x86_64 || FUNC_EXIT_CODE=$?
      ;;

    arm64)
      build_arm64 || FUNC_EXIT_CODE=$?
      ;;

    *)
      printf "%s" "[INFO] Env variable ARCH_BUILD not defined"
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
function build_x86_64() {

    make -j"$(nproc)" \
      DEBUG="-s" \
      TARGET=generic \
      ARCH=x86_64 \
      USE_THREAD=1 \
      USE_PTHREAD_PSHARED=1 \
      USE_LIBCRYPT=1 \
      USE_GETADDRINFO=1 \
      USE_TFO=1 \
      USE_NS=1 \
      USE_OPENSSL=1 \
      USE_ZLIB=1 \
      USE_PCRE2=1 \
      USE_PCRE2_JIT=1 \
      USE_LUA=1 \
      LUA_INC="/usr/include/$LUA_VERSION" \
      LUA_LD_FLAGS="-lz -L/usr/lib/$LUA_VERSION -static" || FUNC_EXIT_CODE=$?

    return $FUNC_EXIT_CODE
}

#
function build_arm64() {
    return 0
}

#
function create_release() {
    ls # To see if everything is fine
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

    install_dependencies || FUNC_EXIT_CODE=$?
    if [ $FUNC_EXIT_CODE -ne 0 ]; then
        return $FUNC_EXIT_CODE
    fi

    check_last_release || FUNC_EXIT_CODE=$?
    if [ $FUNC_EXIT_CODE -ne 0 ]; then
        if [ $FUNC_EXIT_CODE -eq 1 ]; then
            return 0
        fi
        return $FUNC_EXIT_CODE
    fi

    download_haproxy_code || FUNC_EXIT_CODE=$?
    if [ $FUNC_EXIT_CODE -ne 0 ]; then
        return $FUNC_EXIT_CODE
    fi

    build_binary || FUNC_EXIT_CODE=$?
    if [ $FUNC_EXIT_CODE -ne 0 ]; then
        return $FUNC_EXIT_CODE
    fi

    create_release || FUNC_EXIT_CODE=$?
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
    echo -e "[X] Script 'build-binaries.sh' fails, exit code: ${EXIT_CODE}."
    exit $EXIT_CODE
fi

exit 0
