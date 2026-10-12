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
# Version 2.0 - komplett überarbeitet mit neuen Funktionen und Sicherheitsoptionen

$ErrorActionPreference = 'Stop'

# the export script must be started by sap_tab_exp_imp.ps1 (config, checks, logfile, console UI)
if (-not $Global:EXPIMPRUNNING -or -not $Global:EXPIMPLOC -or -not $Global:EXPIMPLOGFILE -or
    -not (Get-Command 'Show-UiCheckList' -ErrorAction SilentlyContinue)) {
    Write-Host 'This script must be started by sap_tab_exp_imp.ps1!'
    Write-Host '... EXIT NOW'
    exit 90
}

# R3trans control files must be plain ASCII without BOM
function Write-AsciiFile {
    param([string]$Path, [string[]]$Lines)
    [System.IO.File]::WriteAllLines($Path, [string[]]$Lines, (New-Object System.Text.ASCIIEncoding))
}

# set config file and delete old one
$selectedtablesforexport = Join-Path $Global:EXPIMPLOC 'selected_tables_for_export.conf'
$exportedtables          = Join-Path $Global:EXPIMPLOC 'exported_tables.conf'
$templatedir             = Join-Path $Global:global_pwd 'templates'

# check existing data of a previous run - copy it to a backup directory before it is deleted
$oldrunfiles = @(Get-ExpImpRunFiles)
if ($oldrunfiles.Count -gt 0) {
    $backupdir = Join-Path (Join-Path $Global:EXPIMPLOC 'backup') (Get-Date -Format 'yyyyMMdd_HHmmss')
    $backupkeepinfo = ''
    if ($Global:BACKUPKEEP -gt 0) { $backupkeepinfo = "`n`nOnly the newest $($Global:BACKUPKEEP) backups are kept (BACKUPKEEP),`nolder backups will be deleted!" }
    $continue = Show-UiYesNo -Text "There are files of a previous run in $($Global:EXPIMPLOC)`n`nIf you continue these files will be copied to`n$backupdir`nand then deleted!$backupkeepinfo" -YesLabel 'Continue' -NoLabel 'Exit'
    switch ($continue) {
        0 {
            Write-ExpImpLog "INFO: backup old files to $backupdir"
            try {
                $null = New-Item -ItemType Directory -Path $backupdir -Force
                foreach ($f in $oldrunfiles) { Copy-Item -LiteralPath $f.FullName -Destination $backupdir -Force }
                # the info files in the backup show the backup directory as location
                foreach ($infoname in 'exported_tables.conf', 'imported_tables.conf') {
                    $infofile = Join-Path $backupdir $infoname
                    if (-not (Test-Path -LiteralPath $infofile)) { continue }
                    $prev = ''
                    $info = foreach ($line in @(Get-Content -LiteralPath $infofile)) {
                        if ($prev -eq '# Exported to:' -or $prev -eq '# Imported from:') { '# ' + $backupdir } else { $line }
                        $prev = $line
                    }
                    Write-AsciiFile -Path $infofile -Lines @($info)
                }
            } catch {
                Write-ExpImpLog "ERROR: backup of the previous run to $backupdir failed, nothing deleted ($($_.Exception.Message))"
                exit 15
            }
            Write-ExpImpLog 'INFO: delete old files'
            foreach ($f in $oldrunfiles) { Remove-Item -LiteralPath $f.FullName -Force }
            # keep only the newest BACKUPKEEP backups (0 = unlimited)
            if ($Global:BACKUPKEEP -gt 0) {
                $oldbackups = @(Get-ChildItem -LiteralPath (Join-Path $Global:EXPIMPLOC 'backup') -Directory |
                    Where-Object { $_.Name -match '^[0-9]{8}_[0-9]{6}\z' } | Sort-Object Name)
                for ($i = 0; $i -lt ($oldbackups.Count - $Global:BACKUPKEEP); $i++) {
                    try {
                        Remove-Item -LiteralPath $oldbackups[$i].FullName -Recurse -Force
                        Write-ExpImpLog "INFO: delete old backup $($oldbackups[$i].FullName) (BACKUPKEEP=$($Global:BACKUPKEEP))"
                    } catch {
                        Write-ExpImpLog "WARNING: cannot delete old backup $($oldbackups[$i].FullName)"
                    }
                }
            }
        }
        1 {
            Write-ExpImpLog 'INFO: exit because old run detected'
            exit 10
        }
        # check ESC hit
        default {
            Write-ExpImpLog 'INFO: exit because old run (ESC hit)'
            exit 10
        }
    }
}

# search templates
$templates = @(Get-ChildItem -LiteralPath $templatedir -File | Sort-Object Name)
$items = @($templates | ForEach-Object {
    # empty templates (no statements) are marked, they are skipped by the export
    $name = $_.Name
    if (-not (@(Get-Content -LiteralPath $_.FullName) -match '\S')) { $name = "$name (empty)" }
    [PSCustomObject]@{ Tag = $_.Name; Item = $name; On = $false }
})

# select the templates
$selection = Show-UiCheckList -Text 'Select the Templates for Export:' -Items $items
$seltables = @($selection.Tags)
Write-AsciiFile -Path $selectedtablesforexport -Lines $seltables
if ($selection.Cancelled) {
    Write-ExpImpLog 'ERROR: fail to select templates for export'
    Remove-Item -LiteralPath $selectedtablesforexport -Force -ErrorAction SilentlyContinue
    exit 11
}
Clear-Host
if ($seltables.Count -eq 0) {
    Write-ExpImpLog 'ERROR: no template selected for export'
    Remove-Item -LiteralPath $selectedtablesforexport -Force -ErrorAction SilentlyContinue
    exit 12
}

# logfile info
Write-ExpImpLog '=== selected tables for export ==='
foreach ($t in $seltables) { Write-ExpImpLog $t }
Write-ExpImpLog '=== selected tables for export ==='

# info file (with metadata of the source system - checked by the import)
Write-AsciiFile -Path $exportedtables -Lines @(
    '# Template name | Return Code of Export | SHA-256 of the data file'
    '# ====================================='
    '# Exported to:'
    ('# ' + $Global:EXPIMPLOC)
    '# ====================================='
    ('# SID=' + $env:SAPSYSTEMNAME)
    ('# HOST=' + [Environment]::MachineName)
    ('# CLIENT=' + $Global:EXPCLIENT)
    ('# USER=' + $Global:CURUSER)
    ('# DATE=' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
    '# ====================================='
)

# check STMS_QA export
if ($seltables -contains 'STMS_QA') {
    $rc = Show-UiMsgBox -Text "You are going to export STMS_QA `n`n Please refresh STMS_QA before continue" -OkLabel 'Continue'
    # check ESC hit
    if ($rc -eq 255) { exit 96 }
}

# export and export dialog
try {
    # progress: number of the template / number of templates
    $exptotal = $seltables.Count
    $expnr    = 0
    Start-UiProgressView -Text "Export SAP Tables ($exptotal templates)"
    foreach ($SELTABLES in $seltables) {
        $expnr++
        Write-Host "=== Export $expnr/$exptotal`: $SELTABLES ===" -ForegroundColor Cyan
        $templatefile = Join-Path $templatedir $SELTABLES
        if (-not (Test-Path -LiteralPath $templatefile)) {
            Write-Host "=== Export SKIPPED $SELTABLES (template missing) ===" -ForegroundColor Yellow
            Write-Host "=== $(Get-ExpImpProgressBar -Current $expnr -Total $exptotal) done ===" -ForegroundColor Green
            Write-Host ''
            Add-Content -LiteralPath $exportedtables -Value "$SELTABLES|RC=TEMPLATE_MISSING|SHA256=" -Encoding ascii
            continue
        }
        if (-not (@(Get-Content -LiteralPath $templatefile) -match '\S')) {
            Write-Host "=== Export SKIPPED $SELTABLES (template empty) ===" -ForegroundColor Yellow
            Write-Host "=== $(Get-ExpImpProgressBar -Current $expnr -Total $exptotal) done ===" -ForegroundColor Green
            Write-Host ''
            Add-Content -LiteralPath $exportedtables -Value "$SELTABLES|RC=TEMPLATE_EMPTY|SHA256=" -Encoding ascii
            continue
        }
        $tplfile = Join-Path $Global:EXPIMPLOC "$SELTABLES.tpl"
        $datfile = Join-Path $Global:EXPIMPLOC "$SELTABLES.dat"
        $logfile = Join-Path $Global:EXPIMPLOC "$SELTABLES.exp.log"

        $tpl = New-Object System.Collections.Generic.List[string]
        $tpl.Add('export')
        $tpl.Add("client = $($Global:EXPCLIENT)")
        if ([int]$Global:PARALLEL -ne 0) {
            $tpl.Add("parallel = $($Global:PARALLEL)")
        }
        $tpl.Add("file = '$datfile'")
        foreach ($line in @(Get-Content -LiteralPath $templatefile)) {
            $tpl.Add($line)
        }
        Write-AsciiFile -Path $tplfile -Lines $tpl.ToArray()

        # R3trans writes warnings to stderr - '2>&1' would raise a terminating
        # error under $ErrorActionPreference = 'Stop' (Windows PowerShell 5.1)
        $prevEap = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            & $Global:R3TRANS -w $logfile $tplfile 2>&1 | ForEach-Object { Write-Host $_ }
            $rc = $LASTEXITCODE
        } finally {
            $ErrorActionPreference = $prevEap
        }
        $sha256 = ''
        if (Test-Path -LiteralPath $datfile) { $sha256 = Get-ExpImpSha256 -Path $datfile }
        Add-Content -LiteralPath $exportedtables -Value "$SELTABLES|RC=$rc|SHA256=$sha256" -Encoding ascii
        Write-Host "=== Export END $SELTABLES (RC=$rc) ===" -ForegroundColor Cyan
        Write-Host "=== $(Get-ExpImpProgressBar -Current $expnr -Total $exptotal) done ===" -ForegroundColor Green
        Write-Host ''
        Start-Sleep -Seconds 1
    }
    Add-Content -LiteralPath $exportedtables -Value '# =====================================' -Encoding ascii
    Complete-UiProgressView
} catch {
    Write-ExpImpLog "ERROR: error while export ($($_.Exception.Message))"
    exit 13
}

# logfile info
Write-ExpImpLog '=== exported tables ==='
foreach ($line in @(Get-Content -LiteralPath $exportedtables)) { Write-ExpImpLog $line }
Write-ExpImpLog '=== exported tables ==='

# export info
$rc = Show-UiTextBox -Path $exportedtables -ExitLabel 'Continue'
if ($rc -ne 0) {
    Write-ExpImpLog 'ERROR: export info error'
    exit 14
}
Clear-Host

# highest return code of R3trans (RC >= 8 or a missing template is an error, an empty template is not)
$maxrc = Get-ExpImpMaxRc -Path $exportedtables
if ($maxrc -ge 8) {
    Write-ExpImpLog "ERROR: error while export (highest RC=$maxrc, see exported tables)"
    exit 13
}

Write-ExpImpLog '=== export finished ==='
exit 0
