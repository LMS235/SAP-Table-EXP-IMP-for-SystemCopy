#!/bin/bash
# global_* variables are exported by sap_tab_exp_imp.sh
# shellcheck disable=SC2154
# SAP(R) Table EXP/IMP for SystemCopy (c) Florian Lamml 2026
# www.florian-lamml.de
# helper functions (shared by main / export / import script)
# Version 1.10 - Security Hardening
# Version 2.0 - komplett überarbeitet mit neuen Funktionen und Sicherheitsoptionen

# find a tool for SHA-256 checksums (sha256sum on Linux, csum or openssl on AIX)
# prints the tool name, returns 1 if no usable tool was found
expimp_find_sha256_tool() {
 for tool in sha256sum shasum csum openssl
 do
  command -v "$tool" > /dev/null 2>&1 || continue
  SHA256TOOL=$tool
  if expimp_sha256 "$0" | grep -q '^[0-9a-f]\{64\}$'
  then
   echo "$tool"
   return 0
  fi
 done
 return 1
}

# SHA-256 checksum of a file (lower case hex)
expimp_sha256() {
 case "$SHA256TOOL" in
  sha256sum) sha256sum "$1" 2>/dev/null | awk '{ print $1 }' ;;
  shasum)    shasum -a 256 "$1" 2>/dev/null | awk '{ print $1 }' ;;
  csum)      csum -h SHA256 "$1" 2>/dev/null | awk '{ print $1 }' ;;
  openssl)   openssl dgst -sha256 "$1" 2>/dev/null | awk '{ print $NF }' ;;
 esac | tr '[:upper:]' '[:lower:]'
}

# value of a metadata line "# KEY=value" in an info file
expimp_meta() {
 sed -n "s/^# $2=//p" "$1" | head -1
}

# files of a previous export / import run in EXPIMPLOC (one per line)
expimp_run_files() {
 for f in "$EXPIMPLOC"/selected_tables_for_export.conf "$EXPIMPLOC"/exported_tables.conf \
          "$EXPIMPLOC"/exported_tables_ok.conf "$EXPIMPLOC"/selected_tables_import.conf \
          "$EXPIMPLOC"/imported_tables.conf "$EXPIMPLOC"/*.tpl "$EXPIMPLOC"/*.dat \
          "$EXPIMPLOC"/*.exp.log "$EXPIMPLOC"/*.imp.log
 do
  [ -f "$f" ] && echo "$f"
 done
}

# current size of the dialogs: at most global_height x global_width (45 x 80),
# limited to the current size of the terminal (sets DLGH, DLGW and DLGL = list height)
expimp_dialog_size() {
 local termsize termlines termcols
 termsize=$(stty size < /dev/tty 2>/dev/null)
 termlines=${termsize% *}
 termcols=${termsize#* }
 case "$termlines$termcols" in
  ''|*[!0-9]*) termlines=$(tput lines 2>/dev/null); termcols=$(tput cols 2>/dev/null) ;;
 esac
 DLGH=${global_height:-45}
 DLGW=${global_width:-80}
 case "$termlines" in
  ''|*[!0-9]*) ;;
  *) [ "$termlines" -lt $((DLGH + 2)) ] && DLGH=$((termlines - 2)) ;;
 esac
 case "$termcols" in
  ''|*[!0-9]*) ;;
  *) [ "$termcols" -lt $((DLGW + 2)) ] && DLGW=$((termcols - 2)) ;;
 esac
 DLGL=$((DLGH - 10))
 [ "$DLGL" -lt 1 ] && DLGL=1
}

# run dialog with the current size of the terminal
# - the size arguments are given as @H@ @W@ @L@ (height, width, list height) and the
#   text @ART@ is replaced by EXPIMPART if the dialog is high enough for it (34 lines)
# - the result of dialog (selection, input) is written to stdout
# - older dialog versions end with an error if the terminal is made smaller than the
#   dialog - then the dialog is shown again with the new size (instead of "ESC")
# - progressbox: the input is always read completely, so the writing process (R3trans)
#   is never ended by a broken pipe, even if dialog ends with an error
expimp_dialog() {
 local rc tries arg args progress errfile outfile
 errfile=$EXPIMPLOC/.expimp_dialog_err.$$
 outfile=$EXPIMPLOC/.expimp_dialog_out.$$
 progress=no
 for arg in "$@"; do [ "$arg" = "--progressbox" ] && progress=yes; done
 tries=0
 while :
 do
  expimp_dialog_size
  args=()
  for arg in "$@"
  do
   case "$arg" in
    @H@) arg=$DLGH ;;
    @W@) arg=$DLGW ;;
    @L@) arg=$DLGL ;;
    *@ART@*) if [ "$DLGH" -ge 34 ]; then arg=${arg//@ART@/"$EXPIMPART"}; else arg=${arg//@ART@/}; fi ;;
   esac
   args+=("$arg")
  done
  dialog --output-fd 3 "${args[@]}" 3> "$outfile" 2> "$errfile" > /dev/tty
  rc=$?
  # error of dialog (not ESC): show the dialog again with the current size
  if [ "$rc" -ne 0 ] && [ "$rc" -ne 1 ] && [ -s "$errfile" ] && [ "$tries" -lt 300 ]
   then
	tries=$((tries + 1))
	if [ "$progress" = yes ]
	 then
		# discard the output for a moment (it is in the R3trans log files)
		while IFS= read -r -t 1 _; do :; done
	else
		sleep 1
	fi
	continue
  fi
  break
 done
 # progressbox: read the rest of the input (never break the pipe of R3trans)
 [ "$progress" = yes ] && cat > /dev/null
 cat "$outfile" 2>/dev/null
 [ "$rc" -ne 0 ] && [ "$rc" -ne 1 ] && cat "$errfile" >&2 2>/dev/null
 rm -f "$outfile" "$errfile"
 return "$rc"
}

# progress bar for the progress box, e.g. "[##########..........] 5/10 (50%)"
expimp_progress_bar() {
 local cur=$1 total=$2 width=20 fill
 [ "$total" -gt 0 ] || total=1
 fill=$((cur * width / total))
 printf '[%s%s] %d/%d (%d%%)' "$(printf '%*s' "$fill" '' | tr ' ' '#')" "$(printf '%*s' $((width - fill)) '' | tr ' ' '.')" "$cur" "$total" $((cur * 100 / total))
}

# progress box that survives a resize of the terminal (a running "dialog --progressbox"
# is not redrawn by some dialog versions after the terminal was made smaller / bigger)
# - the input is shown with "dialog --infobox" (the last lines that fit into the box)
# - redrawn only at planned points: when a template starts ("=== Export 5/10: ...")
#   and when it is finished ("=== [#####.....] 5/10 (50%) done ===") - the output of
#   R3trans in between is collected and shown with the next update (no flickering)
# - the input is always read completely (R3trans is never ended by a broken pipe)
expimp_progressbox() {
 local text=$1 line eof drawsize lastsize max start i out
 local -a lines=()
 eof=no
 lastsize=""
 while [ "$eof" = no ]
 do
  if IFS= read -r line
   then
	lines+=("$line")
  else
	# end of input (a last line without newline is kept too)
	[ -n "$line" ] && lines+=("$line")
	eof=yes
  fi
  # keep only the last 200 lines
  [ "${#lines[@]}" -gt 200 ] && lines=("${lines[@]:$((${#lines[@]} - 200))}")
  # redraw only when a template starts or is finished
  case "$line" in
   "=== Export "[0-9]*|"=== Import "[0-9]*|"=== ["*) ;;
   *) continue ;;
  esac
  expimp_dialog_size
  drawsize="$DLGH $DLGW"
  # the size of the terminal changed: clear the old screen once
  if [ "$drawsize" != "$lastsize" ]
   then
	clear > /dev/tty
	lastsize=$drawsize
  fi
  max=$((DLGH - 4))
  [ "$max" -lt 1 ] && max=1
  start=$((${#lines[@]} - max))
  [ "$start" -lt 0 ] && start=0
  out="$text"$'\n'"$(printf '%*s' $((DLGW - 4)) '' | tr ' ' '-')"
  for ((i = start; i < ${#lines[@]}; i++))
  do
   out+=$'\n'"${lines[$i]:0:$((DLGW - 4))}"
  done
  # if dialog fails (terminal too small), the screen is cleared and drawn with the next update
  dialog --title "$global_title" --backtitle "$global_backtitle" --no-collapse --no-nl-expand --infobox "$out" "$DLGH" "$DLGW" > /dev/tty 2>/dev/null || lastsize=""
 done
}
