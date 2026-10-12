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

$ErrorActionPreference = 'Stop'

# the import script must be started by sap_tab_exp_imp.ps1 (config, checks, logfile, console UI)
if (-not $Global:EXPIMPRUNNING -or -not $Global:EXPIMPLOC -or -not $Global:EXPIMPLOGFILE -or
    -not (Get-Command 'Show-UiCheckList' -ErrorAction SilentlyContinue)) {
    Write-Host 'This script must be started by sap_tab_exp_imp.ps1!'
    Write-Host '... EXIT NOW'
    exit 90
}

function Write-AsciiFile {
    param([string]$Path, [string[]]$Lines)
    [System.IO.File]::WriteAllLines($Path, [string[]]$Lines, (New-Object System.Text.ASCIIEncoding))
}

# exports available for import: the current export and the backups of previous runs
# (newest first - the backup directories are named by timestamp)
function Test-ExpImpExport {
    param([string]$Dir)
    $f = Join-Path $Dir 'exported_tables.conf'
    return ((Test-Path -LiteralPath $f) -and @(Get-Content -LiteralPath $f).Count -gt 0)
}
$impsrcdirs = @()
if (Test-ExpImpExport $Global:EXPIMPLOC) { $impsrcdirs += $Global:EXPIMPLOC }
$backuproot = Join-Path $Global:EXPIMPLOC 'backup'
if (Test-Path -LiteralPath $backuproot) {
    foreach ($d in @(Get-ChildItem -LiteralPath $backuproot -Directory | Sort-Object Name -Descending)) {
        if (Test-ExpImpExport $d.FullName) { $impsrcdirs += $d.FullName }
    }
}
if ($impsrcdirs.Count -eq 0) {
    Write-ExpImpLog 'ERROR: no exports found for import'
    exit 20
}

# select the export to import if there is more than one (default is the newest)
$impsrc = $impsrcdirs[0]
if ($impsrcdirs.Count -gt 1) {
    $items = @()
    for ($i = 0; $i -lt $impsrcdirs.Count; $i++) {
        $d     = $impsrcdirs[$i]
        $conf  = Join-Path $d 'exported_tables.conf'
        $name  = if ($d -eq $Global:EXPIMPLOC) { 'current' } else { 'backup\' + (Split-Path $d -Leaf) }
        $date  = Get-ExpImpMeta -Path $conf -Key 'DATE'; if (-not $date) { $date = 'unknown date' }
        $sid   = Get-ExpImpMeta -Path $conf -Key 'SID';  if (-not $sid)  { $sid  = 'unknown' }
        $count = @(Get-Content -LiteralPath $conf | Where-Object { $_ -match '\|RC=' }).Count
        $items += [PSCustomObject]@{ Tag = $i; Item = "$name | $date | SID $sid | $count exports"; On = ($i -eq 0) }
    }
    $choice = Show-UiRadioList -Text 'Select the export to import (default is the newest):' -Items $items
    if ($choice.Cancelled) {
        Write-ExpImpLog 'INFO: no export selected for import'
        exit 29
    }
    $impsrc = $impsrcdirs[[int]$choice.Tag]
}
Write-ExpImpLog "INFO: import from $impsrc"

# set config file
$exportedtables = Join-Path $impsrc 'exported_tables.conf'

# set config file
$exportedtablesok = Join-Path $impsrc 'exported_tables_ok.conf'

# check existing data
if (Test-Path -LiteralPath $exportedtablesok) {
    $continue = Show-UiYesNo -Text "There is the selection of a previous import in`n$($impsrc)`n`nIf you continue, this selection will be reset.`n(The export data is not changed.)" -YesLabel 'Continue' -NoLabel 'Exit'
    switch ($continue) {
        0 {
            Write-ExpImpLog 'INFO: delete old files'
            Remove-Item -LiteralPath $exportedtablesok -Force
        }
        1 {
            Write-ExpImpLog 'INFO: exit because old run detected'
            exit 21
        }
        # check ESC hit
        255 {
            Write-ExpImpLog 'INFO: exit because old run (ESC hit)'
            exit 21
        }
    }
}

# build list of OK exports for import
$okexports = @(
    Get-Content -LiteralPath $exportedtables |
        Where-Object { $_ -notmatch '^#' } |
        Where-Object { $_ -match 'RC=0' -or $_ -match 'RC=4' }
)
if ($okexports.Count -eq 0) {
    Write-ExpImpLog 'ERROR: no OK exports found for import'
    exit 22
}
Write-AsciiFile -Path $exportedtablesok -Lines $okexports

# set config file and delete old one
$importtables = Join-Path $impsrc 'selected_tables_import.conf'
if (Test-Path -LiteralPath $importtables) { Remove-Item -LiteralPath $importtables -Force }

# select exports to import
$items = @($okexports | ForEach-Object {
    $name = ($_ -split '\|')[0]
    [PSCustomObject]@{ Tag = $name; Item = $name; On = $true }
})

# select exported tables for import
$selection = Show-UiCheckList -Text 'Select the exports to import:' -Items $items
$seltables = @($selection.Tags)
Write-AsciiFile -Path $importtables -Lines $seltables
if ($selection.Cancelled) {
    Write-ExpImpLog 'ERROR: import select error'
    exit 23
}
Clear-Host
if ($seltables.Count -eq 0) {
    Write-ExpImpLog 'ERROR: no exports selected for import'
    exit 24
}

# metadata of the source system (written by the export since version 1.10)
$expsid    = Get-ExpImpMeta -Path $exportedtables -Key 'SID'
$exphost   = Get-ExpImpMeta -Path $exportedtables -Key 'HOST'
$expclient = Get-ExpImpMeta -Path $exportedtables -Key 'CLIENT'
$expuser   = Get-ExpImpMeta -Path $exportedtables -Key 'USER'
$expdate   = Get-ExpImpMeta -Path $exportedtables -Key 'DATE'
$curhost   = [Environment]::MachineName
function Get-OrUnknown { param([string]$Value) if ($Value) { return $Value } return 'unknown' }

# list of the selected exports (PowerShell variables are case-insensitive:
# the import loop variable $SELTABLES overwrites $seltables)
$importlist = @($seltables)

# verify the SHA-256 checksums of the selected exports
Write-ExpImpLog '=== verify checksums ==='
$checksumerror = @()
$checksumerrorlist = ''
foreach ($imptable in $importlist) {
    $datfile = Join-Path $impsrc "$imptable.dat"
    $expsha  = ''
    foreach ($line in $okexports) {
        $f = $line -split '\|'
        if ($f[0] -eq $imptable) {
            foreach ($field in $f) { if ($field.StartsWith('SHA256=')) { $expsha = $field.Substring(7) } }
        }
    }
    if (-not $expsid) {
        # export of an older version without metadata and checksums
        Write-ExpImpLog "$imptable|NO CHECKSUM (export of an older version)"
    } elseif (-not (Test-Path -LiteralPath $datfile)) {
        Write-ExpImpLog "$imptable|ERROR data file missing"
        $checksumerror += $imptable
        $checksumerrorlist += "`n  $imptable (data file missing)"
    } elseif (-not $expsha -or (Get-ExpImpSha256 -Path $datfile) -ne $expsha) {
        Write-ExpImpLog "$imptable|ERROR checksum mismatch"
        $checksumerror += $imptable
        $checksumerrorlist += "`n  $imptable (checksum mismatch - data file changed)"
    } else {
        Write-ExpImpLog "$imptable|checksum OK"
    }
}
Write-ExpImpLog '=== verify checksums ==='
if ($checksumerror.Count -gt 0) {
    Write-ExpImpLog "ERROR: checksum verification failed: $($checksumerror -join ' ')"
    [void](Show-UiMsgBox -Text "Checksum verification FAILED - nothing was imported!`n`nThe data files of these exports are missing or were changed after the export:`n$checksumerrorlist`n`nDetails can be found in $($Global:EXPIMPLOGFILE)" -OkLabel 'EXIT')
    exit 27
}

# confirm the import (show source and target system)
$importwarning = ''
$confirmsid    = $false
if (-not $expsid) {
    $importwarning += "`nWARNING: export of an older version without metadata and checksums,`n         the source system and the data files cannot be verified!`n"
    $confirmsid = $true
} elseif ($expsid -ne $env:SAPSYSTEMNAME) {
    $importwarning += "`nWARNING: SAPSYSTEM MISMATCH - the export was created on $expsid!`n"
}
if ($exphost -and $exphost -ne $curhost) {
    $importwarning += "`nINFO: the export was created on another host ($exphost)`n"
}
$confirmtext = @"
Export: $impsrc

You are going to IMPORT into

  SAPSYSTEM: $($env:SAPSYSTEMNAME) | HOST: $curhost

The export was created on

  SAPSYSTEM: $(Get-OrUnknown $expsid) | HOST: $(Get-OrUnknown $exphost) | CLIENT: $(Get-OrUnknown $expclient)
  USER: $(Get-OrUnknown $expuser) | DATE: $(Get-OrUnknown $expdate)
$importwarning
Selected exports:
$($importlist -join ' ')

The existing content of these tables will be DELETED and replaced!

Continue with the import?
"@
$continue = Show-UiYesNo -Text $confirmtext -YesLabel 'Import' -NoLabel 'Exit' -DefaultNo
if ($continue -ne 0) {
    Write-ExpImpLog 'INFO: import not confirmed'
    exit 28
}
if ($confirmsid) {
    $typed = Show-UiInputBox -Text "The export was created by an older version - the source system and the data files could not be verified!`n`nType the SID of this system ($($env:SAPSYSTEMNAME)) to confirm the import:"
    if ($typed.Cancelled -or $typed.Value -cne $env:SAPSYSTEMNAME) {
        Write-ExpImpLog 'INFO: import not confirmed (SID not confirmed)'
        exit 28
    }
}
Write-ExpImpLog "INFO: import confirmed (source: SID=$(Get-OrUnknown $expsid) HOST=$(Get-OrUnknown $exphost) DATE=$(Get-OrUnknown $expdate))"

# export info file
$importedtables = Join-Path $impsrc 'imported_tables.conf'

# info file
Write-AsciiFile -Path $importedtables -Lines @(
    '# Template name | Return Code of Import'
    '# ====================================='
    '# Imported from:'
    ('# ' + $impsrc)
    '# ====================================='
)

# import tables
try {
    # progress: number of the export / number of exports
    $imptotal = $importlist.Count
    $impnr    = 0
    Start-UiProgressView -Text "Import selected tables ($imptotal exports)"
    foreach ($SELTABLES in $importlist) {
        $impnr++
        $datfile = Join-Path $impsrc "$SELTABLES.dat"
        $logfile = Join-Path $impsrc "$SELTABLES.imp.log"

        Write-Host "=== Import $impnr/$imptotal`: $SELTABLES ===" -ForegroundColor Cyan
        # R3trans writes warnings to stderr - '2>&1' would raise a terminating
        # error under $ErrorActionPreference = 'Stop' (Windows PowerShell 5.1)
        $prevEap = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            & $Global:R3TRANS -w $logfile -i $datfile 2>&1 | ForEach-Object { Write-Host $_ }
            $rc = $LASTEXITCODE
        } finally {
            $ErrorActionPreference = $prevEap
        }
        Add-Content -LiteralPath $importedtables -Value "$SELTABLES|RC=$rc" -Encoding ascii
        Write-Host "=== Import END $SELTABLES (RC=$rc) ===" -ForegroundColor Cyan
        Write-Host "=== $(Get-ExpImpProgressBar -Current $impnr -Total $imptotal) done ===" -ForegroundColor Green
        Write-Host ''
        Start-Sleep -Seconds 1
    }
    Add-Content -LiteralPath $importedtables -Value '# =====================================' -Encoding ascii
    Complete-UiProgressView
} catch {
    Write-ExpImpLog "ERROR: error while import ($($_.Exception.Message))"
    exit 25
}

# logfile info
Write-ExpImpLog '=== imported tables ==='
foreach ($line in @(Get-Content -LiteralPath $importedtables)) { Write-ExpImpLog $line }
Write-ExpImpLog '=== imported tables ==='

# import info
$rc = Show-UiTextBox -Path $importedtables -ExitLabel 'Continue'
if ($rc -ne 0) {
    Write-ExpImpLog 'ERROR: import info error'
    exit 26
}
Clear-Host

# highest return code of R3trans (RC >= 8 is an error)
$maxrc = Get-ExpImpMaxRc -Path $importedtables
if ($maxrc -ge 8) {
    Write-ExpImpLog "ERROR: error while import (highest RC=$maxrc, see imported tables)"
    exit 25
}

Write-ExpImpLog '=== import finished ==='
exit 0
