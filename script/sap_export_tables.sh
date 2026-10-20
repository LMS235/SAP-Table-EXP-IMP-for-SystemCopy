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
# Version 2.0 - Completely redesigned with new features and security options
# Version 2.0.1 - Customizing Dialog Box Colors

# the export script must be started by sap_tab_exp_imp.sh (config, checks, logfile)
if [ -z "$EXPIMPLOC" ] || [ -z "$EXPIMPLOGFILE" ] || [ -z "$SHA256TOOL" ]
 then
	echo "This script must be started by sap_tab_exp_imp.sh!"
	echo "... EXIT NOW"
	exit 90
fi

# helper functions (checksums, files of a previous run)
# shellcheck source=script/sap_expimp_lib.sh
. "$(dirname "$0")/sap_expimp_lib.sh"

# set config file
selectedtablesforexport=$EXPIMPLOC/selected_tables_for_export.conf
exportedtables=$EXPIMPLOC/exported_tables.conf

# check existing data of a previous run - copy it to a backup directory before it is deleted
OLDRUNFILES=$(expimp_run_files)
if [ -n "$OLDRUNFILES" ]
 then
	BACKUPDIR=$EXPIMPLOC/backup/$(date "+%Y%m%d_%H%M%S")
	BACKUPKEEPINFO=""
	[ "$BACKUPKEEP" -gt 0 ] && BACKUPKEEPINFO="\n\nOnly the newest $BACKUPKEEP backups are kept (BACKUPKEEP),\nolder backups will be deleted!"
	expimp_dialog --title "$global_title" --backtitle "$global_backtitle"  --yes-label "Continue" --no-label "Exit" --yesno  "There are files of a previous run in $EXPIMPLOC\n\nIf you continue these files will be copied to\n$BACKUPDIR\nand then deleted!$BACKUPKEEPINFO" @H@ @W@
	CONTINUE=$?
	case $CONTINUE in
		0)
			echo "INFO: backup old files to $BACKUPDIR" >> "$EXPIMPLOGFILE"
			if ! mkdir -p "$BACKUPDIR" || ! echo "$OLDRUNFILES" | while IFS= read -r OLDFILE; do cp -p "$OLDFILE" "$BACKUPDIR/" || exit 1; done
			 then
				echo "ERROR: backup of the previous run to $BACKUPDIR failed, nothing deleted" >> "$EXPIMPLOGFILE"
				exit 15
			fi
			# the info files in the backup show the backup directory as location
			for INFOFILE in "$BACKUPDIR/exported_tables.conf" "$BACKUPDIR/imported_tables.conf"
			do
			 [ -f "$INFOFILE" ] || continue
			 awk -v d="$BACKUPDIR" '{ if (prev == "# Exported to:" || prev == "# Imported from:") print "# " d; else print; prev = $0 }' "$INFOFILE" > "$INFOFILE.tmp" && mv "$INFOFILE.tmp" "$INFOFILE"
			done
			echo "INFO: delete old files" >> "$EXPIMPLOGFILE"
			echo "$OLDRUNFILES" | while IFS= read -r OLDFILE; do rm -f "$OLDFILE"; done
			# keep only the newest BACKUPKEEP backups (0 = unlimited)
			if [ "$BACKUPKEEP" -gt 0 ]
			 then
				OLDBACKUPS=()
				for OLDBACKUP in "$EXPIMPLOC"/backup/[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]_[0-9][0-9][0-9][0-9][0-9][0-9]
				do
				 [ -d "$OLDBACKUP" ] && OLDBACKUPS+=("$OLDBACKUP")
				done
				OLDBACKUPNR=0
				while [ "$OLDBACKUPNR" -lt $((${#OLDBACKUPS[@]} - BACKUPKEEP)) ]
				do
				 if rm -rf "${OLDBACKUPS[$OLDBACKUPNR]}"
				  then
					echo "INFO: delete old backup ${OLDBACKUPS[$OLDBACKUPNR]} (BACKUPKEEP=$BACKUPKEEP)" >> "$EXPIMPLOGFILE"
				 else
					echo "WARNING: cannot delete old backup ${OLDBACKUPS[$OLDBACKUPNR]}" >> "$EXPIMPLOGFILE"
				 fi
				 OLDBACKUPNR=$((OLDBACKUPNR + 1))
				done
			fi
			;;
		1)
			echo "INFO: exit because old run detected" >> "$EXPIMPLOGFILE"
			exit 10
			;;
		# check ESC hit
		*)	
			echo "INFO: exit because old run (ESC hit)" >> "$EXPIMPLOGFILE"
			exit 10
			;;
	esac
fi
 
# search templates
TEMPLATELIST=()
for TEMPLATEFILE in "$global_pwd"/templates/*
do
  [ -f "$TEMPLATEFILE" ] || continue
  TEMPLATE=${TEMPLATEFILE##*/}
  # empty templates (no statements) are marked, they are skipped by the export
  if grep -q '[^[:space:]]' "$TEMPLATEFILE"
   then
	TEMPLATELIST+=("$TEMPLATE" "$TEMPLATE" off)
  else
	TEMPLATELIST+=("$TEMPLATE" "$TEMPLATE (empty)" off)
  fi
done

# select the templates
if ! expimp_dialog --title "$global_title" --backtitle "$global_backtitle" --separate-output --checklist "Select the Templates for Export:" @H@ @W@ @L@ "${TEMPLATELIST[@]}" > "$selectedtablesforexport"
 then
    echo "ERROR: fail to select templates for export" >> "$EXPIMPLOGFILE"
	rm -f "$selectedtablesforexport"
	exit 11
fi 
clear
if [ ! -s "$selectedtablesforexport" ]
 then 
	echo "ERROR: no template selected for export" >> "$EXPIMPLOGFILE"
	rm -f "$selectedtablesforexport"
	exit 12
fi

if [ "$OS" = Linux ]
 then
  listcleaner=$EXPIMPLOC/listcleaner.conf
  sed 's/\"//g' "$selectedtablesforexport" > "$listcleaner"
  mv "$listcleaner" "$selectedtablesforexport"
fi

# logfile info
{
 echo "=== selected tables for export ==="
 cat "$selectedtablesforexport"
 echo "=== selected tables for export ==="
} >> "$EXPIMPLOGFILE"

# info file (with metadata of the source system - checked by the import)
{
 echo "# Template name | Return Code of Export | SHA-256 of the data file"
 echo "# ====================================="
 echo "# Exported to:"
 echo "# $EXPIMPLOC"
 echo "# ====================================="
 echo "# SID=$SAPSYSTEMNAME"
 echo "# HOST=$(hostname)"
 echo "# CLIENT=$EXPCLIENT"
 echo "# USER=$CURUSER"
 echo "# DATE=$(date "+%Y-%m-%d %H:%M:%S")"
 echo "# ====================================="
} > "$exportedtables"

# check STMS_QA export
if grep -qx STMS_QA "$selectedtablesforexport"
then
 expimp_dialog --title "$global_title" --backtitle "$global_backtitle" --ok-label "Continue" --msgbox "You are going to export STMS_QA \n\n Please refresh STMS_QA before continue" @H@ @W@
 # check ESC hit
 if [ $? -eq 255 ];
 then
	exit 96
 fi
fi

# export and export dialog (with progress: number of the template / number of templates)
EXPTOTAL=$(grep -c . "$selectedtablesforexport")
expimp_progressbox "Export SAP Tables ($EXPTOTAL templates)" < <(
EXPNR=0
while IFS= read -r SELTABLES
do
 EXPNR=$((EXPNR + 1))
 echo "=== Export $EXPNR/$EXPTOTAL: $SELTABLES ==="
 if [ ! -f "$global_pwd/templates/$SELTABLES" ]
  then
	echo "=== Export SKIPPED $SELTABLES (template missing) ==="
	echo "$SELTABLES|RC=TEMPLATE_MISSING|SHA256=" >> "$exportedtables"
	echo "=== $(expimp_progress_bar "$EXPNR" "$EXPTOTAL") done ==="
	echo ""
	continue
 fi
 if ! grep -q '[^[:space:]]' "$global_pwd/templates/$SELTABLES"
  then
	echo "=== Export SKIPPED $SELTABLES (template empty) ==="
	echo "$SELTABLES|RC=TEMPLATE_EMPTY|SHA256=" >> "$exportedtables"
	echo "=== $(expimp_progress_bar "$EXPNR" "$EXPTOTAL") done ==="
	echo ""
	continue
 fi
 {
  echo "export"
  echo "client = $EXPCLIENT"
  [ "$PARALLEL" -ne 0 ] && echo "parallel = $PARALLEL"
  echo "file = '$EXPIMPLOC/$SELTABLES.dat'"
  # every line with a line break (also the last line of a template without one)
  awk '1' "$global_pwd/templates/$SELTABLES"
 } > "$EXPIMPLOC/$SELTABLES.tpl"
 # R3trans error output is shown in the progress box too
 R3trans -w "$EXPIMPLOC/$SELTABLES.exp.log" "$EXPIMPLOC/$SELTABLES.tpl" 2>&1
 EXPRC=$?
 EXPSHA256=""
 [ -f "$EXPIMPLOC/$SELTABLES.dat" ] && EXPSHA256=$(expimp_sha256 "$EXPIMPLOC/$SELTABLES.dat")
 echo "$SELTABLES|RC=$EXPRC|SHA256=$EXPSHA256" >> "$exportedtables"
 echo "=== Export END $SELTABLES (RC=$EXPRC) ==="
 echo "=== $(expimp_progress_bar "$EXPNR" "$EXPTOTAL") done ==="
 echo ""
 sleep 1
done < "$selectedtablesforexport"
echo "# =====================================" >> "$exportedtables"
)

# logfile info
{
 echo "=== exported tables ==="
 cat "$exportedtables"
 echo "=== exported tables ==="
} >> "$EXPIMPLOGFILE"

# export info
if ! expimp_dialog --title "$global_title" --backtitle "$global_backtitle" --exit-label "Continue" --textbox "$exportedtables" @H@ @W@
 then
	echo "ERROR: export info error" >> "$EXPIMPLOGFILE"
	exit 14
fi 
clear

# highest return code of R3trans (RC >= 8 or a missing template is an error, an empty template is not)
EXPMAXRC=$(awk -F'|' '!/^#/ && NF > 1 { rc = $2; sub(/^RC=/, "", rc); if (rc == "TEMPLATE_EMPTY") rc = 0; else if (rc !~ /^[0-9]+$/) rc = 12; if (rc + 0 > max) max = rc + 0 } END { print max + 0 }' "$exportedtables")
if [ "$EXPMAXRC" -ge 8 ]
 then
	echo "ERROR: error while export (highest RC=$EXPMAXRC, see exported tables)" >> "$EXPIMPLOGFILE"
	exit 13
fi

echo "=== export finished ===" >> "$EXPIMPLOGFILE"
exit 0
