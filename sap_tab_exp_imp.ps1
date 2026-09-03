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

##### CONFIG EXPORT / IMPORT LOCATION #####
$EXPIMPLOC = ''
###########################################

##### CONFIG CLIENT #######################
# DEFAULT (000), ALL or CLIENT Number
# Default Value = ALL
$EXPCLIENT = 'ALL'
###########################################

##### CONFIG PARALLEL (SAP 1127194) #######
# DEFAULT 0, Max 1-2x CPU Count
$PARALLEL = 0
###########################################

##### info ################################
# with this tool you can export and import
# tables from and into a sap system
# you have to run it as "<sid>adm"
# it use the normal R3trans for export
# and import with template files
####################(c) Florian Lamml 2026#

# Prerequisites ###########################
# Windows PowerShell 5.1 or PowerShell 7+
# a real console host (conhost / Windows
# Terminal) - the ISE is NOT supported
# R3trans.exe must be in the PATH
###########################################

##### list of exit codes ##################
# general
# 99 - you try to run as built-in Administrator
# 98 - cannot find SAP SID
# 97 - cannot start the console UI
# 96 - Hit ESC
# 95 - cannot find R3trans.exe
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

$ErrorActionPreference = 'Stop'

# set global variables
$Global:global_pwd       = $PSScriptRoot
$Global:global_height    = 45
$Global:global_width     = 80
$Global:global_list      = 35
$Global:global_title     = 'SAP Table EXP/IMP for SystemCopy (c) Florian Lamml 2026'
$Global:global_backtitle = 'SAP Table EXP/IMP for SystemCopy (c) Florian Lamml 2026'
$Global:global_copy      = '(c) Florian Lamml 2026'
$Global:global_os        = 'Windows'

# load the console UI (windows replacement for the linux 'dialog' command)
. (Join-Path $Global:global_pwd 'script\sap_expimp_ui.ps1')

# check if the console UI can run
if (-not (Test-UiHost)) {
    Write-Host 'cannot start the console UI'
    Write-Host 'please run this script in a real console host (conhost / Windows Terminal), not in the ISE'
    Write-Host '... EXIT NOW'
    exit 97
}

# check export location (and create directory)
if ([string]::IsNullOrWhiteSpace($EXPIMPLOC)) {
    $Global:EXPIMPLOCINFO = 'EXPIMPLOC is not set, use default'
    $Global:EXPIMPLOC     = Join-Path (Join-Path $Global:global_pwd 'expimp') "$env:SAPSYSTEMNAME"
} else {
    $Global:EXPIMPLOCINFO = 'EXPIMPLOC is set to'
    $Global:EXPIMPLOC     = $EXPIMPLOC
}
if (-not (Test-Path -LiteralPath $Global:EXPIMPLOC)) {
    $null = New-Item -ItemType Directory -Path $Global:EXPIMPLOC -Force
}

# set logfile
$Global:EXPIMPLOGFILE = Join-Path $Global:EXPIMPLOC ('EXP_IMP_LOG_' + (Get-Date -Format 'dd_MM_yyyy') + '.txt')

Write-ExpImpLog (Get-Date -Format 'dd.MM.yyyy-HH:mm')

# "root" check - on windows the equivalent is the built-in Administrator account
# (well-known RID 500, works with every language and even if the account was renamed)
$Global:CURUSER = "$env:USERNAME"
$isBuiltInAdmin = $false
try {
    $wi = [Security.Principal.WindowsIdentity]::GetCurrent()
    $Global:CURUSER = $wi.Name
    if ($wi.User.Value -match '-500$') { $isBuiltInAdmin = $true }
} catch { }
if ($isBuiltInAdmin) {
    Write-Host 'This script must not be run as the built-in Administrator user!'
    Write-Host 'Please run it as <sid>adm.'
    Write-Host '... EXIT NOW'
    exit 99
}

# SAPSYSTEMNAME variable check (need for R3trans)
if ([string]::IsNullOrWhiteSpace($env:SAPSYSTEMNAME)) {
    Write-Host 'No SID found, is the user right?'
    Write-Host '... EXIT NOW'
    exit 98
}

# PARALLEL check empty variable
if ($null -eq $PARALLEL -or "$PARALLEL" -eq '') { $PARALLEL = 0 }

$Global:EXPCLIENT = $EXPCLIENT
$Global:PARALLEL  = [int]$PARALLEL

# check if R3trans is available
$r3 = Get-Command 'R3trans.exe' -ErrorAction SilentlyContinue
if (-not $r3) { $r3 = Get-Command 'R3trans' -ErrorAction SilentlyContinue }
if (-not $r3) {
    Write-Host 'cannot find R3trans.exe in the PATH'
    Write-Host 'please run this script as <sid>adm'
    Write-Host '... EXIT NOW'
    Write-ExpImpLog 'ERROR: cannot find R3trans.exe in the PATH'
    exit 95
}
$Global:R3TRANS = $r3.Source

# EXPORT or IMPORT dialog
$art = @'
   _______   ___ 
  / __/ _ | / _ \ 
 _\ \/ __ |/ ___/
/___/_/ |_/_/    
 _________   ___  __   ____
/_  __/ _ | / _ )/ /  / __/
 / / / __ |/ _  / /__/ _/  
/_/ /_/ |_/____/____/___/  
   _____  _____  ______  ______ 
  / __/ |/_/ _ \/  _/  |/  / _ \ 
 / _/_>  </ ___// // /|_/ / ___/
/___/_/|_/_/  /___/_/  /_/_/    
'@

$prompt = $art + @"

EXPORT or IMPORT Tables?

INFO: $($Global:EXPIMPLOCINFO)
INFO: $($Global:EXPIMPLOC)

CLIENT: $($Global:EXPCLIENT) | PARALLEL: $($Global:PARALLEL)
OS: $($Global:global_os) | USER: $($Global:CURUSER) | SAPSYSTEM: $($env:SAPSYSTEMNAME)

$($Global:global_copy)
"@

$options = @(
    [PSCustomObject]@{ Tag = 'EXPORT'; Item = 'EXPORT   Export SAP Tables'; On = $true  },
    [PSCustomObject]@{ Tag = 'IMPORT'; Item = 'IMPORT   Import SAP Tables'; On = $false }
)

$choice = Show-UiRadioList -Text $prompt -Items $options

# check ESC hit
if ($choice.Cancelled) {
    Clear-Host
    Write-Host 'Hit ESC'
    Write-Host '... EXIT NOW'
    exit 96
}

# EXPORT or IMPORT
$EXPIMPRUNRC = 0
$EXPIMPRUN   = ''
switch ($choice.Tag) {
    'EXPORT' {
        Write-ExpImpLog 'Export SAP Tables'
        & (Join-Path $Global:global_pwd 'script\sap_export_tables.ps1')
        $EXPIMPRUNRC = $LASTEXITCODE
        $EXPIMPRUN   = 'Export procedure finished with RC='
    }
    'IMPORT' {
        Write-ExpImpLog 'Import SAP Tables'
        & (Join-Path $Global:global_pwd 'script\sap_import_tables.ps1')
        $EXPIMPRUNRC = $LASTEXITCODE
        $EXPIMPRUN   = 'Import procedure finished with RC='
    }
}
if ($null -eq $EXPIMPRUNRC) { $EXPIMPRUNRC = 0 }

# summary
[void](Show-UiMsgBox -Text "$EXPIMPRUN$EXPIMPRUNRC`n`nLogfiles can be found in $($Global:EXPIMPLOC)" -OkLabel 'EXIT')

# exit
Clear-Host
exit $EXPIMPRUNRC
