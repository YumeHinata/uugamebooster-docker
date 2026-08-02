#!/bin/ash

readonly BOUND_CB="/etc/miio/bound.d"
readonly UNBOUND_CB="/etc/miio/unbound.d"
readonly MJAC_DID_FILE="/tmp/mjac_did"

gMethod=
gResult=
gParams=


bind_cb() {
	local code=

	code=$(echo "$1" | jsonfilter -e "$.code")

	if [ "$code" = "0" ]; then
		uci set miio_ot.ot.bound=1
		uci commit miio_ot

		if [ -d "$BOUND_CB" ]; then
			find "$BOUND_CB" -type f -exec sh -c 'sh $1 &' _ {} \;
		fi
	fi
}

unbind_cb() {
	local code=

	code=$(echo "$1" | jsonfilter -e "$.code")

	if [ "$code" = "0" ]; then
		uci set miio_ot.ot.bound=0
		uci set miio_ot.ot.unbind=1
		uci commit miio_ot

		if [ -d "$UNBOUND_CB" ]; then
			find "$UNBOUND_CB" -type f -exec sh -c 'sh $1 &' _ {} \;
		fi

	fi
}

mjac_did_cb() {
	[ ! -e "$MJAC_DID_FILE" ] &&  {
		[ -n "$1" -a "$1" != "0" ] && echo "$1" > "$MJAC_DID_FILE"
	}
}

usage() {
	cat <<-EOF
		Usage: $0 OPTION...
		MIIO Response callback entry

		  -m      Callback method
		  -r      Respose result
	EOF
}

while getopts "m:r:p:h" opt; do
	case "${opt}" in
	m)
		gMethod=${OPTARG}
		;;
	r)
		gResult=${OPTARG}
		;;
	p)
		gParams=${OPTARG}
		;;
	h)
		usage
		exit
		;;
	\?)
		usage >&2
		exit 1
		;;
	esac
done
shift $((OPTIND - 1))

if [ -z "$gMethod" ]; then
	printf "Method not specified!\n" >&2
	exit 2
fi

case "$gMethod" in
"_sync.device_bind")
	bind_cb "$gResult"
	;;
"_sync.device_unbind")
	unbind_cb "$gResult"
	;;
"_sync.mjac_did")
	mjac_did_cb "$gParams"
	;;
\?)
	printf "Method not supported!\n" >&2
	exit 3
	;;
esac
