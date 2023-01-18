#!/usr/bin/env bash
set -o pipefail

# Defined to avoid relative-pathing issues
SELF_PATH=$(cd $(dirname "$0"); pwd)

export PCRE2_BUILD_DIR
export ZLIB_BUILD_DIR
export OPENSSL_BUILD_DIR

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
    LUA_PACKAGE=$(sudo apt-cache search -q 'lua[0-9].[0-9]-dev' | sort | tail -1 | cut -d' ' -f1)
    export LUA_VERSION=$(echo "${LUA_PACKAGE/-*}" | sed 's/lib//' | xargs)

    sudo apt-get install --assume-yes --quiet \
      linux-headers-"$(uname -r)" \
      build-essential \
      musl-dev \
      zlib1g-dev lua-zlib-dev \
      libssl-dev \
      libquickfix-dev \
      "${LUA_PACKAGE}"  \
      libpcre2-dev lua-rex-pcre2-dev\
      wget || FUNC_EXIT_CODE=$?

    if [ $FUNC_EXIT_CODE -ne 0 ]; then
        echo -e "[X] Dependencies installation fails."
        return $FUNC_EXIT_CODE
    fi

    return 0
}

#
function check_last_haproxy_release() {
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

    OUR_RELEASES=$(git ls-remote --heads --tags "https://github.com/prosimcorp/haproxy-bins/" | \
          awk '{print $2}' | \
          grep -E -i 'v[[:digit:]]{1,3}.[[:digit:]]{1,3}(.[[:digit:]]{1,3})?$' | \
          sed 's#refs/tags/v##' | \
          sort)

    OUR_RELEASES_COUNT=$(printf "%s" "${OUR_RELEASES}" | wc -w)
    if [ "${OUR_RELEASES_COUNT}" -eq 0 ]; then
        echo "[ok] Create release ${LAST_RELEASE}."
        return 0
    fi

    # Get our last release
    OUR_LAST_RELEASE=$(echo "${OUR_RELEASES}" tail -n1 | xargs)
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
    cd haproxy-"${LAST_RELEASE}" || FUNC_EXIT_CODE=$?
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

    ls /lib/x86_64-linux-gnu/*.a

    # Ref: https://github.com/haproxy/haproxy/blob/master/Makefile

    # USE_PCRE             : enable use of libpcre for regex. Recommended.
    # USE_STATIC_PCRE      : enable static libpcre. Recommended.
    # USE_LIBCRYPT         : enable encrypted passwords using -lcrypt
    # USE_CRYPT_H          : set it if your system requires including crypt.h
    # USE_GETADDRINFO      : use getaddrinfo() to resolve IPv6 host names.
    # USE_OPENSSL          : enable use of OpenSSL. Recommended, but see below.
    # USE_ENGINE           : enable use of OpenSSL Engine.
    # USE_LUA              : enable Lua support.
    # USE_ZLIB             : enable zlib library support and disable SLZ
    # USE_TFO              : enable TCP fast open. Supported on Linux >= 3.7.
    # USE_NS               : enable network namespace support. Supported on Linux >= 2.6.24.
    # USE_PROMEX           : enable the Prometheus exporter
    # USE_SYSTEMD          : enable sd_notify() support.
    # USE_MEMORY_PROFILING : enable the memory profiler. Linux-glibc only.

    # LUA_INC        : force the include path to lua
    # LUA_LD_FLAGS   :

    # ADDLIB may be used to complete the library list in the form -Lpath -llib

    #make TARGET=linux2628 USE_STATIC_PCRE=1   ADDLIB=-ldl -lzlib PCREDIR=$PCREDIR
    #make install

    make -j"$(nproc)" \
      TARGET=linux-glibc \
      ARCH=x86_64 \
      USE_THREAD="" \
      USE_PTHREAD_PSHARED="" \
      USE_LIBCRYPT="" \
      USE_CRYPT_H="" \
      USE_GETADDRINFO="" \
      USE_TFO="" \
      USE_NS="" \
      USE_OPENSSL=1 \
      SSL_INC="$OPENSSL_BUILD_DIR/include" \
      SSL_LIB="$OPENSSL_BUILD_DIR/lib" \
      USE_ZLIB=1 \
      ZLIB_LIB="$ZLIB_BUILD_DIR/lib" \
      ZLIB_INC="$ZLIB_BUILD_DIR/include" \
      USE_STATIC_PCRE2=1 \
      PCRE2_LIB="$PCRE2_BUILD_DIR/lib" \
      PCRE2_INC="$PCRE2_BUILD_DIR/include" \
      LDFLAGS="-static -pthread -ldl"


      #ADDLIB="-ldl -lzlib"
      #LUA_INC="/usr/include/$LUA_VERSION" \
      #LUA_LDFLAGS="-L/usr/lib/$LUA_VERSION" \
      #OPTIONS_LDFLAGS="" || FUNC_EXIT_CODE=$?
#      ZLIB_LIB="libz.a" \
#      USE_LUA=1 \
#      LUA_LD_FLAGS="-lz -L/usr/lib/$LUA_VERSION -static" || FUNC_EXIT_CODE=$?

    ldd haproxy

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

    check_last_haproxy_release || FUNC_EXIT_CODE=$?
    if [ $FUNC_EXIT_CODE -ne 0 ]; then
        if [ $FUNC_EXIT_CODE -eq 1 ]; then
            return 0
        fi
        return $FUNC_EXIT_CODE
    fi

    bash "${SELF_PATH}/build-static-lib-pcre2.sh" || FUNC_EXIT_CODE=$?
    if [ $FUNC_EXIT_CODE -ne 0 ]; then
        return $FUNC_EXIT_CODE
    fi

    bash "${SELF_PATH}/build-static-lib-zlib.sh" || FUNC_EXIT_CODE=$?
    if [ $FUNC_EXIT_CODE -ne 0 ]; then
        return $FUNC_EXIT_CODE
    fi

    bash "${SELF_PATH}/build-static-lib-openssl.sh" || FUNC_EXIT_CODE=$?
    if [ $FUNC_EXIT_CODE -ne 0 ]; then
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
