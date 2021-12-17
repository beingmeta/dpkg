#!/bin/sh

export PACKAGING_ROOT STATE_ROOT PATH LOGFILE LIBNAME TOOLS OUTPUT
export PKGNAME VERSION REL_VERSION BRANCH CHANNEL FULL_VERSION
export BASE_VERSION MAJOR_VERSION MINOR_VERSION RELEASE_VERSION
export KNO_VERSION KNO_MAJOR KNO_MINOR
export REPOMAN REPO_SYSTEM REPO_HOST REPO_URL REPO_LOGIN
export CODENAME DISTRO STATUS ARCH URGENCY

PKGLOG=${PKGLOG:-/dev/null}

logmsg () {
    echo "pkg ($$@$(pwd)) $1" >&2;
}

dbgmsg () {
    if [ -n "${DEBUGGING}" ]; then
	echo "pkgdebug ($$@$(pwd)) $1" >&2;
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

if [ "$(basename $0)" = "packaging.sh" ]; then
    echo "This file should be loaded (sourced) rather than run by itself";
    exit;
else
    echo "Loading packaging.sh into $$, arg1=$1" >${PKGLOG}
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
	fallback=${PACKAGING_ROOT}/fallback;
	PATH="${PATH}:${fallback}";
	STATE_ROOT=${PACKAGING_ROOT}/state;
	TOOLS=${PACKAGING_ROOT}/tools;
	OUTPUT=${PACKAGING_ROOT}/output;
    fi;
fi;

if [ -f state/PKGNAME ]; then
    curpkg=$(cat state/PKGNAME);
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

DISTRIBUTOR=$(lsb_release -i -s | sed - -e 's|Distributor ID:\t||g');

if [ -n "${REPO_SYSTEM}" ]; then
    :;
elif [ -f ${STATE_ROOT}/REPO_SYSTEM ]; then
    REPO_SYSTEM=$(cat ${STATE_ROOT}/REPO_SYSTEM);
elif [ -f defaults/REPO_SYSTEM ]; then
    REPO_SYSTEM=$(cat defaults/REPO_SYSTEM);
else case "${DISTRIBUTOR}" in
	 Fedora|Centos)
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

if [ -n "${DEFAULT_BRANCH}" ]; then
    echo ${DEFAULT_BRANCH} > defaults/BRANCH;
fi;

if [ -n "${DEFAULT_CHANNEL}" ]; then
    echo ${DEFAULT_CHANNEL} > defaults/CHANNEL;
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
    if [ -f ${STATE_ROOT}/CHANNEL ]; then
	CHANNEL=$(cat ${STATE_ROOT}/CHANNEL);
    elif [ "${BRANCH}" != "${BRANCH%-test}" ]; then
	CHANNEL="${BRANCH%-test}";
    elif [ "${BRANCH}" = "edge" ] || [ "${BRANCH}" = "prod" ] || [ "${BRANCH}" = "LTS" ]; then
	CHANNEL="${BRANCH}";
    else CHANNEL=;
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
    if [ -f ${dir}/CHANNEL ]; then
	CHANNEL=$(cat ${dir}/CHANNEL);
    else CHANNEL=;
    fi;
    CODENAME=${DISTRO};
    if [ -n "${CHANNEL}" ]; then CODENAME=${CODENAME}-${CHANNEL}; fi;
}
import_state;


# These are used to probe for specific settings
PROBES=
push_probe() {
    local probe=$1
    if [ -n "${probe}" ] &&
	   [ "${probe}" = "${probe%.}" ] &&
	   [ "${probe}" = "${probe%..*}" ]; then
	if [ -z "${PROBES}" ]; then
	    PROBES="${probe}";
	else PROBES="${probe} ${PROBES}";
	fi;
    fi;
}
push_probe "${PKGNAME}";
push_probe "${PKGNAME}.${DISTRO}.${CHANNEL}";
push_probe "${PKGNAME}.${CHANNEL}";
push_probe "${PKGNAME}.${DISTRO}";

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
    echo "PKGTOOL=${PKGTOOL}";
elif [ -f "${STATE_ROOT}/PKGTOOL" ]; then
    PKGTOOL=$(cat "${STATE_ROOT}/PKGTOOL");
else
    for probe in "${PACKAGING_ROOT}/defaults/${PKGNAME}/PKGTOOL" "${PACKAGING_ROOT}/defaults/PKGTOOL"; do
	if [ -z "${PKGTOOL}" ] && [ -f "${probe}" ]; then
	    PKGTOOL=$(cat "${probe}");
	fi;
    done;
    if [ -z "${PKGTOOL}" ] && which lsb_release 1>/dev/null 2>/dev/null; then
	case ${DISTRIBUTOR} in
	    Ubuntu|Debian)
		PKGTOOL=${PACKAGING_ROOT}/tools/debtool;
		;;
	    Fedora|RHEL|CENTOS)
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

# Getting information about repos

if [ -f "${STATE_ROOT}/REPOMAN" ]; then
    REPOMAN=$(cat "${STATE_ROOT}/REPOMAN");
elif [ -f "defaults/${PKGNAME}/REPOMAN" ]; then
    REPOMAN=$(cat "defaults/${PKGNAME}/REPOMAN");
elif [ -f "defaults/REPOMAN" ]; then
    REPOMAN=$(cat "defaults/REPOMAN");
else
    REPOMAN="Repository Manager <repoman@beingmeta.com>"
fi;

if [ -n "${REPO_HOST}" ]; then
    # If we already have an URL in the environment assume everything
    # else has been set appropriately
    :
else
    for probe in ${PROBES}; do
	if [ -z "${REPO_HOST}" ] && [ -f repos/${probe} ]; then
	    REPO_HOST=$(cat repos/${probe});
	    if [ -f repos/${probe}-login ]; then
		REPO_LOGIN=$(cat repos/${probe}-login ); fi;
	fi;
    done;
fi;
		   
if [ -z "${REPO_HOST}" ] && [ -f repos/default ]; then
    REPO_HOST=$(cat repos/default);
fi;

if [ -f repos//default-login ]; then
    REPO_LOGIN=$(cat repos/default-login);
fi;

if [ -z "${REPO_HOST}" ]; then
    echo "Warning: No REPO_HOST";
else
    if [ -f repos/${REPO_HOST}-login ]; then
	REPO_LOGIN=$(cat "repos/${REPO_URL}-login");
    fi;
    if [ -f "repos/${REPO_HOST}.${REPO_SYSTEM}" ]; then
	REPO_URL=$(cat "repos/${REPO_HOST}.${REPO_SYSTEM}");
	if [ -f "repos/${REPO_HOST}.${REPO_SYSTEM}-login" ]; then
	    REPO_LOGIN=$(cat "repos/${REPO_URL}.${REPO_SYSTEM}-login"); fi;
    elif [ -f "repos/${REPO_HOST}" ]; then
	REPO_URL=$(cat "repos/${REPO_HOST}.${REPO_SYSTEM}");
    else
	REPO_URL="${REPO_HOST}";
    fi;	
fi;

if [ -n "${DISTRO}" ]; then
    REPO_URL=$(echo ${REPO_URL} | sed - -e "s/-@DISTRO@/-${DISTRO}/");
    REPO_URL=$(echo ${REPO_URL} | sed - -e "s|/@DISTRO@|/${DISTRO}|");
else
    REPO_URL=$(echo ${REPO_URL} | sed - -e "s/-@DISTRO@/-universal/");
    REPO_URL=$(echo ${REPO_URL} | sed - -e "s|/@DISTRO@|/universal|");
fi;

if [ -n "${CHANNEL}" ]; then
    REPO_URL=$(echo ${REPO_URL} | sed - -e "s/-@CHANNEL@/-${CHANNEL}/");
    REPO_URL=$(echo ${REPO_URL} | sed - -e "s|/@CHANNEL@|/${CHANNEL}|");
else
    REPO_URL=$(echo ${REPO_URL} | sed - -e "s/-@CHANNEL@//");
    REPO_URL=$(echo ${REPO_URL} | sed - -e "s|/@CHANNEL@|/stable|");
fi;

if [ -f ${STATE_ROOT}/OUTDIR ]; then OUTDIR=$(cat ${STATE_ROOT}/OUTDIR); fi;

if [ -f ${STATE_ROOT}/GIT_NO_LFS ]; then
    GIT_NO_LFS=$(cat ${STATE_ROOT}/GIT_NO_LFS);
elif ! git lfs status 2>/dev/null 1>/dev/null; then
    GIT_NO_LFS=sorry;
    echo ${GIT_NO_LFS} > ${STATE_ROOT}/GIT_NO_LFS;
else
    unset GIT_NO_LFS
fi;
