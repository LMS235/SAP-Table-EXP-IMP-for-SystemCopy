#!/bin/bash
# SAP Table EXP/IMP for SystemCopy (c) Florian Lamml 2015
# www.florian-lamml.de
# Version 1.0 - Initial Release

# set config file and delete old one
export selectedtablesforexport=$EXPIMPLOC/selected_tables_for_export.conf
export exportedtables=$EXPIMPLOC/exported_tables.conf

# check existing data
if [ -e $selectedtablesforexport ]
 then
	dialog --title "$global_title" --backtitle "$global_backtitle"  --yes-label "Continue" --no-label "Exit" --yesno  "There are export files in $EXPIMPLOC\nIf you continue these files will be deleted!" $global_height $global_width 
	CONTINUE=$?
	for choice in $CONTINUE
	do
		case $choice in
			0)
				echo "INFO: delete old files" >> $EXPIMPLOGFILE
				rm $selectedtablesforexport
				[ -e $exportedtables ] && rm $exportedtables
				;;
			1)
				echo "INFO: exit because old run detected" >> $EXPIMPLOGFILE
				exit 10
				;;
			# check ESC hit
			255)	
				echo "INFO: exit because old run (ESC hit)" >> $EXPIMPLOGFILE
				exit 10
				;;
		esac
	done
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
dialog --title "$global_title" --backtitle "$global_backtitle" --separate-output --checklist "Select the Templates for Export:" $global_height $global_width 24 ${TEMPLATE[@]:1:$TEMPLATECOUNTER} 2> $selectedtablesforexport
if [ $? -ne 0 ]
 then
    echo "ERROR: fail to select templates for export" >> $EXPIMPLOGFILE
	exit 11
fi 
clear
if [ $(cat $selectedtablesforexport | wc -l) -eq 0 ]
 then 
	echo "ERROR: no template selected for export" >> $EXPIMPLOGFILE
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

# delete old exports
rm $EXPIMPLOC/*.tpl > /dev/null 2>&1
rm $EXPIMPLOC/*.exp.log > /dev/null 2>&1
rm $EXPIMPLOC/*.dat > /dev/null 2>&1

# info file
echo "# Template name | Return Code of Export" >> $exportedtables
echo "# =====================================" >> $exportedtables
echo "# Exported to:" >> $exportedtables
echo "# "$EXPIMPLOC >> $exportedtables
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
 echo "client = '"$EXPCLIENT"'" >> $EXPIMPLOC/$SELTABLES.tpl
 echo "file = '"$EXPIMPLOC"/"$SELTABLES".dat'" >> $EXPIMPLOC/$SELTABLES.tpl
 cat $global_pwd/templates/$SELTABLES >> $EXPIMPLOC/$SELTABLES.tpl
 echo "=== Export START" $SELTABLES "==="
 R3trans -w $EXPIMPLOC/$SELTABLES.exp.log $EXPIMPLOC/$SELTABLES.tpl
 echo $SELTABLES"|RC="$? >> $exportedtables
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