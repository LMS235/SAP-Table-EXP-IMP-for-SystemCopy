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

##### CONFIG BACKUPKEEP ##################
# number of backups of previous runs to keep
# in EXPIMPLOC\backup (the oldest ones are
# deleted after a new backup was created)
# 0 = unlimited (no backup is deleted)
# Default Value = 0
$BACKUPKEEP = 0
###########################################

##### CONFIG ACCESS GROUP #################
# windows group that gets access to the
# export / import location (besides the
# current user, Administrators and SYSTEM)
# e.g. if export and import run as
# different <sid>adm users, '' = none
$EXPIMPGROUP = 'SAP_LocalAdmin'
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
# 99 - you try to run as built-in Administrator or a system account
# 98 - cannot find SAP SID
# 97 - cannot start the console UI
# 96 - Hit ESC
# 95 - cannot find R3trans.exe
# 94 - cannot create export location / location not writable
# 92 - user is not <sid>adm
# 90 - export / import script started directly (not by sap_tab_exp_imp.ps1)
# 91 - invalid config value (EXPIMPLOC, EXPCLIENT, PARALLEL, BACKUPKEEP)
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

# "root" check - on windows the equivalent is the built-in Administrator account
# (well-known RID 500, works with every language and even if the account was renamed)
# and the system accounts (SYSTEM, LOCAL SERVICE, NETWORK SERVICE)
$Global:CURUSER = "$env:USERNAME"
$isBuiltInAdmin = $false
try {
    $wi = [Security.Principal.WindowsIdentity]::GetCurrent()
    $Global:CURUSER = $wi.Name
    if ($wi.User.Value -match '-500$' -or $wi.User.Value -in @('S-1-5-18', 'S-1-5-19', 'S-1-5-20')) { $isBuiltInAdmin = $true }
} catch { }
if ($isBuiltInAdmin) {
    Write-Host 'This script must not be run as the built-in Administrator or a system account!'
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

# <sid>adm check
$sidadm   = $env:SAPSYSTEMNAME.ToLower() + 'adm'
$username = ($Global:CURUSER -split '\\')[-1]
if ($username -ne $sidadm) {
    Write-Host "This script must be run as $sidadm (current user: $($Global:CURUSER))!"
    Write-Host '... EXIT NOW'
    exit 92
}

# check config values (they are written into the R3trans control files)
$EXPCLIENT = "$EXPCLIENT".Trim().ToUpper()
if ($EXPCLIENT -notmatch '^(ALL|DEFAULT|[0-9]{3})\z') {
    Write-Host "EXPCLIENT '$EXPCLIENT' is invalid (allowed: ALL, DEFAULT or a 3-digit client number)"
    Write-Host '... EXIT NOW'
    exit 91
}

# PARALLEL check empty variable
if ($null -eq $PARALLEL -or "$PARALLEL" -eq '') { $PARALLEL = 0 }
if ("$PARALLEL" -notmatch '^[0-9]+\z') {
    Write-Host "PARALLEL '$PARALLEL' is invalid (allowed: 0 or a positive number)"
    Write-Host '... EXIT NOW'
    exit 91
}

# BACKUPKEEP check empty variable
if ($null -eq $BACKUPKEEP -or "$BACKUPKEEP" -eq '') { $BACKUPKEEP = 0 }
if ("$BACKUPKEEP" -notmatch '^[0-9]+\z') {
    Write-Host "BACKUPKEEP '$BACKUPKEEP' is invalid (allowed: 0 = unlimited or a positive number)"
    Write-Host '... EXIT NOW'
    exit 91
}

$Global:EXPCLIENT  = $EXPCLIENT
$Global:PARALLEL   = [int]$PARALLEL
$Global:BACKUPKEEP = [int]$BACKUPKEEP

# check export location
if ([string]::IsNullOrWhiteSpace($EXPIMPLOC)) {
    $Global:EXPIMPLOCINFO = 'EXPIMPLOC is not set, use default'
    $Global:EXPIMPLOC     = Join-Path (Join-Path $Global:global_pwd 'expimp') "$env:SAPSYSTEMNAME"
} else {
    $Global:EXPIMPLOCINFO = 'EXPIMPLOC is set to'
    $Global:EXPIMPLOC     = $EXPIMPLOC
}
if ($Global:EXPIMPLOC -match "['\r\n]") {
    Write-Host "EXPIMPLOC '$($Global:EXPIMPLOC)' is invalid (must not contain quotes or line breaks)"
    Write-Host '... EXIT NOW'
    exit 91
}
if ($Global:EXPIMPLOC -notmatch '^([A-Za-z]:\\|\\\\)') {
    Write-Host "EXPIMPLOC '$($Global:EXPIMPLOC)' is invalid (must be an absolute path like D:\expimp or \\server\share)"
    Write-Host '... EXIT NOW'
    exit 91
}

# create export location and secure it (only <sid>adm, the access group, Administrators and SYSTEM)
try {
    if (-not (Test-Path -LiteralPath $Global:EXPIMPLOC)) {
        $null = New-Item -ItemType Directory -Path $Global:EXPIMPLOC -Force
    }
} catch {
    Write-Host "cannot create $($Global:EXPIMPLOC)"
    Write-Host '... EXIT NOW'
    exit 94
}
# the directory EXPIMPLOC may belong to another user (if it already exists), it only has
# to be writable for <sid>adm - if the permissions cannot be set, only a warning is written
try {
    $writetest = Join-Path $Global:EXPIMPLOC ('writetest_' + [guid]::NewGuid().ToString('N') + '.tmp')
    [System.IO.File]::WriteAllText($writetest, 'test')
    Remove-Item -LiteralPath $writetest -Force
} catch {
    Write-Host "$($Global:EXPIMPLOC) is not writable for $($Global:CURUSER)!"
    Write-Host '... EXIT NOW'
    exit 94
}
$aclWarning = Protect-ExpImpLocation -Path $Global:EXPIMPLOC -Group $EXPIMPGROUP
if ($aclWarning -eq 'ERROR') {
    $aclWarning = "cannot set the permissions of $($Global:EXPIMPLOC) - please check them manually"
}

# set logfile
$Global:EXPIMPLOGFILE = Join-Path $Global:EXPIMPLOC ('EXP_IMP_LOG_' + (Get-Date -Format 'dd_MM_yyyy') + '.txt')

Write-ExpImpLog (Get-Date -Format 'dd.MM.yyyy-HH:mm')
if ($aclWarning) {
    Write-ExpImpLog "WARNING: $aclWarning"
    Write-Host "WARNING: $aclWarning" -ForegroundColor Yellow
    Start-Sleep -Seconds 3
}

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

CLIENT: $($Global:EXPCLIENT) | PARALLEL: $($Global:PARALLEL) | BACKUPKEEP: $($Global:BACKUPKEEP)
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
# an unexpected error in the export / import script ends with RC 13 / 25 and is shown in the summary
$EXPIMPRUNRC   = 0
$EXPIMPRUN     = ''
$EXPIMPRUNERR  = ''
$Global:EXPIMPRUNNING = $true
switch ($choice.Tag) {
    'EXPORT' {
        Write-ExpImpLog 'Export SAP Tables'
        $EXPIMPRUN = 'Export procedure finished with RC='
        try {
            & (Join-Path $Global:global_pwd 'script\sap_export_tables.ps1')
            $EXPIMPRUNRC = $LASTEXITCODE
        } catch {
            $EXPIMPRUNRC  = 13
            $EXPIMPRUNERR = $_.Exception.Message
            Write-ExpImpLog "ERROR: unexpected error while export ($EXPIMPRUNERR)"
        }
    }
    'IMPORT' {
        Write-ExpImpLog 'Import SAP Tables'
        $EXPIMPRUN = 'Import procedure finished with RC='
        try {
            & (Join-Path $Global:global_pwd 'script\sap_import_tables.ps1')
            $EXPIMPRUNRC = $LASTEXITCODE
        } catch {
            $EXPIMPRUNRC  = 25
            $EXPIMPRUNERR = $_.Exception.Message
            Write-ExpImpLog "ERROR: unexpected error while import ($EXPIMPRUNERR)"
        }
    }
}
$Global:EXPIMPRUNNING = $false
if ($null -eq $EXPIMPRUNRC) { $EXPIMPRUNRC = 0 }

# summary
$EXPIMPRUNINFO = ''
if ($EXPIMPRUNERR) {
    $EXPIMPRUNINFO = "`n`nERROR: unexpected error:`n$EXPIMPRUNERR"
} elseif ($EXPIMPRUNRC -eq 13 -or $EXPIMPRUNRC -eq 25) {
    $EXPIMPRUNINFO = "`n`nERROR: at least one table failed (R3trans RC >= 8 or template missing)!`nPlease check the R3trans log files (*.exp.log / *.imp.log)."
}
[void](Show-UiMsgBox -Text "$EXPIMPRUN$EXPIMPRUNRC$EXPIMPRUNINFO`n`nLogfiles can be found in $($Global:EXPIMPLOC)" -OkLabel 'EXIT')

# exit
Clear-Host
exit $EXPIMPRUNRC
