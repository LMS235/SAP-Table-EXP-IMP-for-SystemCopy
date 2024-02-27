#!/bin/bash
# SAP(R) Table EXP/IMP for SystemCopy (c) Florian Lamml 2024
# www.florian-lamml.de
# Version 1.0 - Initial Release
# Version 1.1 - Client Config
# Version 1.2 - New Tables
# Version 1.3 - Template Correction
# Version 1.4 - Minor Corrections

# set config file and delete old one
export exportedtables=$EXPIMPLOC/exported_tables.conf
if [ $(cat $exportedtables | wc -l) -eq 0 ]
 then 
	echo "ERROR: no exports found for import" >> $EXPIMPLOGFILE
	exit 20
fi

# set config file
export exportedtablesok=$EXPIMPLOC/exported_tables_ok.conf

# check existing data
if [ -e $exportedtablesok ]
 then
	dialog --title "$global_title" --backtitle "$global_backtitle"  --yes-label "Continue" --no-label "Exit" --yesno  "There are import files in $EXPIMPLOC\nIf you continue these files will be deleted!" $global_height $global_width 
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
export templist=$EXPIMPLOC/templist.conf
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
export importtables=$EXPIMPLOC/selected_tables_import.conf
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
dialog --title "$global_title" --backtitle "$global_backtitle" --separate-output --checklist "Select the exports to import:" $global_height $global_width 24 ${IMPORTEDTABLES[@]:1:$IMPORTEDTABLESCOUNTER} 2> $importtables
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
  export listcleaner=$EXPIMPLOC/listcleaner.conf
  sed 's/\"//g' $importtables >> $listcleaner
  mv $listcleaner $importtables
fi

# export info file
export importedtables=$EXPIMPLOC/imported_tables.conf
[ -e $importedtables ] && rm $importedtables

# info file
echo "# Template name | Return Code of Export" >> $importedtables
echo "# =====================================" >> $importedtables
echo "# Imported from:" >> $importedtables
echo "# "$EXPIMPLOC >> $importedtables
echo "# =====================================" >> $importedtables

# import tables
dialog --title "$global_title" --backtitle "$global_backtitle" --progressbox "Import selected tables"  $global_height $global_width < <(
while read SELTABLES
do
 echo "=== Import START" $SELTABLES "==="
 R3trans -w $EXPIMPLOC/$SELTABLES.imp.log -i $EXPIMPLOC/$SELTABLES.dat
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