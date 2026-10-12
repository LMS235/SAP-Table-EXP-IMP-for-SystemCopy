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

# helper functions (checksums, files of a previous run)
. "$(dirname "$0")/sap_expimp_lib.sh"

# set config file
export selectedtablesforexport=$EXPIMPLOC/selected_tables_for_export.conf
export exportedtables=$EXPIMPLOC/exported_tables.conf

# check existing data of a previous run - copy it to a backup directory before it is deleted
OLDRUNFILES=$(expimp_run_files)
if [ -n "$OLDRUNFILES" ]
 then
	BACKUPDIR=$EXPIMPLOC/backup/$(date "+%Y%m%d_%H%M%S")
	dialog --title "$global_title" --backtitle "$global_backtitle"  --yes-label "Continue" --no-label "Exit" --yesno  "There are files of a previous run in $EXPIMPLOC\n\nIf you continue these files will be copied to\n$BACKUPDIR\nand then deleted!" $global_height $global_width 
	CONTINUE=$?
	case $CONTINUE in
		0)
			echo "INFO: backup old files to $BACKUPDIR" >> $EXPIMPLOGFILE
			if ! mkdir -p "$BACKUPDIR" || ! echo "$OLDRUNFILES" | while IFS= read -r OLDFILE; do cp -p "$OLDFILE" "$BACKUPDIR/" || exit 1; done
			 then
				echo "ERROR: backup of the previous run to $BACKUPDIR failed, nothing deleted" >> $EXPIMPLOGFILE
				exit 15
			fi
			echo "INFO: delete old files" >> $EXPIMPLOGFILE
			echo "$OLDRUNFILES" | while IFS= read -r OLDFILE; do rm -f "$OLDFILE"; done
			;;
		1)
			echo "INFO: exit because old run detected" >> $EXPIMPLOGFILE
			exit 10
			;;
		# check ESC hit
		*)	
			echo "INFO: exit because old run (ESC hit)" >> $EXPIMPLOGFILE
			exit 10
			;;
	esac
fi
 
# search templates
TEMPLATECOUNTER=0
TEMPLATES=$global_pwd/templates/*
for TEMPLATES in $TEMPLATES
do
  TEMPLATECOUNTER=$(expr $TEMPLATECOUNTER + 1)
  TEMPLATE=$(echo "$TEMPLATES" | awk -F/ '{ printf $NF"\n" }')
  TEMPLATE[$TEMPLATECOUNTER]="$TEMPLATE $TEMPLATE off"
done

# selet the templates
dialog --title "$global_title" --backtitle "$global_backtitle" --separate-output --checklist "Select the Templates for Export:" $global_height $global_width $global_list ${TEMPLATE[@]:1:$TEMPLATECOUNTER} 2> $selectedtablesforexport
if [ $? -ne 0 ]
 then
    echo "ERROR: fail to select templates for export" >> $EXPIMPLOGFILE
	rm -f $selectedtablesforexport
	exit 11
fi 
clear
if [ $(cat $selectedtablesforexport | wc -l) -eq 0 ]
 then 
	echo "ERROR: no template selected for export" >> $EXPIMPLOGFILE
	rm -f $selectedtablesforexport
	exit 12
fi

if [ $OS == Linux ]
 then
  export listcleaner=$EXPIMPLOC/listcleaner.conf
  sed 's/\"//g' $selectedtablesforexport >> $listcleaner
  mv $listcleaner $selectedtablesforexport
fi

# logfile info
echo "=== selected tables for export ===" >> $EXPIMPLOGFILE
cat $selectedtablesforexport >> $EXPIMPLOGFILE
echo "=== selected tables for export ===" >> $EXPIMPLOGFILE

# info file (with metadata of the source system - checked by the import)
echo "# Template name | Return Code of Export | SHA-256 of the data file" > $exportedtables
echo "# =====================================" >> $exportedtables
echo "# Exported to:" >> $exportedtables
echo "# "$EXPIMPLOC >> $exportedtables
echo "# =====================================" >> $exportedtables
echo "# SID=$SAPSYSTEMNAME" >> $exportedtables
echo "# HOST=$(hostname)" >> $exportedtables
echo "# CLIENT=$EXPCLIENT" >> $exportedtables
echo "# USER=$CURUSER" >> $exportedtables
echo "# DATE=$(date "+%Y-%m-%d %H:%M:%S")" >> $exportedtables
echo "# =====================================" >> $exportedtables

# check STMS_QA export
if [ $(grep STMS_QA $selectedtablesforexport | wc -l) -ge 1 ]
then
 dialog --title "$global_title" --backtitle "$global_backtitle" --exit-label "Continue" --msgbox "You are going to export STMS_QA \n\n Please refresh STMS_QA before continue" $global_height $global_width
 # check ESC hit
 if [ $? -eq 255 ];
 then
	exit 96
 fi
fi

# export and export dialog
dialog --title "$global_title" --backtitle "$global_backtitle" --progressbox "Export SAP Tables"  $global_height $global_width < <(
while read SELTABLES
do
 echo "export" >> $EXPIMPLOC/$SELTABLES.tpl
 echo "client = "$EXPCLIENT"" >> $EXPIMPLOC/$SELTABLES.tpl
 if [ "${PARALLEL}" -ne 0 ]; then
  echo "parallel = "$PARALLEL >> $EXPIMPLOC/$SELTABLES.tpl
 fi
 echo "file = '"$EXPIMPLOC"/"$SELTABLES".dat'" >> $EXPIMPLOC/$SELTABLES.tpl
 cat $global_pwd/templates/$SELTABLES >> $EXPIMPLOC/$SELTABLES.tpl
 echo "=== Export START" $SELTABLES "==="
 R3trans -w $EXPIMPLOC/$SELTABLES.exp.log $EXPIMPLOC/$SELTABLES.tpl
 EXPRC=$?
 EXPSHA256=""
 [ -f "$EXPIMPLOC/$SELTABLES.dat" ] && EXPSHA256=$(expimp_sha256 "$EXPIMPLOC/$SELTABLES.dat")
 echo "$SELTABLES|RC=$EXPRC|SHA256=$EXPSHA256" >> $exportedtables
 echo "=== Export END" $SELTABLES "==="
 echo ""
 sleep 1
done < $selectedtablesforexport
if [ $? -ne 0 ]
 then
	echo "ERROR: error while export" >> $EXPIMPLOGFILE
	exit 13
fi 
echo "# =====================================" >> $exportedtables
clear
)

# logfile info
echo "=== exported tables ===" >> $EXPIMPLOGFILE
cat $exportedtables >> $EXPIMPLOGFILE
echo "=== exported tables ===" >> $EXPIMPLOGFILE

# export info
dialog --title "$global_title" --backtitle "$global_backtitle" --exit-label "Continue" --textbox $exportedtables $global_height $global_width
if [ $? -ne 0 ]
 then
	echo "ERROR: export info error" >> $EXPIMPLOGFILE
	exit 14
fi 
clear

echo "=== export finished ===" >> $EXPIMPLOGFILE
exit 0