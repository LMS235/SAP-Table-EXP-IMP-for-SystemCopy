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

# helper functions (checksums, metadata)
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
if [ ${#IMPSRCDIRS[@]} -eq 0 ]
 then 
	echo "ERROR: no exports found for import" >> $EXPIMPLOGFILE
	exit 20
fi

# select the export to import if there is more than one (default is the newest)
IMPSRC=${IMPSRCDIRS[0]}
if [ ${#IMPSRCDIRS[@]} -gt 1 ]
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
	 [ $IMPSRCNR -eq 1 ] && IMPSRCSTATE=on || IMPSRCSTATE=off
	 IMPSRCLIST+=("$IMPSRCNR" "$IMPSRCNAME | ${IMPSRCDATE:-unknown date} | SID ${IMPSRCSID:-unknown} | $IMPSRCCOUNT exports" "$IMPSRCSTATE")
	done
	IMPSRCNR=$(dialog --title "$global_title" --backtitle "$global_backtitle" --radiolist "Select the export to import (default is the newest):" $global_height $global_width $global_list "${IMPSRCLIST[@]}" 2>&1 >/dev/tty)
	if [ $? -ne 0 ]
	 then
		echo "INFO: no export selected for import" >> $EXPIMPLOGFILE
		clear
		exit 29
	fi
	clear
	IMPSRCNR=$(echo "$IMPSRCNR" | tr -d '"')
	IMPSRC=${IMPSRCDIRS[$((IMPSRCNR - 1))]}
fi
echo "INFO: import from $IMPSRC" >> $EXPIMPLOGFILE

# set config file
export exportedtables=$IMPSRC/exported_tables.conf

# set config file
export exportedtablesok=$IMPSRC/exported_tables_ok.conf

# check existing data
if [ -e $exportedtablesok ]
 then
	dialog --title "$global_title" --backtitle "$global_backtitle"  --yes-label "Continue" --no-label "Exit" --yesno  "There are import files in $IMPSRC\nIf you continue these files will be deleted!" $global_height $global_width 
	CONTINUE=$?
	for choice in $CONTINUE
	do
		case $choice in
			0)
				echo "INFO: delete old files" >> $EXPIMPLOGFILE
				rm $exportedtablesok
				;;
			1)
				echo "INFO: exit because old run detected" >> $EXPIMPLOGFILE
				exit 21
				;;
			# check ESC hit
			255)	
				echo "INFO: exit because old run (ESC hit)" >> $EXPIMPLOGFILE
				exit 21
				;;
		esac
	done
fi

# build list of OK exports for import
export templist=$IMPSRC/templist.conf
[ -e $templist ] && rm $templist
cat $exportedtables | sed -ne '/^[^#].*/p' >> $templist
cat $templist | grep RC=0 >> $exportedtablesok 
cat $templist | grep RC=4 >> $exportedtablesok 
[ -e $templist ] && rm $templist
if [ $(cat $exportedtablesok | wc -l) -eq 0 ]
 then 
	echo "ERROR: no OK exports found for import" >> $EXPIMPLOGFILE
	exit 22
fi

# set config file and delete old one
export importtables=$IMPSRC/selected_tables_import.conf
[ -e $importtables ] && rm $importtables

# select exports to import
IMPORTEDTABLESCOUNTER=0
while read IMPORTEDTABLES
do
 IMPORTEDTABLESCOUNTER=$(expr $IMPORTEDTABLESCOUNTER + 1)
 IMPORTEDTABLES=$(echo "$IMPORTEDTABLES" | awk -F\| '{ printf $1}')
 IMPORTEDTABLES[$IMPORTEDTABLESCOUNTER]="$IMPORTEDTABLES $IMPORTEDTABLES on"
done < $exportedtablesok

# select exported tables for import
dialog --title "$global_title" --backtitle "$global_backtitle" --separate-output --checklist "Select the exports to import:" $global_height $global_width $global_list ${IMPORTEDTABLES[@]:1:$IMPORTEDTABLESCOUNTER} 2> $importtables
if [ $? -ne 0 ]
 then
	echo "ERROR: import select error" >> $EXPIMPLOGFILE
	exit 23
fi
clear 
if [ $(cat $importtables | wc -l) -eq 0 ]
 then 
	echo "ERROR: no exports selected for import" >> $EXPIMPLOGFILE
	exit 24
fi

if [ $OS == Linux ]
 then
  export listcleaner=$IMPSRC/listcleaner.conf
  sed 's/\"//g' $importtables >> $listcleaner
  mv $listcleaner $importtables
fi

# metadata of the source system (written by the export since version 1.10)
EXPSID=$(expimp_meta $exportedtables SID)
EXPHOST=$(expimp_meta $exportedtables HOST)
EXPCLIENTINFO=$(expimp_meta $exportedtables CLIENT)
EXPUSER=$(expimp_meta $exportedtables USER)
EXPDATE=$(expimp_meta $exportedtables DATE)
CURHOST=$(hostname)

# verify the SHA-256 checksums of the selected exports
echo "=== verify checksums ===" >> $EXPIMPLOGFILE
CHECKSUMERROR=""
while IFS= read -r SELTABLES
do
 EXPSHA256=$(awk -F'|' -v t="$SELTABLES" '$1 == t { for (i = 2; i <= NF; i++) if ($i ~ /^SHA256=/) { sub(/^SHA256=/, "", $i); print $i } }' $exportedtablesok | tail -1)
 if [ -z "$EXPSID" ]
  then
	# export of an older version without metadata and checksums
	echo "$SELTABLES|NO CHECKSUM (export of an older version)" >> $EXPIMPLOGFILE
 elif [ ! -f "$IMPSRC/$SELTABLES.dat" ]
  then
	echo "$SELTABLES|ERROR data file missing" >> $EXPIMPLOGFILE
	CHECKSUMERROR="$CHECKSUMERROR $SELTABLES"
 elif [ -z "$EXPSHA256" ] || [ "$(expimp_sha256 "$IMPSRC/$SELTABLES.dat")" != "$EXPSHA256" ]
  then
	echo "$SELTABLES|ERROR checksum mismatch" >> $EXPIMPLOGFILE
	CHECKSUMERROR="$CHECKSUMERROR $SELTABLES"
 else
	echo "$SELTABLES|checksum OK" >> $EXPIMPLOGFILE
 fi
done < $importtables
echo "=== verify checksums ===" >> $EXPIMPLOGFILE
if [ -n "$CHECKSUMERROR" ]
 then
	echo "ERROR: checksum verification failed:$CHECKSUMERROR" >> $EXPIMPLOGFILE
	dialog --title "$global_title" --backtitle "$global_backtitle" --ok-label "EXIT" --msgbox "Checksum verification FAILED - nothing was imported!\n\nThe data files of these exports are missing or were changed after the export:\n\n$CHECKSUMERROR\n\nDetails can be found in $EXPIMPLOGFILE" $global_height $global_width
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
IMPORTLIST=$(tr '\n' ' ' < $importtables)
dialog --title "$global_title" --backtitle "$global_backtitle" --defaultno --yes-label "Import" --no-label "Exit" --yesno "Export: $IMPSRC\n\nYou are going to IMPORT into\n\n  SAPSYSTEM: $SAPSYSTEMNAME | HOST: $CURHOST\n\nThe export was created on\n\n  SAPSYSTEM: ${EXPSID:-unknown} | HOST: ${EXPHOST:-unknown} | CLIENT: ${EXPCLIENTINFO:-unknown}\n  USER: ${EXPUSER:-unknown} | DATE: ${EXPDATE:-unknown}\n$IMPORTWARNING\nSelected exports:\n$IMPORTLIST\n\nThe existing content of these tables will be DELETED and replaced!\n\nContinue with the import?" $global_height $global_width
if [ $? -ne 0 ]
 then
	echo "INFO: import not confirmed" >> $EXPIMPLOGFILE
	clear
	exit 28
fi
if [ "$CONFIRMSID" = yes ]
 then
	TYPEDSID=$(dialog --title "$global_title" --backtitle "$global_backtitle" --inputbox "The export was created by an older version - the source system and the data files could not be verified!\n\nType the SID of this system ($SAPSYSTEMNAME) to confirm the import:" $global_height $global_width 2>&1 >/dev/tty)
	if [ $? -ne 0 ] || [ "$TYPEDSID" != "$SAPSYSTEMNAME" ]
	 then
		echo "INFO: import not confirmed (SID not confirmed)" >> $EXPIMPLOGFILE
		clear
		exit 28
	fi
fi
clear
echo "INFO: import confirmed (source: SID=${EXPSID:-unknown} HOST=${EXPHOST:-unknown} DATE=${EXPDATE:-unknown})" >> $EXPIMPLOGFILE

# export info file
export importedtables=$IMPSRC/imported_tables.conf
[ -e $importedtables ] && rm $importedtables

# info file
echo "# Template name | Return Code of Import" >> $importedtables
echo "# =====================================" >> $importedtables
echo "# Imported from:" >> $importedtables
echo "# "$IMPSRC >> $importedtables
echo "# =====================================" >> $importedtables

# import tables
dialog --title "$global_title" --backtitle "$global_backtitle" --progressbox "Import selected tables"  $global_height $global_width < <(
while read SELTABLES
do
 echo "=== Import START" $SELTABLES "==="
 R3trans -w $IMPSRC/$SELTABLES.imp.log -i $IMPSRC/$SELTABLES.dat
 echo $SELTABLES"|RC="$? >> $importedtables
 echo "=== Import END" $SELTABLES "==="
 echo ""
 sleep 1
done < $importtables
if [ $? -ne 0 ]
 then
	echo "ERROR: error while import" >> $EXPIMPLOGFILE
	exit 25
fi 
echo "# =====================================" >> $importedtables
clear
)

# logfile info
echo "=== imported tables ===" >> $EXPIMPLOGFILE
cat $importedtables >> $EXPIMPLOGFILE
echo "=== imported tables ===" >> $EXPIMPLOGFILE

# import info
dialog --title "$global_title" --backtitle "$global_backtitle" --exit-label "Continue" --textbox $importedtables $global_height $global_width
if [ $? -ne 0 ]
 then
	echo "ERROR: import info error" >> $EXPIMPLOGFILE
	exit 26
fi 
clear

echo "=== import finished ===" >> $EXPIMPLOGFILE
exit 0
