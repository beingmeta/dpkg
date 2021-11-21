#!/bin/sh

export PACKAGING_ROOT STATE_ROOT PATH LOGFILE LIBNAME
export PKGNAME VERSION REL_VERSION BRANCH CHANNEL FULL_VERSION
export BASE_VERSION MAJOR_VERSION MINOR_VERSION RELEASE_VERSION
export KNO_VERSION KNO_MAJOR KNO_MINOR
export REPOMAN REPO_URL REPO_LOGIN REPO_CURLOPTS
export CODENAME DISTRO STATUS ARCH URGENCY

PKGLOG=${PKGLOG:-/dev/null}

logmsg () {
    echo "pkg: $1" >&2;
}

mkpath () {
    local root=$1;
    local path=$2;
    local slash_root=${root}
    if [ "${path#/}" != "${path}" ]; then
	# starts with /
	echo ${path};
    else
	if [ ${root%/} == ${root} ]; then slash_root="${root}/"; fi
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
    fi;
fi;

if [ -f state/PKGNAME ]; then
    curpkg=$(cat state/PKGNAME);
fi;

if [ $# -gt 0 ]  && [ -z "${NO_PKGNAME}" ]; then
    pkgname=$1;
    stripped="${pkgname%#*}"
    if [ "${stripped}" != "${pkgname}" ]; then
	branch="${pkgname#*#}";
	pkgname=${stripped}
    fi;
    if [ -f "sources/${pkgname}" ]; then
	if [ ! -f ${STATE_ROOT}/PKGNAME ]; then
	    curpkg=$(cat ${STATE_ROOT}/PKGNAME);
	else curpkg=; fi
	if [ "${curpkg}" == "${pkgname}" ]; then
	    PKGNAME=${curpkg};
	else
	    if [ -z "${curpkg}" ]; then
		echo "Building ${pkgname}";
	    else
		echo "Switching from ${curpkg} to ${pkgname}";
	    fi;
	    PKGNAME=${pkgname};
	    rm -f ${STATE_ROOT}/*;
	    echo "${pkgname}" > ${STATE_ROOT}/PKGNAME;
	    if [ -n "${branch}" ]; then echo "${branch}" > ${STATE_ROOT}/BRANCH; fi;
	    cp ${PACKAGING_ROOT}/defaults/* ${STATE_ROOT} 2> /dev/null;
	    if [ -d ${PACKAGING_ROOT}/defaults/${pkgname} ]; then
		cp ${PACKAGING_ROOT}/defaults/${pkgname}/* ${STATE_ROOT} 2> /dev/null;
	    fi;
	fi;
	# Discard the package name (usually)
	if [ -z "${KEEP_PKG_ARG}" ]; then shift; fi;
    fi;
fi;

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

# This is all information which should come from getsource

get_state() {
    local file=$1;
    if [ -f ${file} ]; then
	$(cat ${file});
    else echo; fi
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
    if [ -f ${STATE_ROOT}/DISTRO ]; then
	DISTRO=$(cat ${STATE_ROOT}/DISTRO);
    else
	DISTRO=$(lsb_release -s -c || echo release);
    fi;
    if [ -f ${STATE_ROOT}/ARCH ]; then
	ARCH=$(cat ${STATE_ROOT}/ARCH);
    else
	ARCH=$(uname -p || echo x86_64);
    fi;
    if [ -f ${STATE_ROOT}/CHANNEL ]; then
	CHANNEL=$(cat ${STATE_ROOT}/CHANNEL);
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
	release_type="$(lsb_release -s -i)";
	case ${release_type} in
	    Ubuntu|Debian)
		PKGTOOL=${PACKAGING_ROOT}/tools/debtool;
		;;
	    RHEL|CENTOS)
		PKGTOOL=${PACKAGING_ROOT}/tools/rpmtool;
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

if [ -n "${REPO_URL}" ]; then
    # If we already have an URL in the environment assume everything
    # else has been set appropriately
    :
elif [ -f ${STATE_ROOT}/REPO_URL ]; then
    REPO_URL=$(cat ${STATE_ROOT}/REPO_URL);
    REPO_LOGIN=$(cat ${STATE_ROOT}/REPO_LOGIN 2>/dev/null || \
		     cat repos/default-login 2>/dev/null || \
		     echo);
    REPO_CURLOPTS=$(cat ${STATE_ROOT}/REPO_CURLOPTS 2>/dev/null || \
			cat repos/default-curlopts 2>/dev/null || \
			echo);
else
    for probe in ${PROBES}; do
	if [ -z "${REPO_URL}" ] && [ -f repos/${probe} ]; then
	    REPO_URL=$(cat repos/${probe});
	    if [ -f repos/${probe}-login ]; then
		REPO_LOGIN=$(cat repos/${probe}-login ); fi;
	    if [ -f repos/${probe}-curl ]; then
		REPO_CURL_OPTS=$(cat repos/${probe}-curlopts); fi;
	fi;
    done;
fi;
		   
if [ -z "${REPO_URL}" ] && [ -f repos/default ]; then
    REPO_URL=$(cat repos/default);
    REPO_LOGIN=$(cat ${STATE_ROOT}/REPO_LOGIN 2>/dev/null || cat repos/default-login 2>/dev/null || echo);
    REPO_CURL_OPTS=$(cat ${STATE_ROOT}/REPO_CURLOPTS 2>/dev/null || cat repos/default-curlopts 2>/dev/null || echo);
fi;

if [ -n "${DISTRO}" ]; then
    REPO_URL=$(echo ${REPO_URL} | sed - -e "s/@DISTRO@/-${DISTRO}/");
else
    REPO_URL=$(echo ${REPO_URL} | sed - -e "s/@CHANNEL@//");
fi;

if [ -n "${CHANNEL}" ]; then
    REPO_URL=$(echo ${REPO_URL} | sed - -e "s/@CHANNEL@/-${CHANNEL}/");
else
    REPO_URL=$(echo ${REPO_URL} | sed - -e "s/@CHANNEL@//");
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
