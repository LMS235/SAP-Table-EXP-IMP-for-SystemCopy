#!/bin/bash
# global_* variables are exported by sap_tab_exp_imp.sh
# shellcheck disable=SC2154
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

# the import script must be started by sap_tab_exp_imp.sh (config, checks, logfile)
if [ -z "$EXPIMPLOC" ] || [ -z "$EXPIMPLOGFILE" ] || [ -z "$SHA256TOOL" ]
 then
	echo "This script must be started by sap_tab_exp_imp.sh!"
	echo "... EXIT NOW"
	exit 90
fi

# helper functions (checksums, metadata)
# shellcheck source=script/sap_expimp_lib.sh
. "$(dirname "$0")/sap_expimp_lib.sh"

# exports available for import: the current export and the backups of previous runs
# (newest first - the backup directories are named by timestamp)
IMPSRCDIRS=()
[ -s "$EXPIMPLOC/exported_tables.conf" ] && IMPSRCDIRS+=("$EXPIMPLOC")
BACKUPDIRS=()
for BACKUPDIR in "$EXPIMPLOC"/backup/*
do
 [ -s "$BACKUPDIR/exported_tables.conf" ] && BACKUPDIRS=("$BACKUPDIR" "${BACKUPDIRS[@]}")
done
IMPSRCDIRS+=("${BACKUPDIRS[@]}")
if [ "${#IMPSRCDIRS[@]}" -eq 0 ]
 then 
	echo "ERROR: no exports found for import" >> "$EXPIMPLOGFILE"
	exit 20
fi

# select the export to import if there is more than one (default is the newest)
IMPSRC=${IMPSRCDIRS[0]}
if [ "${#IMPSRCDIRS[@]}" -gt 1 ]
 then
	IMPSRCLIST=()
	IMPSRCNR=0
	for IMPSRCDIR in "${IMPSRCDIRS[@]}"
	do
	 IMPSRCNR=$((IMPSRCNR + 1))
	 if [ "$IMPSRCDIR" = "$EXPIMPLOC" ]; then IMPSRCNAME="current"; else IMPSRCNAME="backup/${IMPSRCDIR##*/}"; fi
	 IMPSRCDATE=$(expimp_meta "$IMPSRCDIR/exported_tables.conf" DATE)
	 IMPSRCSID=$(expimp_meta "$IMPSRCDIR/exported_tables.conf" SID)
	 IMPSRCCOUNT=$(grep -c '|RC=' "$IMPSRCDIR/exported_tables.conf")
	 [ "$IMPSRCNR" -eq 1 ] && IMPSRCSTATE=on || IMPSRCSTATE=off
	 IMPSRCLIST+=("$IMPSRCNR" "$IMPSRCNAME | ${IMPSRCDATE:-unknown date} | SID ${IMPSRCSID:-unknown} | $IMPSRCCOUNT exports" "$IMPSRCSTATE")
	done
	if ! IMPSRCNR=$(expimp_dialog --title "$global_title" --backtitle "$global_backtitle" --radiolist "Select the export to import (default is the newest):" @H@ @W@ @L@ "${IMPSRCLIST[@]}")
	 then
		echo "INFO: no export selected for import" >> "$EXPIMPLOGFILE"
		clear
		exit 29
	fi
	clear
	IMPSRCNR=$(echo "$IMPSRCNR" | tr -d '"')
	IMPSRC=${IMPSRCDIRS[$((IMPSRCNR - 1))]}
fi
echo "INFO: import from $IMPSRC" >> "$EXPIMPLOGFILE"

# set config files
exportedtables=$IMPSRC/exported_tables.conf
exportedtablesok=$IMPSRC/exported_tables_ok.conf

# check existing data
if [ -e "$exportedtablesok" ]
 then
	expimp_dialog --title "$global_title" --backtitle "$global_backtitle"  --yes-label "Continue" --no-label "Exit" --yesno  "There is the selection of a previous import in\n$IMPSRC\n\nIf you continue, this selection will be reset.\n(The export data is not changed.)" @H@ @W@
	case $? in
		0)
			echo "INFO: delete old files" >> "$EXPIMPLOGFILE"
			rm -f "$exportedtablesok"
			;;
		1)
			echo "INFO: exit because old run detected" >> "$EXPIMPLOGFILE"
			exit 21
			;;
		# check ESC hit
		*)	
			echo "INFO: exit because old run (ESC hit)" >> "$EXPIMPLOGFILE"
			exit 21
			;;
	esac
fi

# build list of OK exports for import (RC=0 or RC=4, order of the export is kept)
awk -F'|' '!/^#/ && ($2 == "RC=0" || $2 == "RC=4")' "$exportedtables" > "$exportedtablesok"
if [ ! -s "$exportedtablesok" ]
 then 
	echo "ERROR: no OK exports found for import" >> "$EXPIMPLOGFILE"
	exit 22
fi

# set config file and delete old one
importtables=$IMPSRC/selected_tables_import.conf
rm -f "$importtables"

# select exports to import
IMPORTLISTITEMS=()
while IFS='|' read -r IMPORTEDTABLE _
do
 IMPORTLISTITEMS+=("$IMPORTEDTABLE" "$IMPORTEDTABLE" on)
done < "$exportedtablesok"

# select exported tables for import
if ! expimp_dialog --title "$global_title" --backtitle "$global_backtitle" --separate-output --checklist "Select the exports to import:" @H@ @W@ @L@ "${IMPORTLISTITEMS[@]}" > "$importtables"
 then
	echo "ERROR: import select error" >> "$EXPIMPLOGFILE"
	exit 23
fi
clear 
if [ ! -s "$importtables" ]
 then 
	echo "ERROR: no exports selected for import" >> "$EXPIMPLOGFILE"
	exit 24
fi

if [ "$OS" = Linux ]
 then
  listcleaner=$IMPSRC/listcleaner.conf
  sed 's/\"//g' "$importtables" > "$listcleaner"
  mv "$listcleaner" "$importtables"
fi

# metadata of the source system (written by the export since version 1.10)
EXPSID=$(expimp_meta "$exportedtables" SID)
EXPHOST=$(expimp_meta "$exportedtables" HOST)
EXPCLIENTINFO=$(expimp_meta "$exportedtables" CLIENT)
EXPUSER=$(expimp_meta "$exportedtables" USER)
EXPDATE=$(expimp_meta "$exportedtables" DATE)
CURHOST=$(hostname)

# verify the SHA-256 checksums of the selected exports
echo "=== verify checksums ===" >> "$EXPIMPLOGFILE"
CHECKSUMERROR=""
while IFS= read -r SELTABLES
do
 EXPSHA256=$(awk -F'|' -v t="$SELTABLES" '$1 == t { for (i = 2; i <= NF; i++) if ($i ~ /^SHA256=/) { sub(/^SHA256=/, "", $i); print $i } }' "$exportedtablesok" | tail -1)
 if [ -z "$EXPSID" ]
  then
	# export of an older version without metadata and checksums
	echo "$SELTABLES|NO CHECKSUM (export of an older version)" >> "$EXPIMPLOGFILE"
 elif [ ! -f "$IMPSRC/$SELTABLES.dat" ]
  then
	echo "$SELTABLES|ERROR data file missing" >> "$EXPIMPLOGFILE"
	CHECKSUMERROR="$CHECKSUMERROR $SELTABLES"
 elif [ -z "$EXPSHA256" ] || [ "$(expimp_sha256 "$IMPSRC/$SELTABLES.dat")" != "$EXPSHA256" ]
  then
	echo "$SELTABLES|ERROR checksum mismatch" >> "$EXPIMPLOGFILE"
	CHECKSUMERROR="$CHECKSUMERROR $SELTABLES"
 else
	echo "$SELTABLES|checksum OK" >> "$EXPIMPLOGFILE"
 fi
done < "$importtables"
echo "=== verify checksums ===" >> "$EXPIMPLOGFILE"
if [ -n "$CHECKSUMERROR" ]
 then
	echo "ERROR: checksum verification failed:$CHECKSUMERROR" >> "$EXPIMPLOGFILE"
	expimp_dialog --title "$global_title" --backtitle "$global_backtitle" --ok-label "EXIT" --msgbox "Checksum verification FAILED - nothing was imported!\n\nThe data files of these exports are missing or were changed after the export:\n\n$CHECKSUMERROR\n\nDetails can be found in $EXPIMPLOGFILE" @H@ @W@
	clear
	exit 27
fi

# confirm the import (show source and target system)
IMPORTWARNING=""
CONFIRMSID=no
if [ -z "$EXPSID" ]
 then
	IMPORTWARNING="$IMPORTWARNING\nWARNING: export of an older version without metadata and checksums,\n         the source system and the data files cannot be verified!\n"
	CONFIRMSID=yes
elif [ "$EXPSID" != "$SAPSYSTEMNAME" ]
 then
	IMPORTWARNING="$IMPORTWARNING\nWARNING: SAPSYSTEM MISMATCH - the export was created on $EXPSID!\n"
fi
if [ -n "$EXPHOST" ] && [ "$EXPHOST" != "$CURHOST" ]
 then
	IMPORTWARNING="$IMPORTWARNING\nINFO: the export was created on another host ($EXPHOST)\n"
fi
IMPORTLIST=$(tr '\n' ' ' < "$importtables")
if ! expimp_dialog --title "$global_title" --backtitle "$global_backtitle" --defaultno --yes-label "Import" --no-label "Exit" --yesno "Export: $IMPSRC\n\nYou are going to IMPORT into\n\n  SAPSYSTEM: $SAPSYSTEMNAME | HOST: $CURHOST\n\nThe export was created on\n\n  SAPSYSTEM: ${EXPSID:-unknown} | HOST: ${EXPHOST:-unknown} | CLIENT: ${EXPCLIENTINFO:-unknown}\n  USER: ${EXPUSER:-unknown} | DATE: ${EXPDATE:-unknown}\n$IMPORTWARNING\nSelected exports:\n$IMPORTLIST\n\nThe existing content of these tables will be DELETED and replaced!\n\nContinue with the import?" @H@ @W@
 then
	echo "INFO: import not confirmed" >> "$EXPIMPLOGFILE"
	clear
	exit 28
fi
if [ "$CONFIRMSID" = yes ]
 then
	if ! TYPEDSID=$(expimp_dialog --title "$global_title" --backtitle "$global_backtitle" --inputbox "The export was created by an older version - the source system and the data files could not be verified!\n\nType the SID of this system ($SAPSYSTEMNAME) to confirm the import:" @H@ @W@) || [ "$TYPEDSID" != "$SAPSYSTEMNAME" ]
	 then
		echo "INFO: import not confirmed (SID not confirmed)" >> "$EXPIMPLOGFILE"
		clear
		exit 28
	fi
fi
clear
echo "INFO: import confirmed (source: SID=${EXPSID:-unknown} HOST=${EXPHOST:-unknown} DATE=${EXPDATE:-unknown})" >> "$EXPIMPLOGFILE"

# info file
importedtables=$IMPSRC/imported_tables.conf
{
 echo "# Template name | Return Code of Import"
 echo "# ====================================="
 echo "# Imported from:"
 echo "# $IMPSRC"
 echo "# ====================================="
} > "$importedtables"

# import tables (with progress: number of the export / number of exports)
IMPTOTAL=$(grep -c . "$importtables")
expimp_progressbox "Import selected tables ($IMPTOTAL exports)" < <(
IMPNR=0
while IFS= read -r SELTABLES
do
 IMPNR=$((IMPNR + 1))
 echo "=== Import $IMPNR/$IMPTOTAL: $SELTABLES ==="
 # R3trans error output is shown in the progress box too
 R3trans -w "$IMPSRC/$SELTABLES.imp.log" -i "$IMPSRC/$SELTABLES.dat" 2>&1
 IMPRC=$?
 echo "$SELTABLES|RC=$IMPRC" >> "$importedtables"
 echo "=== Import END $SELTABLES (RC=$IMPRC) ==="
 echo "=== $(expimp_progress_bar "$IMPNR" "$IMPTOTAL") done ==="
 echo ""
 sleep 1
done < "$importtables"
echo "# =====================================" >> "$importedtables"
)

# logfile info
{
 echo "=== imported tables ==="
 cat "$importedtables"
 echo "=== imported tables ==="
} >> "$EXPIMPLOGFILE"

# import info
if ! expimp_dialog --title "$global_title" --backtitle "$global_backtitle" --exit-label "Continue" --textbox "$importedtables" @H@ @W@
 then
	echo "ERROR: import info error" >> "$EXPIMPLOGFILE"
	exit 26
fi 
clear

# highest return code of R3trans (RC >= 8 is an error)
IMPMAXRC=$(awk -F'|' '!/^#/ && NF > 1 { rc = $2; sub(/^RC=/, "", rc); if (rc !~ /^[0-9]+$/) rc = 12; if (rc + 0 > max) max = rc + 0 } END { print max + 0 }' "$importedtables")
if [ "$IMPMAXRC" -ge 8 ]
 then
	echo "ERROR: error while import (highest RC=$IMPMAXRC, see imported tables)" >> "$EXPIMPLOGFILE"
	exit 25
fi

echo "=== import finished ===" >> "$EXPIMPLOGFILE"
exit 0
