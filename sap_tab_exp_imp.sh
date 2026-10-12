#!/bin/bash
# SAP(R) Table EXP/IMP for SystemCopy (c) Florian Lamml 2026
# www.florian-lamml.de
# Version 1.0 - Initial Release
# Version 1.1 - Client Config
# Version 1.2 - New Tables
# Version 1.3 - Template Correction
# Version 1.4 - Minor Corrections
# Version 1.5 - Cloud ALM Template
# Version 1.6 - Corrections Cloud ALM and GTS Template
# Version 1.7 - More Templates
# Version 1.7.1 - More Templates Correction
# Version 1.7.2 - BD97 Template
# Version 1.8 - R3load Parallel Parameter
# Version 1.8.1 - More Templates
# Version 1.8.2 - More Templates
# Version 1.8.3 - $SAPSYSTEMNAME in default expimp location
# Version 1.8.4 - Correction of OAC0 Template
# Version 1.8.5 - OMIQ Template, Correction OAC0 Template
# Version 1.8.6 - Correct OAC0 Template
# Version 1.8.7 - Correct UCON Template, ADD ALECUSTOMIZINGNOTADIR (ALECUSTOMIZING without TADIR)
# Version 1.8.8 - New Template RZ20andRZ21, New Template SM37-S4 (old is SM37-R3), New Template OAUTHCONFIG, renaming some templates
# Version 1.8.9 - New Template OAC0-NOTOA01
# Version 1.9   - PowerShell Port for Windows
# Version 1.9.1 - Correct VSCAN Template
# Version 1.10  - Security Hardening (permissions, checksums, target check, backup, user and config check)

##### CONFIG EXPORT / IMPORT LOCATION #####
export EXPIMPLOC=
###########################################

##### CONFIG CLIENT #######################
# DEFAULT (000), ALL or CLIENT Number
# Default Value = ALL
export EXPCLIENT=ALL
###########################################

##### CONFIG PARALLEL (SAP 1127194) #######
# DEFAULT 0, Max 1-2x CPU Count
export PARALLEL=0
###########################################

##### CONFIG BACKUPKEEP ##################
# number of backups of previous runs to keep
# in EXPIMPLOC/backup (the oldest ones are
# deleted after a new backup was created)
# 0 = unlimited (no backup is deleted)
# Default Value = 0
export BACKUPKEEP=0
###########################################

##### CONFIG PERMISSIONS ##################
# OPEN   = files 666, directories 777, no
#          permission checks (works always,
#          e.g. on NFS v3 shares)
# STRICT = files 660, directories 770
#          (only <sid>adm users of the same
#          group), stop if EXPIMPLOC contains
#          files of another group or files
#          writable by others
# the import always verifies the SHA-256
# checksums of the data files
# Default Value = OPEN
export EXPIMPPERM=OPEN
###########################################

##### info ################################
# with this tool you can export and import
# tables from and into a sap system
# you have to run it as "sidadm"
# it use the normal R3trans for export
# and import with template files
####################(c) Florian Lamml 2026#

# Prerequisites ###########################
# need 'dialog' to run
# need sha256sum, shasum, csum or openssl
###########################################

##### list of exit codes ##################
# general
# 99 - you try to run as "root"
# 98 - cannot find SAP SID
# 97 - cannot start dialog
# 96 - Hit ESC
# 94 - cannot create / secure export location (writable / group / permissions)
# 93 - no SHA-256 tool found (sha256sum, shasum, csum or openssl)
# 92 - user is not <sid>adm
# 90 - export / import script started directly (not by sap_tab_exp_imp.sh)
# 91 - invalid config value (EXPIMPLOC, EXPCLIENT, PARALLEL, BACKUPKEEP, EXPIMPPERM)
# export
# 10 - exit because old run detected
# 11 - fail to select templates for export
# 12 - no template selected for export
# 13 - error while export
# 14 - export info error
# 15 - backup of the previous run failed
# import
# 20 - no exports found for import
# 21 - exit because old run detected
# 22 - no OK exports found for import
# 23 - import select error
# 24 - no exports selected for import
# 25 - error while import
# 26 - import info error
# 27 - checksum verification failed
# 28 - import not confirmed
# 29 - no export selected for import
###########################################

# set global variables
# directory of this script (templates, sub scripts) - independent of the current directory
global_pwd=$(cd "$(dirname "$0")" && pwd)
export global_pwd
export global_height=45
export global_width=80
export global_list=35
export global_title="SAP Table EXP/IMP for SystemCopy (c) Florian Lamml 2026"
export global_backtitle="SAP Table EXP/IMP for SystemCopy (c) Florian Lamml 2026"
export global_copy="(c) Florian Lamml 2026"


# root check
CURUSER=$(id -un)
export CURUSER
if [ "$(id -u)" -eq 0 ];
then
	echo "This script must not be run as root user!" 
	echo "... EXIT NOW"
	exit 99
fi 

# SAPSYSTEMNAME variable check (need for R3trans)
if [ -z "$SAPSYSTEMNAME" ];
 then
   echo "No SID found, is the user right?"
   echo "... EXIT NOW"
   exit 98
fi

# <sid>adm check
SIDADM="$(echo "$SAPSYSTEMNAME" | tr '[:upper:]' '[:lower:]')adm"
if [ "$CURUSER" != "$SIDADM" ];
 then
   echo "This script must be run as $SIDADM (current user: $CURUSER)!"
   echo "... EXIT NOW"
   exit 92
fi

# check config values (they are written into the R3trans control files)
EXPCLIENT=$(echo "$EXPCLIENT" | tr '[:lower:]' '[:upper:]')
case "$EXPCLIENT" in
 ALL|DEFAULT|[0-9][0-9][0-9]) ;;
 *)
   echo "EXPCLIENT '$EXPCLIENT' is invalid (allowed: ALL, DEFAULT or a 3-digit client number)"
   echo "... EXIT NOW"
   exit 91
   ;;
esac
export EXPCLIENT

# PARALLEL check empty variable
if [ -z "${PARALLEL}" ]; 
 then
	PARALLEL=0
fi
case "$PARALLEL" in
 *[!0-9]*)
   echo "PARALLEL '$PARALLEL' is invalid (allowed: 0 or a positive number)"
   echo "... EXIT NOW"
   exit 91
   ;;
esac
export PARALLEL

# BACKUPKEEP check empty variable
if [ -z "${BACKUPKEEP}" ]; 
 then
	BACKUPKEEP=0
fi
case "$BACKUPKEEP" in
 *[!0-9]*)
   echo "BACKUPKEEP '$BACKUPKEEP' is invalid (allowed: 0 = unlimited or a positive number)"
   echo "... EXIT NOW"
   exit 91
   ;;
esac
export BACKUPKEEP

# check permission mode and set umask
# the export files contain sensitive data (PSEs, secure storage, RFC destinations ...)
# STRICT: all files and directories created by this tool are only accessible by the owner
#         and the group (sapsys) - export and import can run as different <sid>adm users
# OPEN:   files and directories are accessible by everyone (e.g. NFS v3 shares)
EXPIMPPERM=$(echo "$EXPIMPPERM" | tr '[:lower:]' '[:upper:]')
case "$EXPIMPPERM" in
 STRICT) umask 007 ;;
 OPEN)   umask 000 ;;
 *)
   echo "EXPIMPPERM '$EXPIMPPERM' is invalid (allowed: STRICT or OPEN)"
   echo "... EXIT NOW"
   exit 91
   ;;
esac
export EXPIMPPERM

# check export location
if [ -z "$EXPIMPLOC" ]; 
 then 
 export EXPIMPLOCINFO="EXPIMPLOC is not set, use default";
 export EXPIMPLOC="$global_pwd/expimp/$SAPSYSTEMNAME"
else 
 export EXPIMPLOCINFO="EXPIMPLOC is set to"; 
fi
NEWLINE='
'
case "$EXPIMPLOC" in
 *"'"*|*"$NEWLINE"*)
   echo "EXPIMPLOC '$EXPIMPLOC' is invalid (must not contain quotes or line breaks)"
   echo "... EXIT NOW"
   exit 91
   ;;
 /*) ;;
 *)
   echo "EXPIMPLOC '$EXPIMPLOC' is invalid (must be an absolute path)"
   echo "... EXIT NOW"
   exit 91
   ;;
esac

# create export location and secure it (only users of the group of <sid>adm may read and write)
# the directory EXPIMPLOC itself may belong to another user / group (if it already exists),
# it only has to be writable for <sid>adm - all files and directories in it are checked
CURGROUP=$(id -gn)
if [ ! -d "$EXPIMPLOC" ] && ! mkdir -p "$EXPIMPLOC";
 then
   echo "cannot create $EXPIMPLOC"
   echo "... EXIT NOW"
   exit 94
fi
if [ ! -w "$EXPIMPLOC" ] || [ ! -x "$EXPIMPLOC" ];
 then
   echo "$EXPIMPLOC is not writable for $CURUSER!"
   echo "... EXIT NOW"
   exit 94
fi
if [ "$EXPIMPPERM" = OPEN ];
 then
   # open permissions for own files of previous runs, errors are ignored (e.g. NFS)
   find "$EXPIMPLOC" -user "$CURUSER" | awk -v d="$EXPIMPLOC" '$0 != d' | while IFS= read -r OWNFILE; do chmod a+rwX "$OWNFILE" 2>/dev/null; done
else
   FOREIGNFILE=$(find "$EXPIMPLOC" ! -group "$CURGROUP" 2>/dev/null | awk -v d="$EXPIMPLOC" '$0 != d' | head -1)
   if [ -n "$FOREIGNFILE" ];
    then
      echo "$EXPIMPLOC contains files not belonging to group $CURGROUP (e.g. $FOREIGNFILE)!"
      echo "... EXIT NOW"
      exit 94
   fi
   if ! find "$EXPIMPLOC" -user "$CURUSER" | awk -v d="$EXPIMPLOC" '$0 != d' | while IFS= read -r OWNFILE; do chmod g+rwX,o-rwx "$OWNFILE" || exit 1; done;
    then
      echo "cannot set permissions in $EXPIMPLOC"
      echo "... EXIT NOW"
      exit 94
   fi
   FOREIGNFILE=$(find "$EXPIMPLOC" -perm -002 2>/dev/null | awk -v d="$EXPIMPLOC" '$0 != d' | head -1)
   if [ -n "$FOREIGNFILE" ];
    then
      echo "$EXPIMPLOC contains files writable by others (e.g. $FOREIGNFILE)!"
      echo "... EXIT NOW"
      exit 94
   fi
fi

# set logfile
EXPIMPLOGFILE="$EXPIMPLOC/EXP_IMP_LOG_$(date "+%d_%m_%Y").txt"
export EXPIMPLOGFILE
date "+%d.%m.%Y-%H:%M" >> "$EXPIMPLOGFILE"

# SHA-256 tool for the checksums of the export files
# shellcheck source=script/sap_expimp_lib.sh
. "$global_pwd/script/sap_expimp_lib.sh"
SHA256TOOL=$(expimp_find_sha256_tool)
export SHA256TOOL
if [ -z "$SHA256TOOL" ];
 then
   echo "cannot find a tool for SHA-256 checksums (sha256sum, shasum, csum or openssl)"
   echo "... EXIT NOW"
   echo "ERROR: no SHA-256 tool found" >> "$EXPIMPLOGFILE"
   exit 93
fi

# check AIX and set PATH and LIBPATH to use linux dialog (build from dialog-1.2-20150225 with gcc-4.8.3-1.aix7.1 on AIX 7.1) on AIX
OS=$(uname)
export OS
if [ "$OS" = AIX ]
then
export PATH="$PATH:$global_pwd/dialogaix/bin"
export LIBPATH="$LIBPATH:$global_pwd/dialogaix/lib"
chmod u+x "$global_pwd/dialogaix/bin/dialog"
fi

# check if dialog is running
if ! dialog > /dev/null 2>&1;
 then
	echo "cannot start linux 'dialog' command"
	echo "... EXIT NOW"
	exit 97
fi

# limit the dialog size to the size of the terminal (dialog fails if the terminal is smaller)
TERMSIZE=$(stty size < /dev/tty 2>/dev/null)
TERMLINES=${TERMSIZE% *}
TERMCOLS=${TERMSIZE#* }
case "$TERMLINES$TERMCOLS" in
 ''|*[!0-9]*) TERMLINES=$(tput lines 2>/dev/null); TERMCOLS=$(tput cols 2>/dev/null) ;;
esac
case "$TERMLINES" in
 ''|*[!0-9]*) ;;
 *) [ "$TERMLINES" -lt $((global_height + 2)) ] && global_height=$((TERMLINES - 2)) ;;
esac
case "$TERMCOLS" in
 ''|*[!0-9]*) ;;
 *) [ "$TERMCOLS" -lt $((global_width + 2)) ] && global_width=$((TERMCOLS - 2)) ;;
esac
global_list=$((global_height - 10))
[ "$global_list" -lt 1 ] && global_list=1
export global_height global_width global_list

# EXPORT or IMPORT dialog
# ascii art only if the terminal is big enough for it
STARTART=""
[ "$global_height" -ge 34 ] && STARTART="   _______   ___ \n  / __/ _ | / _ \ \n _\ \/ __ |/ ___/\n/___/_/ |_/_/    \n _________   ___  __   ____\n/_  __/ _ | / _ )/ /  / __/\n / / / __ |/ _  / /__/ _/  \n/_/ /_/ |_/____/____/___/  \n   _____  _____  ______  ______ \n  / __/ |/_/ _ \/  _/  |/  / _ \ \n / _/_>  </ ___// // /|_/ / ___/\n/___/_/|_/_/  /___/_/  /_/_/    \n\n"
DIALOG=(dialog --title "$global_title" --backtitle "$global_backtitle"  --radiolist  "${STARTART}EXPORT or IMPORT Tables?\n\nINFO: $EXPIMPLOCINFO\nINFO: $EXPIMPLOC \n\nCLIENT: $EXPCLIENT | PARALLEL: $PARALLEL | BACKUPKEEP: $BACKUPKEEP | PERM: $EXPIMPPERM\nOS: $OS | USER: $CURUSER | SAPSYSTEM: $SAPSYSTEMNAME\n\n                                $global_copy" "$global_height" "$global_width" 2)
OPTIONS=("EXPORT" "Export SAP Tables" on "IMPORT" "Import SAP Tables" off)
# check ESC / Cancel hit
if ! EXPORIMP=$("${DIALOG[@]}" "${OPTIONS[@]}" 2>&1 >/dev/tty);
 then
	clear
	echo "Hit ESC / Cancel"
	echo "... EXIT NOW"
	exit 96
fi

# EXPORT or IMPORT
EXPIMPRUNRC=96
EXPIMPRUN="Procedure finished with RC="
case "$(echo "$EXPORIMP" | tr -d '"')" in
    EXPORT)
			(
			echo "Export SAP Tables" >> "$EXPIMPLOGFILE"
			# run export script
			bash "$global_pwd/script/sap_export_tables.sh"
			)
			EXPIMPRUNRC=$?
			EXPIMPRUN="Export procedure finished with RC="
            ;;
    IMPORT)
			(
			echo "Import SAP Tables" >> "$EXPIMPLOGFILE"
			# run import script
			bash "$global_pwd/script/sap_import_tables.sh"
			)
			EXPIMPRUNRC=$?
			EXPIMPRUN="Import procedure finished with RC="
            ;;
esac

# summary
EXPIMPRUNINFO=""
case "$EXPIMPRUNRC" in
 13|25) EXPIMPRUNINFO="\n\nERROR: at least one table failed (R3trans RC >= 8 or template missing)!\nPlease check the R3trans log files (*.exp.log / *.imp.log)." ;;
esac
dialog --title "$global_title" --backtitle "$global_backtitle"  --ok-label "EXIT" --msgbox "$EXPIMPRUN$EXPIMPRUNRC$EXPIMPRUNINFO\n\nLogfiles can be found in $EXPIMPLOC" "$global_height" "$global_width"

# exit
clear
exit "$EXPIMPRUNRC"
