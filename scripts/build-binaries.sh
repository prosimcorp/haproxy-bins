#!/usr/bin/env bash
set -o pipefail

# Defined to avoid relative-pathing issues
SELF_PATH=$(cd "$(dirname "$0")" || echo "."; pwd)
TMP_PATH="${SELF_PATH}/../tmp"

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
function install_dependencies() {
    echo -e "\n================ Install dependencies ================\n"
    local FUNC_EXIT_CODE=0

    # Update package list
    sudo apt-get update --assume-yes --quiet || FUNC_EXIT_CODE=$?

    if [ $FUNC_EXIT_CODE -ne 0 ]; then
        echo -e "[X] Repository update fails."
        return $FUNC_EXIT_CODE
    fi

    # gcc-aarch64-linux-gnu binutils-aarch64-linux-gnu
    sudo apt-get install --assume-yes --quiet \
      linux-headers-"$(uname -r)" \
      build-essential \
      crossbuild-essential-arm64 \
      wget || FUNC_EXIT_CODE=$?

    if [ $FUNC_EXIT_CODE -ne 0 ]; then
        echo -e "[X] Dependencies installation fails."
        return $FUNC_EXIT_CODE
    fi

    return 0
}

function build_libraries() {

    echo -e "\n================ Build libraries ================\n"
    local FUNC_EXIT_CODE=0

    # Create the directory that contains the build of all libraries
    mkdir -p "${SELF_PATH}/../libs/build" || FUNC_EXIT_CODE=$?
    if [ $FUNC_EXIT_CODE -ne 0 ]; then
        echo -e "[X] Creation of libs/build directory fails."
        return $FUNC_EXIT_CODE
    fi

    # Create a file to store data about lib versions
    touch "${SELF_PATH}/../libs/info"
    if [ $FUNC_EXIT_CODE -ne 0 ]; then
        echo -e "[X] Creation of libs info file fails."
        return $FUNC_EXIT_CODE
    fi

    # Execute the compilation process
    bash "${SELF_PATH}/build-static-lib-pcre2.sh" || FUNC_EXIT_CODE=$?
    if [ $FUNC_EXIT_CODE -ne 0 ]; then
        echo -e "[X] Creation of libs/build directory fails."
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

    bash "${SELF_PATH}/build-static-lib-lua.sh" || FUNC_EXIT_CODE=$?
    if [ $FUNC_EXIT_CODE -ne 0 ]; then
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
    # Ref: # http://www.haproxy.org/download/2.7/src/haproxy-2.7.1.tar.gz
    wget --timestamping --quiet "http://www.haproxy.org/download/${LAST_MINOR}/src/haproxy-${LAST_RELEASE}.tar.gz" || FUNC_EXIT_CODE=$?
    if [ $FUNC_EXIT_CODE -ne 0 ]; then
        echo -e "[X] Download of 'haproxy-${LAST_RELEASE}.tar.gz' fails."
        return $FUNC_EXIT_CODE
    fi

    # Uncompress the last release
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

# Don't be scared, sweet child. The problem is Haproxy maintainers are not prepared
# to give the users the option to statically link everything. We are here to make your
# wet wishes real. For that, we have to patch some things, and diff+patch is not enough.
function patch_haproxy_makefile() {
    echo -e "\n================ Patch Haproxy makefile ================\n"
    local FUNC_EXIT_CODE=0

    # 'libm' (-lm) is not included in the following list due to it would require to link statically 'libc' too (-lc)
    FLAGS_TO_PATCH=(-lcrypt -ldl -lrt -lnetwork -lnsl -lsocket -lz -lpthread -lssl -lcrypto -lwolfssl -lda -lwurfl -lsystemd -latomic '-l\$\(LUA_LIB_NAME\)')

    HAPROXY_BUILD_DIR="$(find "${TMP_PATH}/" -maxdepth 1 -type d -name "haproxy-*" -print0 | xargs --null)"

    # Replace each dynamic library-related flag with its static counterpart
    for FLAG in "${FLAGS_TO_PATCH[@]}"
    do
        perl -pi.back -e "s/(?<![\w])${FLAG}(?![\w])/-Wl,-Bstatic ${FLAG} -Wl,-Bdynamic /g;" "${HAPROXY_BUILD_DIR}/Makefile"
    done
}

# Build binary files according to the architecture and target
function build_binary() {
    echo -e "\n================ Build binary ================\n"
    local  FUNC_EXIT_CODE=0
    local TARGET="${TARGET_BUILD}_${ARCH_BUILD}"

    ZLIB_BUILD_DIR="$(find "${SELF_PATH}/../libs/build/" -maxdepth 1 -type d -name "zlib-*" -print0 | xargs --null)"
    PCRE2_BUILD_DIR="$(find "${SELF_PATH}/../libs/build/" -maxdepth 1 -type d -name "pcre2-*" -print0 | xargs --null)"
    OPENSSL_BUILD_DIR="$(find "${SELF_PATH}/../libs/build/" -maxdepth 1 -type d -name "openssl-*" -print0 | xargs --null)"
    LUA_BUILD_DIR="$(find "${SELF_PATH}/../libs/build/" -maxdepth 1 -type d -name "lua-*" -print0 | xargs --null)"

    case "${TARGET}" in

      linux_x86_64)
        build_linux_x86_64 || FUNC_EXIT_CODE=$?
        ;;

      linux_aarch64)
        build_linux_aarch64 || FUNC_EXIT_CODE=$?
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
function build_linux_x86_64() {

    # Ref: https://github.com/haproxy/haproxy/blob/master/Makefile
    make -j"$(nproc)" \
      TARGET=linux-glibc \
      ARCH=x86_64 \
      USE_LIBCRYPT=1 \
      USE_CRYPT_H=1 \
      USE_THREAD=1 \
      USE_GETADDRINFO=1 \
      USE_TFO=1 \
      USE_NS=1 \
      USE_PROMEX=1 \
      USE_SHM_OPEN=1 \
      ZLIB_INC="${ZLIB_BUILD_DIR}/include" \
      ZLIB_LIB="${ZLIB_BUILD_DIR}/lib" \
      USE_ZLIB=1 \
      SSL_INC="${OPENSSL_BUILD_DIR}/include" \
      SSL_LIB="${OPENSSL_BUILD_DIR}/lib64" \
      USE_OPENSSL=1 \
      PCRE2_INC="${PCRE2_BUILD_DIR}/include" \
      PCRE2_LIB="${PCRE2_BUILD_DIR}/lib" \
      USE_STATIC_PCRE2=1 \
      LUA_INC="${LUA_BUILD_DIR}/include" \
      LUA_LIB="${LUA_BUILD_DIR}/lib" \
      USE_LUA=1

    ldd haproxy

    return $FUNC_EXIT_CODE
}

#
function build_linux_aarch64() {

    # Ref: https://github.com/haproxy/haproxy/blob/master/Makefile
    # TODO: Fix libcrypt not found on cross-compile to allow usage of options: USE_LIBCRYPT=1, USE_CRYPT_H=1
    make -j"$(nproc)" CC="aarch64-linux-gnu-gcc" \
      TARGET=linux-glibc \
      ARCH_FLAGS="" \
      USE_THREAD=1 \
      USE_GETADDRINFO=1 \
      USE_TFO=1 \
      USE_NS=1 \
      USE_PROMEX=1 \
      USE_SHM_OPEN=1 \
      ZLIB_INC="${ZLIB_BUILD_DIR}/include" \
      ZLIB_LIB="${ZLIB_BUILD_DIR}/lib" \
      USE_ZLIB=1 \
      SSL_INC="${OPENSSL_BUILD_DIR}/include" \
      SSL_LIB="${OPENSSL_BUILD_DIR}/lib" \
      USE_OPENSSL=1 \
      PCRE2_INC="${PCRE2_BUILD_DIR}/include" \
      PCRE2_LIB="${PCRE2_BUILD_DIR}/lib" \
      USE_STATIC_PCRE2=1 \
      LUA_INC="${LUA_BUILD_DIR}/include" \
      LUA_LIB="${LUA_BUILD_DIR}/lib" \
      USE_LUA=1

    ldd haproxy

    return $FUNC_EXIT_CODE
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

#    install_dependencies || FUNC_EXIT_CODE=$?
#    if [ $FUNC_EXIT_CODE -ne 0 ]; then
#        return $FUNC_EXIT_CODE
#    fi

    check_last_haproxy_release || FUNC_EXIT_CODE=$?
    if [ $FUNC_EXIT_CODE -ne 0 ]; then
        if [ $FUNC_EXIT_CODE -eq 1 ]; then
            return 0
        fi
        return $FUNC_EXIT_CODE
    fi

    build_libraries || FUNC_EXIT_CODE=$?
    if [ $FUNC_EXIT_CODE -ne 0 ]; then
        return $FUNC_EXIT_CODE
    fi

    download_haproxy_code || FUNC_EXIT_CODE=$?
    if [ $FUNC_EXIT_CODE -ne 0 ]; then
        return $FUNC_EXIT_CODE
    fi

    patch_haproxy_makefile || FUNC_EXIT_CODE=$?
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
