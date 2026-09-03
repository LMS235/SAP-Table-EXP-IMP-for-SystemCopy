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

# R3trans control files must be plain ASCII without BOM
function Write-AsciiFile {
    param([string]$Path, [string[]]$Lines)
    [System.IO.File]::WriteAllLines($Path, [string[]]$Lines, (New-Object System.Text.ASCIIEncoding))
}

# set config file and delete old one
$selectedtablesforexport = Join-Path $Global:EXPIMPLOC 'selected_tables_for_export.conf'
$exportedtables          = Join-Path $Global:EXPIMPLOC 'exported_tables.conf'
$templatedir             = Join-Path $Global:global_pwd 'templates'

# check existing data
if (Test-Path -LiteralPath $selectedtablesforexport) {
    $continue = Show-UiYesNo -Text "There are export files in $($Global:EXPIMPLOC)`nIf you continue these files will be deleted!" -YesLabel 'Continue' -NoLabel 'Exit'
    switch ($continue) {
        0 {
            Write-ExpImpLog 'INFO: delete old files'
            Remove-Item -LiteralPath $selectedtablesforexport -Force
            if (Test-Path -LiteralPath $exportedtables) { Remove-Item -LiteralPath $exportedtables -Force }
        }
        1 {
            Write-ExpImpLog 'INFO: exit because old run detected'
            exit 10
        }
        # check ESC hit
        255 {
            Write-ExpImpLog 'INFO: exit because old run (ESC hit)'
            exit 10
        }
    }
}

# search templates
$templates = @(Get-ChildItem -LiteralPath $templatedir -File | Sort-Object Name)
$items = @($templates | ForEach-Object {
    [PSCustomObject]@{ Tag = $_.Name; Item = $_.Name; On = $false }
})

# select the templates
$selection = Show-UiCheckList -Text 'Select the Templates for Export:' -Items $items
$seltables = @($selection.Tags)
Write-AsciiFile -Path $selectedtablesforexport -Lines $seltables
if ($selection.Cancelled) {
    Write-ExpImpLog 'ERROR: fail to select templates for export'
    exit 11
}
Clear-Host
if ($seltables.Count -eq 0) {
    Write-ExpImpLog 'ERROR: no template selected for export'
    exit 12
}

# logfile info
Write-ExpImpLog '=== selected tables for export ==='
foreach ($t in $seltables) { Write-ExpImpLog $t }
Write-ExpImpLog '=== selected tables for export ==='

# delete old exports
Get-ChildItem -LiteralPath $Global:EXPIMPLOC -Filter '*.tpl'     -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
Get-ChildItem -LiteralPath $Global:EXPIMPLOC -Filter '*.exp.log' -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
Get-ChildItem -LiteralPath $Global:EXPIMPLOC -Filter '*.dat'     -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue

# info file
Write-AsciiFile -Path $exportedtables -Lines @(
    '# Template name | Return Code of Export'
    '# ====================================='
    '# Exported to:'
    ('# ' + $Global:EXPIMPLOC)
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
    Start-UiProgressView -Text 'Export SAP Tables'
    foreach ($SELTABLES in $seltables) {
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
        foreach ($line in @(Get-Content -LiteralPath (Join-Path $templatedir $SELTABLES) -ErrorAction SilentlyContinue)) {
            $tpl.Add($line)
        }
        Write-AsciiFile -Path $tplfile -Lines $tpl.ToArray()

        Write-Host "=== Export START $SELTABLES ===" -ForegroundColor Cyan
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
        Add-Content -LiteralPath $exportedtables -Value "$SELTABLES|RC=$rc" -Encoding ascii
        Write-Host "=== Export END $SELTABLES ===" -ForegroundColor Cyan
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

Write-ExpImpLog '=== export finished ==='
exit 0
