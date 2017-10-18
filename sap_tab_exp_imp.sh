#!/bin/bash
# SAP Table EXP/IMP for SystemCopy (c) Florian Lamml 2015
# www.florian-lamml.de
# Version 1.0 - Initial Release

##### CONFIG EXPORT / IMPORT LOCATION #####
export EXPIMPLOC=
###########################################

##### info ################################
# with this tool you can export and import
# tables from and into a sap system
# you have to run it as "sidadm"
# it use the normal R3trans for export
# and import with template files
####################(c) Florian Lamml 2015#

# Prerequisites ###########################
# need 'dialog' to run
###########################################

##### list of exit codes ##################
# general
# 99 - you try to run as "root"
# 98 - cannot find SAP SID
# 97 - cannot start dialog
# 96 - Hit ESC
# export
# 10 - exit because old run detected
# 11 - fail to select templates for export
# 12 - no template selected for export
# 13 - error while export
# 14 - export info error
# import
# 20 - no exports found for import
# 21 - exit because old run detected
# 22 - no OK exports found for import
# 23 - import select error
# 24 - no exports selected for import
# 25 - error while import
# 26 - import info error
###########################################

# set global variables
export global_pwd=$(pwd)
export global_height=30
export global_width=60
export global_title="SAP Table EXP/IMP for SystemCopy (c) Florian Lamml 2015"
export global_backtitle="SAP Table EXP/IMP for SystemCopy (c) Florian Lamml 2015"

# check export location (and create directory)
if [ -z "$EXPIMPLOC" ]; 
 then 
 export EXPIMPLOCINFO="EXPIMPLOC is not set, use default";
 export EXPIMPLOC=$global_pwd/expimp
else 
 export EXPIMPLOCINFO="EXPIMPLOC is set to"; 
fi
[ ! -d "$EXPIMPLOC" ] && mkdir $EXPIMPLOC

# set logfile
export EXPIMPLOGFILE=$EXPIMPLOC/EXP_IMP_LOG_$(date "+%d_%m_%Y").txt
echo $(date "+%d.%m.%Y-%H:%M") >> $EXPIMPLOGFILE

# root check
export CURUSER=$(whoami)
if [ $CURUSER == "root" ];
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

# check AIX and set PATH and LIBPATH to use linux dialog (build from dialog-1.2-20150225 with gcc-4.8.3-1.aix7.1 on AIX 7.1) on AIX
export OS=$(uname)
if [ $OS == AIX ]
then
export PATH=$PATH:$(pwd)/dialogaix/bin
export LIBPATH=$LIBPATH:$(pwd)/dialogaix/lib
chmod u+x $(pwd)/dialogaix/bin/dialog
fi

# check if dialog is running
dialog > /dev/null 2>&1
export DIAGCHECK=$(echo $?)
if [ $DIAGCHECK -ne 0 ];
 then
	echo "cannot start linux 'dialog' command"
	echo "... EXIT NOW"
	exit 97
fi

# set executable to scripts
chmod u+x $global_pwd/script/sap_export_tables.sh
chmod u+x $global_pwd/script/sap_import_tables.sh

# EXPORT or IMPORT dialog
DIALOG=(dialog --title "$global_title" --backtitle "$global_backtitle"  --radiolist  "   _______   ___ \n  / __/ _ | / _ \ \n _\ \/ __ |/ ___/\n/___/_/ |_/_/    \n _________   ___  __   ____\n/_  __/ _ | / _ )/ /  / __/\n / / / __ |/ _  / /__/ _/  \n/_/ /_/ |_/____/____/___/  \n   _____  _____  ______  ______ \n  / __/ |/_/ _ \/  _/  |/  / _ \ \n / _/_>  </ ___// // /|_/ / ___/\n/___/_/|_/_/  /___/_/  /_/_/    \n\nEXPORT or IMPORT Tables?\n\nINFO: $EXPIMPLOCINFO\nINFO: $EXPIMPLOC\n\nINFO:\nOS: $OS | USER: $CURUSER | SAPSYSTEM: $SAPSYSTEMNAME\n\n                                (c) Florian Lamml 2015" $global_height $global_width 2)
OPTIONS=("EXPORT" "Export SAP Tables" on "IMPORT" "Import SAP Tables" off)
EXPORIMP=$("${DIALOG[@]}" "${OPTIONS[@]}" 2>&1 >/dev/tty)
# check ESC hit
if [ $? -eq 255 ];
 then
	echo "Hit ESC"
	echo "... EXIT NOW"
	exit 96
fi

# EXPORT or IMPORT
for choice in $EXPORIMP
do
    case $choice in
        EXPORT)
			(
			echo "Export SAP Tables" >> $EXPIMPLOGFILE
			# run export script
			$global_pwd/script/sap_export_tables.sh
			)
			export EXPIMPRUNRC=$(echo $?)
			export EXPIMPRUN="Export procedure finished with RC="
            ;;
        IMPORT)
			(
			echo "Import SAP Tables" >> $EXPIMPLOGFILE
			# run import script
			$global_pwd/script/sap_import_tables.sh
			)
			export EXPIMPRUNRC=$(echo $?)
			export EXPIMPRUN="Import procedure finished with RC="
            ;;
    esac
done

# summary

dialog --title "$global_title" --backtitle "$global_backtitle"  --ok-label "EXIT" --msgbox "$EXPIMPRUN$EXPIMPRUNRC\n\nLogfiles can be found in $EXPIMPLOC" $global_height $global_width

# exit
clear
exit $EXPIMPRUNRC
