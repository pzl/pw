#!/usr/bin/env bash

# Copyright (C) 2012 - 2014 Jason A. Donenfeld <Jason@zx2c4.com>. All Rights Reserved.
# Copyright (C) 2016 Dan Panzarella <alsoelp@gmail.com>.
# This file is licensed under the GPLv2. Please see LICENSE for more information.

umask "${PASSWORD_STORE_UMASK:-077}"
set -o pipefail
#set -x
set -e

GPG_OPTS=( $PW_GPG_OPTS "--quiet" "--yes" "--compress-algo=none" "--no-encrypt-to" )
GPG="gpg"
export GPG_TTY="${GPG_TTY:-$(tty 2>/dev/null)}"
which gpg2 &>/dev/null && GPG="gpg2"
[[ -n $GPG_AGENT_INFO || $GPG == "gpg2" ]] && GPG_OPTS+=( "--batch" )

CLIP_TIME="${PASSWORD_STORE_CLIP_TIME:-5}"
GENERATED_LENGTH="${PASSWORD_STORE_GENERATED_LENGTH:-25}"


FLNAME="pw"
TMPDIR="/dev/shm"
ENCDIR="${XDG_DATA_HOME:-$HOME/.local/share}"
EDITOR="${EDITOR:-vi}"


#
# BEGIN helper functions
#

approve() {
	local response
	if [ -t 0 ]; then
		read -r -p "$1 [y/N] " response
		[[ $response == [yY] ]] || return 1
		return 0
	else
		response="$(pinentry-gtk-2 <<EOD
setdesc $1
settitle pw
setok Yes
setcancel No
confirm
EOD
)"
		echo "$response" | grep "^ERR.*cancelled" && return 1
		return 0
	fi
}

say() {
	if [ -t 0 ]; then
		echo "$@"
	else
		pinentry-gtk-2 <<EOD
setdesc $@
settitle pw
message
EOD
	fi
}

die() {
	if [ -t 0 ]; then
		echo "$@" >&2
	else
		pinentry-gtk-2 <<EOD
setdesc $@
settitle pw error
message
EOD
	fi
	cleanup
	exit 1
}

askkey() {
	if [ -t 0 ]; then
		read -s -p "$1: " USER_PW || return 1
		printf "\n"
		#echo -ne "\033[1G\033[2K" #erases pass line
	else
		local answers
		answers="$( pinentry-gnome3 <<EOD
setdesc $1
setprompt pass:
settitle pw
setok OK
setcancel Cancel
getpin
EOD
)"
		echo "$answers" | grep "^ERR" && return 1
		USER_PW="$( echo "$answers" | grep "^D " | awk '{print $2}' )"
	fi
}
dblask() {
	if [ -t 0 ]; then
		local pass repeated
		read -s -p "$1: " pass || return 1
		printf "\n"
		read -s -p "Repeat: " repeated || return 1
		printf "\n"

		if [[ $pass == "$repeated" ]]; then
			USER_PW="$pass"
		else
			return 1
		fi
	else
		local answers
		answers="$( pinentry-gnome3 <<EOD
setdesc $1
setprompt pass:
settitle pw
setok OK
setcancel Cancel
setrepeat
getpin
EOD
)"
		grep "^ERR" <<< "$answers" && return 1
		USER_PW="$( echo "$answers" | grep "^D " | awk '{print $2}' )"
	fi	
}

decrypt() {
	[[ -d "${TMPDIR}/${FLNAME}" ]] && return 0 #already decrypted from previous
	[[ -f "${ENCDIR}/${FLNAME}" ]] || die "Error: no encrypted library found. Create entries first"
	file -b "${ENCDIR}/${FLNAME}" | grep "GPG.*encrypted" >/dev/null 2>&1 || die "Error: library was not encrypted"

	askkey "Enter decryption key" || die "Decryption key required"
	gpg -d  --pinentry-mode loopback --passphrase "$USER_PW" "${ENCDIR}/${FLNAME}" 2>/dev/null | tar -C "${TMPDIR}" -xj 2>/dev/null || die "bad password"
}

encrypt() {
	[[ -d "${TMPDIR}/${FLNAME}" ]] || die "Error: no information to encrypt"

	while [[ -z "$USER_PW" ]]; do
		dblask "Enter new master encryption key" || say "key required"
	done
	tar -C "${TMPDIR}" -cj "${FLNAME}" | gpg -c "${GPG_OPTS[@]}" -o "${ENCDIR}/${FLNAME}" --pinentry-mode loopback --passphrase "$USER_PW"
	cleanup
}

createlib() {
	dblask "Enter new master encryption key" || die "key required"
	mkdir -p "${TMPDIR}/${FLNAME}"
}

cleanup() {
	[[ -d "${TMPDIR}/${FLNAME}" ]] || exit 0
	find "${TMPDIR}/${FLNAME}" -type f -exec shred -fzu {} +
	rm -rf "${TMPDIR}/${FLNAME}"
}

check_sneaky_paths() {
	local path
	for path in "$@"; do
		if [[ $path =~ /\.\.$ || $path =~ ^\.\./ || $path =~ /\.\./ || $path =~ ^\.\.$ ]]; then
			die "Error: You've attempted to pass a sneaky path to pass. Go home."
		fi
	done
}

#
# END helper functions
#

#
# BEGIN platform definable
#

clip() {
	# This base64 business is because bash cannot store binary data in a shell
	# variable. Specifically, it cannot store nulls nor (non-trivally) store
	# trailing new lines.
	local sleep_argv0="password store sleep on display $DISPLAY"
	pkill -f "^$sleep_argv0" 2>/dev/null && sleep 0.5
	local before="$(xclip -o -selection clipboard 2>/dev/null | base64)"
	echo -n "$1" | xclip -selection clipboard || die "Error: Could not copy data to the clipboard"
	(
		( exec -a "$sleep_argv0" sleep "$CLIP_TIME" )
		local now="$(xclip -o -selection clipboard | base64)"
		[[ $now != $(echo -n "$1" | base64) ]] && before="$now"
		echo "$before" | base64 -d | xclip -selection clipboard
	) 2>/dev/null & disown
	if [ -t 0 ]; then
		echo "Copied $2 to clipboard. Will clear in $CLIP_TIME seconds."
	else
		notify-send "pw" "Copied $2 to clipboard. Will clear in $CLIP_TIME seconds."
	fi
}

#
# END platform definable
#


#
# BEGIN subcommand functions
#

cmd_version() {
	echo "pw v1.7"
}

cmd_usage() {
	cmd_version
	echo
	cat <<-_EOF
	Usage:
	    $PROGRAM [ls] [subfolder]
	        List passwords.
	    $PROGRAM find pass-names...
	    	List passwords that match pass-names.
	    $PROGRAM [show] [--clip[=line-number],-c[line-number]] pass-name
	        Show existing password and optionally put it on the clipboard.
	        If put on the clipboard, it will be cleared in $CLIP_TIME seconds.
	    $PROGRAM grep search-string
	        Search for password files containing search-string when decrypted.
	    $PROGRAM insert [--echo,-e | --multiline,-m] [--force,-f] pass-name
	        Insert new password. Optionally, echo the password back to the console
	        during entry. Or, optionally, the entry may be multiline. Prompt before
	        overwriting existing password unless forced.
	    $PROGRAM edit pass-name
	        Insert a new password or edit an existing password using ${EDITOR:-vi}.
	    $PROGRAM generate [--no-symbols,-n] [--clip,-c] [--in-place,-i | --force,-f] pass-name [pass-length]
	        Generate a new password of pass-length (or $GENERATED_LENGTH if unspecified) with optionally no symbols.
	        Optionally put it on the clipboard and clear board after $CLIP_TIME seconds.
	        Prompt before overwriting existing password unless forced.
	        Optionally replace only the first line of an existing file with a new password.
	    $PROGRAM rm [--recursive,-r] [--force,-f] pass-name
	        Remove existing password or directory, optionally forcefully.
	    $PROGRAM mv [--force,-f] old-path new-path
	        Renames or moves old-path to new-path, optionally forcefully
	    $PROGRAM cp [--force,-f] old-path new-path
	        Copies old-path to new-path, optionally forcefully
	    $PROGRAM help
	        Show this text.
	    $PROGRAM version
	        Show version information.

	More information may be found in the pass(1) man page.
	_EOF
}

cmd_list() {
	local path="$1"
	check_sneaky_paths "$path"
	decrypt
	tree -C -l --noreport "${TMPDIR}/${FLNAME}/${path}" | tail -n +2 | sed -E 's/\.txt(\x1B\[[0-9]+m)?( ->|$)/\1\2/g' #remove .txt at end of line, but keep colors
}

cmd_show() {
	local opts clip_location clip=0
	opts="$(getopt -o c:: -l clip:: -n "$PROGRAM" -- "$@")"
	local err=$?
	eval set -- "$opts"
	while true; do case $1 in
		-c|--clip) clip=1; clip_location="${2:-1}"; shift 2 ;;
		--) shift; break ;;
	esac done
	clip_location="${clip_location:-1}"

	[[ $err -ne 0 ]] && die "Usage: $PROGRAM $COMMAND [--clip[=line-number],-c[line-number]] [pass-name]"

	local path="$1"
	local passfile="${TMPDIR}/${FLNAME}/$path.txt"
	check_sneaky_paths "$path"

	decrypt
	if [[ -d ${passfile%.txt} ]]; then # "show" a directory by listing contents
		COMMAND="list"
		cmd_list "$path"
	elif [[ -f $passfile ]]; then
		if [[ $clip -eq 0 && -t 0 ]]; then
			cat "$passfile"
		else
			[[ $clip_location =~ ^[0-9]+$ ]] || die "Clip location '$clip_location' is not a number."
			local pass="$(tail -n +${clip_location} "$passfile" | head -n 1)"
			[[ -n $pass ]] || die "There is no password to put on the clipboard at line ${clip_location}."
			clip "$pass" "$path"
		fi
	elif [[ -d $PREFIX/$path ]]; then
		cmd_list "$path"
	else
		die "Error: $path was not found."
	fi
}

cmd_find() {
	[[ -z "$@" ]] && die "Usage: $PROGRAM $COMMAND pass-names..."
	decrypt
	IFS="," eval 'echo "Search Terms: $*"'
	local terms="*$(printf '%s*|*' "$@")"
	tree -C -l --noreport -P "${terms%|*}" --prune --matchdirs --ignore-case "${TMPDIR}/${FLNAME}" | tail -n +2 | sed -E 's/\.txt(\x1B\[[0-9]+m)?( ->|$)/\1\2/g'
}

cmd_grep() {
	[[ $# -ne 1 ]] && die "Usage: $PROGRAM $COMMAND search-string"
	decrypt
	grep --color=always -H -nr "$1" "${TMPDIR}/${FLNAME}" | sed "s@${TMPDIR}/${FLNAME}/@@g" # strip out leading 
}

cmd_insert() {
	if [ ! -f "${ENCDIR}/${FLNAME}" ]; then
		if approve "password library not found. Create a new one?"; then
			createlib
		else
			exit 1
		fi
	else
		decrypt
	fi

	local opts multiline=0 force=0
	opts="$(getopt -o mf -l multiline,force -n "$PROGRAM" -- "$@")"
	local err=$?
	eval set -- "$opts"
	while true; do case $1 in
		-m|--multiline) multiline=1; shift ;;
		-f|--force) force=1; shift ;;
		--) shift; break ;;
	esac done

	[[ $err -ne 0 || $# -ne 1 ]] && die "Usage: $PROGRAM $COMMAND [--multiline,-m] [--force,-f] pass-name"
	local path="${1%/}"
	local passfile="${TMPDIR}/${FLNAME}/${path}.txt"
	check_sneaky_paths "$path"

	if [[ $force -eq 0 && -e $passfile ]]; then
		approve "An entry already exists for $path. Overwrite it?" || exit 1
	fi

	mkdir -p -v "${TMPDIR}/${FLNAME}/$(dirname "$path")"

	if [[ $multiline -eq 1 ]]; then
		$EDITOR "$passfile"
		if [[ -s $passfile ]]; then
			encrypt
		elif [[ -f $passfile ]]; then
			die "Not saved. Empty password"
		else
			die "Not saved. Aborted by user"
		fi
	else
		local passcache gotpass
		[[ -n "$USER_PW" ]] && passcache="$USER_PW"
		if askkey "Enter password for $path"; then
			echo "$USER_PW" > "$passfile"
			[[ -n "$passcache" ]] && USER_PW="$passcache"
			encrypt
		else
			[[ -n "$passcache" ]] && USER_PW="$passcache"
			die "Empty password. Aborted."
		fi
	fi
}

cmd_edit() {
	[[ $# -ne 1 ]] && die "Usage: $PROGRAM $COMMAND pass-name"

	local path="${1%/}"
	check_sneaky_paths "$path"

	decrypt
	local passfile="${TMPDIR}/${FLNAME}/${path}.txt"
	[[ -f $passfile ]] || die "${path} not found"
	$EDITOR $passfile

	if [[ -s $passfile ]]; then
		encrypt
	elif [[ -f $passfile ]]; then
		die "${path} cannot have empty password. Remove instead. Aborting edit"
	else
		die "Cannot remove ${path} this way. Use rm command. Aborting"
	fi
}

cmd_generate() {
	local opts clip=0 force=0 symbols="-y" inplace=0
	opts="$(getopt -o ncif -l no-symbols,clip,in-place,force -n "$PROGRAM" -- "$@")"
	local err=$?
	eval set -- "$opts"
	while true; do case $1 in
		-n|--no-symbols) symbols=""; shift ;;
		-c|--clip) clip=1; shift ;;
		-f|--force) force=1; shift ;;
		-i|--in-place) inplace=1; shift ;;
		--) shift; break ;;
	esac done

	[[ $err -ne 0 || ( $# -ne 2 && $# -ne 1 ) || ( $force -eq 1 && $inplace -eq 1 ) ]] && die "Usage: $PROGRAM $COMMAND [--no-symbols,-n] [--clip,-c] [--in-place,-i | --force,-f] pass-name [pass-length]"
	local path="$1"
	local length="${2:-$GENERATED_LENGTH}"
	check_sneaky_paths "$path"
	[[ ! $length =~ ^[0-9]+$ ]] && die "Error: pass-length \"$length\" must be a number."
	mkdir -p -v "$PREFIX/$(dirname "$path")"
	local passfile="$PREFIX/$path.gpg"

	[[ $inplace -eq 0 && $force -eq 0 && -e $passfile ]] && approve "An entry already exists for $path. Overwrite it?" || exit 1

	local pass="$(pwgen -s $symbols $length 1)"
	[[ -n $pass ]] || exit 1
	if [[ $inplace -eq 0 ]]; then
		$GPG -e -o "$passfile" "${GPG_OPTS[@]}" <<<"$pass" || die "Password encryption aborted."
	else
		local passfile_temp="${passfile}.tmp.${RANDOM}.${RANDOM}.${RANDOM}.${RANDOM}.--"
		if $GPG -d "${GPG_OPTS[@]}" "$passfile" | sed $'1c \\\n'"$(sed 's/[\/&]/\\&/g' <<<"$pass")"$'\n' | $GPG -e -o "$passfile_temp" "${GPG_OPTS[@]}"; then
			mv "$passfile_temp" "$passfile"
		else
			rm -f "$passfile_temp"
			die "Could not reencrypt new password."
		fi
	fi
	local verb="Add"
	[[ $inplace -eq 1 ]] && verb="Replace"
	git_add_file "$passfile" "$verb generated password for ${path}."

	if [[ $clip -eq 0 ]]; then
		printf "\e[1m\e[37mThe generated password for \e[4m%s\e[24m is:\e[0m\n\e[1m\e[93m%s\e[0m\n" "$path" "$pass"
	else
		clip "$pass" "$path"
	fi
}

cmd_delete() {
	local opts recursive="" force=0
	opts="$(getopt -o rf -l recursive,force -n "$PROGRAM" -- "$@")"
	local err=$?
	eval set -- "$opts"
	while true; do case $1 in
		-r|--recursive) recursive="-r"; shift ;;
		-f|--force) force=1; shift ;;
		--) shift; break ;;
	esac done
	[[ $# -ne 1 ]] && die "Usage: $PROGRAM $COMMAND [--recursive,-r] [--force,-f] pass-name"
	local path="$1"
	check_sneaky_paths "$path"

	local passdir="${TMPDIR}/${FLNAME}/${path%/}"
	local passfile="${TMPDIR}/${FLNAME}/${path}.txt"

	decrypt

	[[ -f $passfile && -d $passdir && $path == */ || ! -f $passfile ]] && passfile="$passdir"
	[[ -e $passfile ]] || die "Error: $path is not in the password store."

	[[ $force -eq 1 ]] || approve "Are you sure you would like to delete $path?" || exit 1

	rm $recursive -f -v "$passfile"
	rmdir -p "${passfile%/*}" 2>/dev/null || true

	encrypt
}

cmd_copy_move() {
	local opts move=1 force=0
	[[ $1 == "copy" ]] && move=0
	shift
	opts="$(getopt -o f -l force -n "$PROGRAM" -- "$@")"
	local err=$?
	eval set -- "$opts"
	while true; do case $1 in
		-f|--force) force=1; shift ;;
		--) shift; break ;;
	esac done
	[[ $# -ne 2 ]] && die "Usage: $PROGRAM $COMMAND [--force,-f] old-path new-path"
	check_sneaky_paths "$@"

	decrypt

	local old_path="${TMPDIR}/${FLNAME}/${1%/}"
	local old_dir="$old_path"
	local new_path="${TMPDIR}/${FLNAME}/$2"

	if ! [[ -f ${old_path}.txt && -d $old_path && $1 == */ || ! -f ${old_path}.txt ]]; then
		old_dir="${old_path%/*}"
		old_path="${old_path}.txt"
	fi
	echo "$old_path"
	[[ -e $old_path ]] || die "Error: $1 is not in your library."

	mkdir -p -v "${new_path%/*}"
	[[ -d $old_path || -d $new_path || $new_path == */ ]] || new_path="${new_path}.txt"

	local interactive="-i"
	[[ ! -t 0 || $force -eq 1 ]] && interactive="-f"

	if [[ $move -eq 1 ]]; then
		mv $interactive -v "$old_path" "$new_path" || exit 1
		rmdir -p "$old_dir" 2>/dev/null || true
		encrypt
	else
		cp $interactive -r -v "$old_path" "$new_path" || exit 1
		encrypt
	fi
}

cmd_update() {
	decrypt
	unset USER_PW
	encrypt
}

#
# END subcommand functions
#

trap cleanup INT TERM EXIT

PROGRAM="${0##*/}"
COMMAND="$1"

case "$1" in
	help|-h|--help) shift;			cmd_usage "$@" ;;
	version|-v|--version) shift;	cmd_version "$@" ;;
	ls|list) shift;					cmd_list "$@" ;;
	show) shift;					cmd_show "$@" ;;
	find|search) shift;				cmd_find "$@" ;;
	grep) shift;					cmd_grep "$@" ;;
	insert|add) shift;				cmd_insert "$@" ;;
	edit) shift;					cmd_edit "$@" ;;
	generate) shift;				cmd_generate "$@" ;;
	delete|rm|remove) shift;		cmd_delete "$@" ;;
	rename|mv) shift;				cmd_copy_move "move" "$@" ;;
	copy|cp) shift;					cmd_copy_move "copy" "$@" ;;
	update|up) shift;				cmd_update "$@" ;;
	*) COMMAND="show";				cmd_show "$@" ;;
esac
exit 0
