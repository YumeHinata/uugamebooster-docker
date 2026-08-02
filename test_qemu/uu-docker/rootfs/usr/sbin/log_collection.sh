#!/bin/ash

readonly DIAG_ZIP_FILE=/tmp/log.tar.gz

readonly DIAG_STAT_SRC=/etc/diag_info/stat
readonly DIAG_STAT_DST=/var/diag_info/stat

readonly DIAG_CFG_ORI=/etc/config
readonly DIAG_CFG_SRC=/etc/diag_info/cfg
readonly DIAG_CFG_DST=/var/diag_info/cfg

readonly DIAG_LOG_SRC=/etc/diag_info/log
readonly DIAG_LOG_DST=/var/diag_info/log

readonly DIAG_TMP_SRC=/etc/diag_info/tmp
readonly DIAG_TMP_DST=/var/diag_info

get_cfg() {
	local _filename=

	mkdir -p "$DIAG_CFG_DST"

	find ${DIAG_CFG_SRC} -type f |
		while read -r _filename; do
			if [ ! -e "${DIAG_CFG_ORI}/${_filename##*/}" ]; then
				continue
			fi

			sed -f "$_filename" "${DIAG_CFG_ORI}/${_filename##*/}" \
				| tee "${DIAG_CFG_DST}/${_filename##*/}" >/dev/null
		done
}

get_stat() {
	local _stat_res=
	local _filename=

	mkdir -p "$DIAG_STAT_DST"

	find ${DIAG_STAT_SRC} -type f |
		while read -r _filename; do
			_stat_res=$(echo "${_filename}"|grep -oE '[^/]+/[^/]+$'|tr '/' '-'|sed 's|.sh$|.txt|')
			sh "${_filename}" > "${DIAG_STAT_DST}/${_stat_res}"
		done
}

get_log() {
	local _src=
	local _dst=
	local _line=
	local _file=

	mkdir -p "$DIAG_LOG_DST"

	while read -r _line; do
		_src=$(echo "$_line"|cut -d, -f1)
		_dst=$(echo "$_line"|cut -d, -f2)

		mkdir "$DIAG_LOG_DST/$_dst"
		find "$_src" -maxdepth 1 -type f |
			while read -r _file; do
				ln -s "$_file" "$DIAG_LOG_DST/$_dst/${_file##*/}"
			done
	done < "$DIAG_LOG_SRC"
}

get_tmp() {
	local _file=
	local _name=

	while read -r _name; do
		find "${_name%/*}" -maxdepth 1 -name "${_name##*/}" |
			while read -r _file; do
				mkdir -p "${DIAG_TMP_DST}${_file%/*}"
				ln -s "$_file" "${DIAG_TMP_DST}$_file"
			done
	done < "$DIAG_TMP_SRC"
}

rm -rf "$DIAG_ZIP_FILE" "${DIAG_STAT_DST%/*}"

get_cfg
get_stat
get_log
get_tmp

tar -hczf "$DIAG_ZIP_FILE" -C "${DIAG_STAT_DST%/*}" ./
