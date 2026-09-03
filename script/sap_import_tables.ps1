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

$ErrorActionPreference = 'Stop'

# the console UI is already loaded by the main script, load it again if called directly
if (-not (Get-Command 'Show-UiCheckList' -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'sap_expimp_ui.ps1')
}

function Write-AsciiFile {
    param([string]$Path, [string[]]$Lines)
    [System.IO.File]::WriteAllLines($Path, [string[]]$Lines, (New-Object System.Text.ASCIIEncoding))
}

# set config file and delete old one
$exportedtables = Join-Path $Global:EXPIMPLOC 'exported_tables.conf'
if (-not (Test-Path -LiteralPath $exportedtables) -or @(Get-Content -LiteralPath $exportedtables).Count -eq 0) {
    Write-ExpImpLog 'ERROR: no exports found for import'
    exit 20
}

# set config file
$exportedtablesok = Join-Path $Global:EXPIMPLOC 'exported_tables_ok.conf'

# check existing data
if (Test-Path -LiteralPath $exportedtablesok) {
    $continue = Show-UiYesNo -Text "There are import files in $($Global:EXPIMPLOC)`nIf you continue these files will be deleted!" -YesLabel 'Continue' -NoLabel 'Exit'
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
$importtables = Join-Path $Global:EXPIMPLOC 'selected_tables_import.conf'
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

# export info file
$importedtables = Join-Path $Global:EXPIMPLOC 'imported_tables.conf'

# info file
Write-AsciiFile -Path $importedtables -Lines @(
    '# Template name | Return Code of Import'
    '# ====================================='
    '# Imported from:'
    ('# ' + $Global:EXPIMPLOC)
    '# ====================================='
)

# import tables
try {
    Start-UiProgressView -Text 'Import selected tables'
    foreach ($SELTABLES in $seltables) {
        $datfile = Join-Path $Global:EXPIMPLOC "$SELTABLES.dat"
        $logfile = Join-Path $Global:EXPIMPLOC "$SELTABLES.imp.log"

        Write-Host "=== Import START $SELTABLES ===" -ForegroundColor Cyan
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
        Write-Host "=== Import END $SELTABLES ===" -ForegroundColor Cyan
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

Write-ExpImpLog '=== import finished ==='
exit 0
