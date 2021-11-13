export PACKAGING_ROOT STATE_ROOT PATH
export PKGNAME VERSION REL_VERSION BRANCH CHANNEL FULL_VERSION
export BASE_VERSION MAJOR_VERSION MINOR_VERSION
export REPO_URL REPO_LOGIN REPO_CURLOPTS
export DISTRO STATUS URGENCY

if [ "$(basename $0)" = "packaging.sh" ]; then
    echo "This file should be loaded (sourced) rather than run by itself";
    exit;
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

if [ $# -gt 0 ]  && [ -z "${NO_PKGNAME}" ]; then
    pkgname=$1;
    if [ ! -z "${PKGNAME}" ]; then
	if [ "${pkgname}" != "${PKGNAME}" ]; then
	    echo "Currently buildling '${PKGNAME}' not '$[pkgname}'";
	    exit 2;
	fi;
    elif [ ! -f sources/${pkgname} ]; then
	echo "No source information for '${pkgname}'";
	exit 2;
    else
	echo "${pkgname}" > ${STATE_ROOT}/PKGNAME;
    fi;
fi;

if [ -f ${STATE_ROOT}/PKGNAME ]; then
    PKGNAME=$(cat ${STATE_ROOT}/PKGNAME);
fi;

if [ -f ${STATE_ROOT}/DISTRO ]; then
    DISTRO=$(cat ${STATE_ROOT}/DISTRO);
else
    DISTRO=$(lsb_release -s -c || echo release);

fi;

if [ -f ${STATE_ROOT}/CHANNEL ]; then
    CHANNEL=$(cat ${STATE_ROOT}/CHANNEL);
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

if [ -f ${STATE_ROOT}/VERSION ]; then
    VERSION=$(cat ${STATE_ROOT}/VERSION);
fi;

if [ -f ${STATE_ROOT}/REL_VERSION ]; then
    REL_VERSION=$(cat ${STATE_ROOT}/REL_VERSION);
elif [ -f ${STATE_ROOT}/VERSION ]; then
    REL_VERSION=${VERSION%-*}
fi;

if [ -f ${STATE_ROOT}/BRANCH ]; then
    BRANCH=$(cat ${STATE_ROOT}/BRANCH);
fi;

if [ -f ${STATE_ROOT}/FULL_VERSION ]; then
    FULL_VERSION=$(cat ${STATE_ROOT}/FULL_VERSION);
else
    FULL_VERSION=${VERSION};
fi;

if [ -f ${STATE_ROOT}/MAJOR_VERSION ]; then
    MAJOR_VERSION=$(cat ${STATE_ROOT}/MAJOR_VERSION);
else
    MAJOR_VERSION=$(echo $VERSION | cut -d'.' -f 1);
fi;

if [ -f ${STATE_ROOT}/MINOR_VERSION ]; then
    MINOR_VERSION=$(cat ${STATE_ROOT}/MINOR_VERSION || echo $version);
else
    MINOR_VERSION=$(echo $VERSION | cut -d'.' -f 2);
fi;

if [ -f ${STATE_ROOT}/BASE_VERSION ]; then
    BASE_VERSION=$(cat ${STATE_ROOT}/BASE_VERSION);
else
    BASE_VERSION=${VERSION}
fi;

# Other packaging parameters

if [ -f ${STATE_ROOT}/STATUS ]; then
    STATUS=$(cat ${STATE_ROOT}/STATUS);
else
    STATUS=stable;
fi;
if [ -f ${STATE_ROOT}/URGENCY ]; then
    URGENCY=$(cat ${STATE_ROOT}/URGENCY);
else
    URGENCY=normal
fi;

if [ -f ${STATE_ROOT}/GPGID ]; then
    GPGID=$(cat ${STATE_ROOT}/GPGID);
fi;

# Getting information about repos

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
    REPO_LOGIN=$(cat ${STATE_ROOT}/REPO_LOGIN 2>/dev/null || cat repos/default-login 2>/dev/null || echo)
    REPO_CURL_OPTS=$(cat ${STATE_ROOT}/REPO_CURLOPTS 2>/dev/null || cat repos/default-curlopts 2>/dev/null || echo)
fi;

if [ -f ${STATE_ROOT}/OUTDIR ]; then
    OUTDIR=$(cat ${STATE_ROOT}/OUTDIR);
fi;

logmsg () {
    echo "pkg: $1" >&2;
}
