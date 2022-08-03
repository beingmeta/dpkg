#!/bin/sh

export PACKAGING_ROOT STATE_ROOT SOURCE_ROOT WORK_ROOT
export PATH LOGFILE LIBNAME TOOLS OUTPUT CONFIG_ROOT
export PKGNAME VERSION REL_VERSION BRANCH VARIANT FULL_VERSION
export BASE_VERSION MAJOR_VERSION MINOR_VERSION RELEASE_VERSION
export KNO_VERSION KNO_MAJOR KNO_MINOR GIT_PROTOCOL
export REPOMAN REPO_SYSTEM REPO REPO_URL REPO_LOGIN
export CODENAME DISTRO STATUS ARCH URGENCY
export PKGTOOL PKGINFO

PKGLOG=${PKGLOG:-/dev/null}

logmsg () {
    echo "pkg ($$@$(pwd):${DISTRO}) $1" >&2;
}

infomsg () {
    if [ -n "${PKGLOG}" ] && [ -w "${PKGLOG}" ]; then
        echo "pkg ($$@$(pwd):${DISTRO}) $1" >>${PKGLOG};
    else
        echo "pkg ($$@$(pwd):${DISTRO}) $1" >&2;
    fi;
}

dbgmsg () {
    if [ -n "${DEBUGGING}" ]; then
	echo "pkgdebug ($$@$(pwd):${DISTRO}) $1" >&2;
    fi;
}

dbgmsg "Sourcing packaging.sh into $$";

export SUDO
if [ "$(id -u)" != "0" ]; then SUDO=sudo; fi;

set_pkg_state() {
    local state=$1;
    if [ -z "${PKGNAME}" ]; then
	echo "# No current package! set_pkg_state ${state}" >&2;
	return -1
    else
	if [ -n "${state}" ]; then
	    rm -f *.sourced *.prepped *.packaged *.installed *.pushed;
	fi;
	touch ${PKGNAME}.${state};
	return 0;
    fi;
}

get_pkg_state() {
    local state=$1;
    if [ -z "${PKGNAME}" ]; then
	echo "# No current package! get_pkg_state" >&2;
    else
	for state in sourced prepped packaged installed pushed; do
	    if [ -f "${PKGNAME}.${state}" ]; then
		echo ${state};
		return;
	    fi;
	done;
    fi;
}

mkpath () {
    local root=$1;
    local path=$2;
    local slash_root=${root}
    if [ "${path#/}" != "${path}" ]; then
	# starts with /
	echo ${path};
    else
	if [ ${root%/} = ${root} ]; then slash_root="${root}/"; fi
	if [ ${path#./} != ${path} ]; then path=${path#./}; fi;
	if [ ${path#../} != ${path} ]; then
	    path=${path#../};
	    slash_root=$(dirname ${slash_root});
	fi;
	echo ${slash_root}${path};
   fi;
}

make_dirs () {
    local path=$1;
    local dir=$(dirname $1);
    if [ -z "${path}" ]; then
	:;
    elif [ -d "${path}" ]; then
	:;
    else
	make_dirs ${dir};
	mkdir ${path};
    fi;
}

if [ "$(basename $0)" = "packaging.sh" ]; then
    echo "This file should be loaded (sourced) rather than run by itself";
    exit;
else
    echo "Loading packaging.sh into $$, arg1=$1" >>${PKGLOG}
fi;

if [ -z "${PACKAGING_ROOT}" ]; then
    if [ -f packaging.sh ]; then
	PACKAGING_ROOT=$(pwd);
    else
	script_dir=$(dirname $0)
	if [ -f ${script_dir}/packaging.sh ]; then
	    PACKAGING_ROOT=$(pwd);
	fi;
    fi;
    if [ -z "${PACKAGING_ROOT}" ]; then
	echo "Couldn't find packaging root directory";
	exit;
    else
	TOOLS=${PACKAGING_ROOT}/tools;
	PATH="${PATH}:${TOOLS}";
	STATE_ROOT=${PACKAGING_ROOT}/state;
	CONFIG_ROOT=${PACKAGING_ROOT}/sources;
	SOURCE_ROOT=${PACKAGING_ROOT}/src;
	WORK_ROOT=${PACKAGING_ROOT}/work;
	OUTPUT=${PACKAGING_ROOT}/output;
    fi;
fi;

if [ ! -d "${PACKAGING_ROOT}/output" ]; then
    mkdir "${PACKAGING_ROOT}/output";
fi;

if [ -f ${STATE_ROOT}/PKGNAME ]; then
    curpkg=$(cat ${STATE_ROOT}/PKGNAME);
fi;

# Handle defaults from the environment

if [ -n "${DISTRO}" ]; then
    :;
elif [ -f ${STATE_ROOT}/DISTRO ]; then
    DISTRO=$(cat ${STATE_ROOT}/DISTRO);
else
    DISTRO=$(lsb_release -s -c || echo release);
fi;

if [ -n "${ARCH}" ]; then
    :;
elif [ -f ${STATE_ROOT}/ARCH ]; then
    ARCH=$(cat ${STATE_ROOT}/ARCH);
else
    ARCH=$(uname -p || echo x86_64);
fi;

if [ -n "${DISTRIBUTOR}" ]; then
    :;
elif which lsb_release 1>/dev/null 2>/dev/null; then
    DISTRIBUTOR=$(lsb_release -i -s | sed - -e 's|Distributor ID:\t||g');
else
    DISTRIBUTOR=any
fi;

if [ -n "${REPO_SYSTEM}" ]; then
    :;
elif [ -f ${STATE_ROOT}/REPO_SYSTEM ]; then
    REPO_SYSTEM=$(cat ${STATE_ROOT}/REPO_SYSTEM);
elif [ -f defaults/REPO_SYSTEM ]; then
    REPO_SYSTEM=$(cat defaults/REPO_SYSTEM);
else case "${DISTRIBUTOR}" in
	 Fedora|Centos|RedHat|RedHatEnterprise)
	     REPO_SYSTEM="yum";
	     ;;
	 Debian|Mint|Ubuntu)
	     REPO_SYSTEM="apt";
	     ;;
	 Alpine)
	     REPO_SYSTEM="apk";
	     ;;
	 *)
	     REPO_SYSTEM="apt";
	     ;;
     esac;
fi;

if [ -n "${GIT_PROTOCOL}" ]; then
    :;
elif [ -f ${STATE_ROOT}/GIT_PROTOCOL ]; then
    GIT_PROTOCOL=$(cat ${STATE_ROOT}/GIT_PROTOCOL);
elif [ -f defaults/GIT_PROTOCOL ]; then
    GIT_PROTOCOL=$(cat defaults/GIT_PROTOCOL);
fi;

if [ -n "${DEFAULT_BRANCH}" ]; then
    echo ${DEFAULT_BRANCH} > defaults/BRANCH;
fi;

if [ -n "${DEFAULT_VARIANT}" ]; then
    echo ${DEFAULT_VARIANT} > defaults/VARIANT;
fi;

# This is all information which should come from getsource

get_state() {
    local file=$1;
    if [ -f ${file} ]; then
	cat ${file};
    else echo;
    fi;
}

import_state() {
    local dir=${1:-${STATE_ROOT}};
    if [ -f ${dir}/PKGNAME ]; then
	PKGNAME=$(cat ${dir}/PKGNAME);
    else PKGNAME=;
    fi;
    if [ -f ${dir}/BRANCH ]; then
	BRANCH=$(cat ${dir}/BRANCH);
    else BRANCH=;
    fi;
    if [ -f ${dir}/VERSION ]; then
	VERSION=$(cat ${dir}/VERSION);
    else VERSION=;
    fi;
    if [ -f ${dir}/BASE_VERSION ]; then
	BASE_VERSION=$(cat ${dir}/BASE_VERSION);
    else BASE_VERSION=${VERSION};
    fi;
    if [ -f ${dir}/FULL_VERSION ]; then
	FULL_VERSION=$(cat ${dir}/FULL_VERSION);
    else FULL_VERSION=${VERSION};
    fi;
    MAJOR_VERSION=$(echo $VERSION | cut -d. -f 1);
    MINOR_VERSION=$(echo $VERSION | cut -d. -f 2);
    RELEASE_VERSION=$(echo $VERSION | cut -d. -f 3);

    if [ -f ${STATE_ROOT}/VARIANT ]; then
	VARIANT=$(cat ${STATE_ROOT}/VARIANT);
    elif [ -f defaults/VARIANT ]; then
	VARIANT=$(cat defaults/VARIANT);
    else VARIANT=;
    fi;

    if [ -f ${dir}/LIBNAME ]; then
	LIBNAME=$(cat ${dir}/LIBNAME);
    fi;

    if [ -f ${dir}/STATUS ]; then
	STATUS=$(cat ${dir}/STATUS);
    else STATUS=stable;
    fi;

    if [ -f ${dir}/URGENCY ]; then
	URGENCY=$(cat ${dir}/URGENCY);
    else URGENCY=normal;
    fi;

    CODENAME=${DISTRO};

    if [ -n "${REPO}" ]; then
        :;
    elif [ -f "${dir}/REPO" ]; then
	REPO=$(cat "${dir}/REPO");
    elif [ -f "${CONFIG_ROOT}/repo" ]; then
	REPO=$(cat "${CONFIG_ROOT}/repo");
    else
	REPO=kno;
    fi;

    if [ -n "${REPOMAN}" ]; then
	:;
    elif [ -f "${dir}/REPOMAN" ]; then
	REPOMAN=$(cat "${dir}/REPOMAN");
    fi;
}
import_state;

# More repo information

resolve_repo() {
    local dir=${1:-${PACKAGING_ROOT}/repos};
    if [ -f "${dir}/${REPO}.${REPO_SYSTEM}" ]; then
        REPO_URL=$(cat "${dir}/${REPO}.${REPO_SYSTEM}");
    elif [ -f "${dir}/${REPO}" ]; then
        REPO_URL=$(cat "${dir}/${REPO}");
    elif [ -n "${USE_REPO_URL}" ]; then
        REPO_URL="${USE_REPO_URL}";
    fi;

    if [ -f "${dir}/${REPO}.${REPO_SYSTEM}.login" ]; then
        REPO_LOGIN=$(cat "${dir}/${REPO}.${REPO_SYSTEM}.login");
    elif [ -f "${dir}/${REPO}.login" ]; then
        REPO_LOGIN=$(cat "${dir}/${REPO}.login");
    elif [ -n "${USE_REPO_LOGIN}" ]; then
        REPO_LOGIN="${USE_REPO_LOGIN}";
    fi;

    if [ -n "${DISTRO}" ]; then
        REPO_URL=$(echo ${REPO_URL} | sed - -e "s/-@DISTRO@/-${DISTRO}/");
        REPO_URL=$(echo ${REPO_URL} | sed - -e "s|/@DISTRO@|/${DISTRO}|");
    else
        REPO_URL=$(echo ${REPO_URL} | sed - -e "s/-@DISTRO@/-universal/");
        REPO_URL=$(echo ${REPO_URL} | sed - -e "s|/@DISTRO@|/universal|");
    fi;
    if [ -n "${VARIANT}" ]; then
        REPO_URL=$(echo ${REPO_URL} | sed - -e "s/-@VARIANT@/-${VARIANT}/");
        REPO_URL=$(echo ${REPO_URL} | sed - -e "s|/@VARIANT@|/${VARIANT}|");
    else
        REPO_URL=$(echo ${REPO_URL} | sed - -e "s/-@VARIANT@//");
        REPO_URL=$(echo ${REPO_URL} | sed - -e "s|/@VARIANT@|/stable|");
    fi;
}
resolve_repo;

# Log files

if [ -z "${LOGFILE}" ]; then
    if [ -f defaults/${PKGNAME}.LOGFILE ]; then
	LOGFILE=$(cat defaults/${PKGNAME}.LOGFILE);
    elif [ -f defaults/LOGFILE ]; then
	LOGFILE=$(cat defaults/LOGFILE);
    fi;
fi;

# Information about KNO

if which knoconfig 2>/dev/null 1>/dev/null; then
    KNO_VERSION=$(knoconfig version);
    KNO_MAJOR=$(knoconfig major);
    KNO_MINOR=$(knoconfig minor);
elif [ -d src/kno/.git ]; then
    KNO_VERSION=$("cd" src/kno; u8_gitversion etc/base_version);
    KNO_MAJOR=$(echo ${KNO_VERSION} | cut - -d'.' -f1);
    KNO_MINOR=$(echo ${KNO_VERSION} | cut - -d'.' -f2);
else
    KNO_VERSION="2110.1.4";
    KNO_MAJOR="2110;"
    KNO_MINOR="1";
fi;

if [ -f ${STATE_ROOT}/GPGID ]; then
    GPGID=$(cat ${STATE_ROOT}/GPGID);
fi;

# Find the package tool

if [ -n "${PKGTOOL}" ]; then
    dbgmsg "PKGTOOL=${PKGTOOL}"
elif [ -f "${STATE_ROOT}/PKGTOOL" ]; then
    PKGTOOL=$(cat "${STATE_ROOT}/PKGTOOL");
else
    for probe in "${PACKAGING_ROOT}/defaults/${PKGNAME}/PKGTOOL" "${PACKAGING_ROOT}/defaults/PKGTOOL"; do
	if [ -z "${PKGTOOL}" ] && [ -f "${probe}" ]; then
	    PKGTOOL=$(cat "${probe}");
	fi;
    done;
    if [ -z "${PKGTOOL}" ] && [ -n "${DISTRIBUTOR}" ]; then
	case ${DISTRIBUTOR} in
	    Ubuntu|Debian)
		PKGTOOL=${PACKAGING_ROOT}/tools/debtool;
		;;
	    Fedora|RHEL|CENTOS|RedHat|RedHatEnterprise)
		PKGTOOL=${PACKAGING_ROOT}/tools/rpmtool;
		;;
	    Alpine)
		PKGTOOL=${PACKAGING_ROOT}/tools/apktool;
		;;
	    *)
		PKGTOOL=
		;;
	esac
	if [ -n "${PKGTOOL}" ]; then
	    echo ${PKGTOOL} > ${STATE_ROOT}/PKGTOOL;
	fi;
    fi;
fi;

TOOLNAME=${PKGTOOL##*/}

if [ -z "${TOOLNAME}" ]; then
    echo "No TOOLNAME";
elif [ "${TOOLNAME}" = "debtool" ]; then
    PKGINFO=debinfo
elif [ "${TOOLNAME}" = "rpmtool" ]; then
    PKGINFO=rpminfo
elif [ "${TOOLNAME}" = "apktool" ]; then
    PKGINFO=apkinfo
else
    PKGINFO=none
fi;

if [ -f ${STATE_ROOT}/OUTDIR ]; then OUTDIR=$(cat ${STATE_ROOT}/OUTDIR); fi;

dbgmsg "REPO HOST=${REPO} URL=${REPO_URL} REPO_LOGIN=${REPO_LOGIN}";

if [ -f ${STATE_ROOT}/GIT_NO_LFS ]; then
    GIT_NO_LFS=$(cat ${STATE_ROOT}/GIT_NO_LFS);
elif ! git lfs status 2>/dev/null 1>/dev/null; then
    GIT_NO_LFS=sorry;
    echo ${GIT_NO_LFS} > ${STATE_ROOT}/GIT_NO_LFS;
else
    unset GIT_NO_LFS
fi;

