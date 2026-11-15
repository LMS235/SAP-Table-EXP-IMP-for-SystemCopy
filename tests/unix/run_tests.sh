#!/bin/bash
# SAP(R) Table EXP/IMP for SystemCopy (c) Florian Lamml 2026
# www.florian-lamml.de
# tests of the Unix version
# - the tool runs in a pseudo terminal ('script') with stand-ins for R3trans and dialog
#   (tests/unix/fake - the answers of the dialogs come from a file)
# - one test uses the real 'dialog' command (skipped if it is not installed)
# - a copy of the scripts is tested, in the copy only the <sid>adm check is disabled
#   (and the root check, if the tests are run as root)
# usage: bash tests/unix/run_tests.sh
set -euo pipefail

TESTDIR=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$TESTDIR/../.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

SID=TST
LOC=$WORK/loc
FAILED=0
LASTRC=""

# stand-ins (executable copies, the real dialog is found first if the directory is not in the PATH)
mkdir "$WORK/bin_dialog" "$WORK/bin_r3trans"
cp "$TESTDIR/fake/dialog" "$WORK/bin_dialog/dialog"
cp "$TESTDIR/fake/R3trans" "$WORK/bin_r3trans/R3trans"
chmod +x "$WORK/bin_dialog/dialog" "$WORK/bin_r3trans/R3trans"
export EXPIMP_TEST_ANSWERS=$WORK/answers
export EXPIMP_TEST_CALLS=$WORK/calls

check() {
 # check <description> <command ...>
 local desc=$1
 shift
 if "$@"
  then
	echo "  ok   $desc"
 else
	echo "  FAIL $desc"
	FAILED=$((FAILED + 1))
 fi
}

rc_is() { [ "$LASTRC" = "$1" ]; }
has_line() { grep -a -q -e "$2" "$1" 2>/dev/null; }
no_file() { [ ! -e "$1" ]; }
mode_is() { [ "$(stat -c '%a' "$2")" = "$1" ]; }

answers() {
 # answers <line ...>: the answers of the dialogs in the order of the dialogs
 printf '%s\n' "$@" > "$EXPIMP_TEST_ANSWERS"
}

run_tool() {
 # run_tool <path> <keys or ''> <config assignments ...>
 # the exit code of the tool is written to LASTRC, the output of the terminal to $WORK/tty.out
 local path=$1 keys=$2 kv main
 shift 2
 rm -rf "$WORK/repo"
 mkdir "$WORK/repo"
 cp -r "$REPO/sap_tab_exp_imp.sh" "$REPO/script" "$REPO/templates" "$WORK/repo/"
 main=$WORK/repo/sap_tab_exp_imp.sh
 # shellcheck disable=SC2016
 grep -q '^if \[ "$CURUSER" != "$SIDADM" \];$' "$main"
 # shellcheck disable=SC2016
 sed -i 's|^if \[ "$CURUSER" != "$SIDADM" \];$|if false;|' "$main"
 if [ "$(id -u)" -eq 0 ]
  then
	# shellcheck disable=SC2016
	sed -i 's|^if \[ "$(id -u)" -eq 0 \];$|if false;|' "$main"
 fi
 for kv in "$@"
 do
  grep -q "^export ${kv%%=*}=" "$main"
  sed -i "s|^export ${kv%%=*}=.*|export $kv|" "$main"
 done
 : > "$EXPIMP_TEST_CALLS"
 if [ -n "$keys" ]
  then
	# keys for the real dialog: one key every two seconds
	(
	 for key in $keys
	 do
	  sleep 2
	  case "$key" in
	   ENTER) printf '\r' ;;
	   SPACE) printf ' ' ;;
	  esac
	 done
	 sleep 5
	) | PATH="$path" SAPSYSTEMNAME=$SID TERM=xterm timeout 180 script -qec "stty rows 40 cols 120; bash $main; echo EXITCODE=\$?" "$WORK/tty.out" > /dev/null || true
 else
	PATH="$path" SAPSYSTEMNAME=$SID TERM=xterm timeout 180 script -qec "stty rows 40 cols 120; bash $main; echo EXITCODE=\$?" "$WORK/tty.out" > /dev/null < /dev/null || true
 fi
 LASTRC=$(tr -d '\r' < "$WORK/tty.out" | grep -a -o 'EXITCODE=[0-9]*' | tail -1 | cut -d= -f2 || true)
}

FAKEPATH=$WORK/bin_dialog:$WORK/bin_r3trans:$PATH
D=$LOC/$SID

echo "TEST export of two templates"
answers '0|EXPORT' '0|AL11\nSM59\n' '0|' '0|'
run_tool "$FAKEPATH" '' "EXPIMPLOC=$LOC"
check "exit code 0 (is $LASTRC)" rc_is 0
check "AL11 exported with checksum" has_line "$D/exported_tables.conf" '^AL11|RC=0|SHA256=[0-9a-f]\{64\}$'
check "SM59 exported with checksum" has_line "$D/exported_tables.conf" '^SM59|RC=0|SHA256=[0-9a-f]\{64\}$'
check "control file with data file" has_line "$D/AL11.tpl" "^file = '$D/AL11.dat'$"
check "directory 770" mode_is 770 "$D"
check "data file 660" mode_is 660 "$D/AL11.dat"

echo "TEST export with a failed table, ESC in the overview"
answers '0|EXPORT' '0|' '0|AL11\nRZ04\n' '255|' '0|'
run_tool "$FAKEPATH" '' "EXPIMPLOC=$LOC"
check "exit code 13 (is $LASTRC)" rc_is 13
check "backup of the previous run" test -f "$(echo "$D"/backup/*/SM59.dat)"

echo "TEST export, ESC in the overview"
answers '0|EXPORT' '0|' '0|AL11\nSM59\n' '255|' '0|'
run_tool "$FAKEPATH" '' "EXPIMPLOC=$LOC"
check "exit code 0 (is $LASTRC)" rc_is 0

echo "TEST import from a backup, ESC in the overview"
answers '0|IMPORT' '0|2' '0|AL11\n' '0|' '255|' '0|'
run_tool "$FAKEPATH" '' "EXPIMPLOC=$LOC"
check "exit code 0 (is $LASTRC)" rc_is 0
check "import from the backup" has_line "$(echo "$D"/EXP_IMP_LOG_*.txt)" "^INFO: import from $D/backup/"

echo "TEST import with a failed table, ESC in the overview"
cp "$D/SM59.dat" "$D/FAIL.dat"
sed -i 's/^SM59|\(.*\)$/SM59|\1\nFAIL|\1/' "$D/exported_tables.conf"
answers '0|IMPORT' '0|1' '0|AL11\nFAIL\n' '0|' '255|' '0|'
run_tool "$FAKEPATH" '' "EXPIMPLOC=$LOC"
check "exit code 25 (is $LASTRC)" rc_is 25
check "return code of the failed table" has_line "$D/imported_tables.conf" '^FAIL|RC=12$'

echo "TEST import with a changed data file"
echo "changed" >> "$D/AL11.dat"
answers '0|IMPORT' '0|1' '0|' '0|AL11\n' '0|' '0|'
run_tool "$FAKEPATH" '' "EXPIMPLOC=$LOC"
check "exit code 27 (is $LASTRC)" rc_is 27

echo "TEST ESC at the STMS_QA hint"
rm -rf "$LOC"
answers '0|EXPORT' '0|STMS_QA\n' '255|' '0|'
run_tool "$FAKEPATH" '' "EXPIMPLOC=$LOC"
check "exit code 96 (is $LASTRC)" rc_is 96
check "no info file" no_file "$D/exported_tables.conf"
check "no selection file" no_file "$D/selected_tables_for_export.conf"

echo "TEST import of an info file with CRLF (windows version)"
rm -rf "$LOC"
answers '0|EXPORT' '0|AL11\nSM59\n' '0|' '0|'
run_tool "$FAKEPATH" '' "EXPIMPLOC=$LOC"
sed -i 's/$/\r/' "$D/exported_tables.conf"
answers '0|IMPORT' '0|AL11\nSM59\n' '0|' '0|' '0|'
run_tool "$FAKEPATH" '' "EXPIMPLOC=$LOC"
check "exit code 0 (is $LASTRC)" rc_is 0
check "checksum verified" has_line "$(echo "$D"/EXP_IMP_LOG_*.txt)" '^SM59|checksum OK$'

echo "TEST BACKUPKEEP=01 keeps one backup"
for _ in 1 2
do
 sleep 1
 answers '0|EXPORT' '0|' '0|AL11\n' '0|' '0|'
 run_tool "$FAKEPATH" '' "EXPIMPLOC=$LOC" BACKUPKEEP=01
done
check "exit code 0 (is $LASTRC)" rc_is 0
check "one backup left" test "$(find "$D/backup" -mindepth 1 -maxdepth 1 -type d | wc -l)" -eq 1

echo "TEST config values"
rm -rf "$LOC"
answers '0|EXPORT' '0|AL11\n' '0|' '0|'
run_tool "$FAKEPATH" '' "EXPIMPLOC=$LOC" PARALLEL=007
check "PARALLEL=007: exit code 0 (is $LASTRC)" rc_is 0
check "PARALLEL=007 is 7" has_line "$D/AL11.tpl" '^parallel = 7$'
run_tool "$FAKEPATH" '' "EXPIMPLOC=$LOC" PARALLEL=1234567890
check "PARALLEL=1234567890: exit code 91 (is $LASTRC)" rc_is 91
run_tool "$FAKEPATH" '' "EXPIMPLOC=$LOC" BACKUPKEEP=x
check "BACKUPKEEP=x: exit code 91 (is $LASTRC)" rc_is 91

echo "TEST R3trans not found"
run_tool "$WORK/bin_dialog:/usr/bin:/bin" '' "EXPIMPLOC=$LOC"
check "exit code 95 (is $LASTRC)" rc_is 95

echo "TEST permissions"
rm -rf "$LOC"
mkdir -p "$D/backup/20260101_000000"
touch "$D/notes.txt" "$D/OLD.dat" "$D/backup/20260101_000000/X.dat"
chmod 644 "$D/notes.txt"
chmod 666 "$D/OLD.dat" "$D/backup/20260101_000000/X.dat"
chmod 770 "$D"
answers '255|'
run_tool "$FAKEPATH" '' "EXPIMPLOC=$LOC"
check "STRICT: exit code 96 (is $LASTRC)" rc_is 96
check "STRICT: file of the tool 660" mode_is 660 "$D/OLD.dat"
check "STRICT: file in the backup 660" mode_is 660 "$D/backup/20260101_000000/X.dat"
check "STRICT: other file not changed" mode_is 644 "$D/notes.txt"
answers '255|'
run_tool "$FAKEPATH" '' "EXPIMPLOC=$LOC" EXPIMPPERM=OPEN
check "OPEN: file of the tool 666" mode_is 666 "$D/OLD.dat"
check "OPEN: other file not changed" mode_is 644 "$D/notes.txt"
chmod 777 "$D"
answers '255|'
run_tool "$FAKEPATH" '' "EXPIMPLOC=$LOC"
check "STRICT: EXPIMPLOC writable by others: exit code 94 (is $LASTRC)" rc_is 94
chmod 1777 "$D"
answers '255|'
run_tool "$FAKEPATH" '' "EXPIMPLOC=$LOC"
check "STRICT: EXPIMPLOC with sticky bit: exit code 96 (is $LASTRC)" rc_is 96

echo "TEST error of dialog"
rm -rf "$LOC"
answers '255||Error: test error of dialog' '255|'
run_tool "$FAKEPATH" '' "EXPIMPLOC=$LOC"
check "exit code 96 (is $LASTRC)" rc_is 96
check "error is shown" has_line "$WORK/tty.out" 'Error: test error of dialog'
check "retry is shown" has_line "$WORK/tty.out" 'Retry 1/300'

echo "TEST export with the real dialog"
if command -v dialog > /dev/null 2>&1
 then
	rm -rf "$LOC"
	# start dialog: ENTER (EXPORT) - templates: SPACE (first template), ENTER - overview: ENTER - summary: ENTER
	run_tool "$WORK/bin_r3trans:$PATH" 'ENTER SPACE ENTER ENTER ENTER' "EXPIMPLOC=$LOC"
	check "exit code 0 (is $LASTRC)" rc_is 0
	check "first template exported" has_line "$D/exported_tables.conf" '^AL11|RC=0|SHA256=[0-9a-f]\{64\}$'
	check "export finished" has_line "$(echo "$D"/EXP_IMP_LOG_*.txt)" '^=== export finished ===$'
else
	echo "  skip (dialog is not installed)"
fi

echo ""
if [ "$FAILED" -ne 0 ]
 then
	echo "$FAILED check(s) FAILED"
	exit 1
fi
echo "all checks ok"
