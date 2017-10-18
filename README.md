# SAP-Table-EXP-IMP-for-SystemCopy

# SAP Table EXP/IMP for SystemCopy (c) Florian Lamml 2015
# www.florian-lamml.de
# Version 1.0 - Initial Release

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