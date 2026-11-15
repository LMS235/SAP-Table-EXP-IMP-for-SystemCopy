# SAP(R) Table EXP/IMP for SystemCopy (c) Florian Lamml 2026
# www.florian-lamml.de
# tests of the Windows version (run with Windows PowerShell 5.1)
# - the tool runs in its own console window with a stand-in for R3trans (tests\windows\fake)
# - the keys come from a file, every screen of the console UI is written to a file
# - a copy of the scripts is tested, in the copy only the user checks (built-in
#   Administrator, <sid>adm) are disabled and the key input is replaced
# usage: powershell.exe -ExecutionPolicy Bypass -File tests\windows\run_tests.ps1

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$testdir = $PSScriptRoot
$repo    = Split-Path -Parent (Split-Path -Parent $testdir)
$work    = Join-Path ([System.IO.Path]::GetTempPath()) ('expimp_test_' + [guid]::NewGuid().ToString('N'))
$null    = New-Item -ItemType Directory -Path $work
$sid     = 'TST'
$fakebin = Join-Path $testdir 'fake'

$script:failed     = 0
$script:testfailed = $false
$script:loc        = ''

Write-Host "PowerShell $($PSVersionTable.PSVersion) - work directory $work"

# key codes
$ENTER = '13'
$ESC   = '27'
$SPACE = '32'
$PGDN  = '34'
$LEFT  = '37'
$DOWN  = '40'

# replacement of the key input (added to the copy of script\sap_expimp_ui.ps1):
# the keys come from the file EXPIMP_TEST_KEYS (one key per line: a virtual key code
# or c:<character>), the screen is written to the file EXPIMP_TEST_SCREENS before every key
$mock = @'

# ----- test mode: keys from a file, every screen is written to a file -----
function Read-UiKey {
    $screen = ''
    try {
        $rui  = $Host.UI.RawUI
        $size = $rui.WindowSize
        $pos  = $rui.WindowPosition
        $rect = New-Object System.Management.Automation.Host.Rectangle $pos.X, $pos.Y, ($pos.X + $size.Width - 1), ($pos.Y + $size.Height - 1)
        $buf  = $rui.GetBufferContents($rect)
        $sb   = New-Object System.Text.StringBuilder
        for ($y = 0; $y -lt $size.Height; $y++) {
            $line = New-Object System.Text.StringBuilder
            for ($x = 0; $x -lt $size.Width; $x++) { [void]$line.Append($buf[$y, $x].Character) }
            [void]$sb.AppendLine($line.ToString().TrimEnd())
        }
        $screen = $sb.ToString()
    } catch {
        $screen = "SCREEN NOT READABLE: $($_.Exception.Message)`r`n"
    }
    $queue = @(Get-Content -LiteralPath $env:EXPIMP_TEST_KEYS)
    if ($queue.Count -eq 0) {
        Add-Content -LiteralPath $env:EXPIMP_TEST_SCREENS -Value "##### NO KEY LEFT`r`n$screen"
        [Environment]::Exit(77)
    }
    $entry = "$($queue[0])"
    $rest  = @()
    if ($queue.Count -gt 1) { $rest = @($queue[1..($queue.Count - 1)]) }
    [System.IO.File]::WriteAllLines($env:EXPIMP_TEST_KEYS, [string[]]$rest)
    Add-Content -LiteralPath $env:EXPIMP_TEST_SCREENS -Value "##### SCREEN (next key: $entry)`r`n$screen"
    if ($entry.StartsWith('c:')) {
        $ch = [char]$entry.Substring(2, 1)
        return [PSCustomObject]@{ VirtualKeyCode = [int][char]("$ch".ToUpper()); Character = $ch }
    }
    return [PSCustomObject]@{ VirtualKeyCode = [int]$entry; Character = [char]0 }
}
'@

function Start-Test {
    param([string]$Name)
    Write-Host "TEST $Name"
    $script:testfailed = $false
}

function Assert-That {
    param([bool]$Condition, [string]$Message)
    if ($Condition) {
        Write-Host "  ok   $Message"
    } else {
        Write-Host "  FAIL $Message"
        $script:failed++
        $script:testfailed = $true
    }
}

# shows the screens and the logfile of a failed test
function Complete-Test {
    param($Result)
    if (-not $script:testfailed) { return }
    Write-Host '---------- error output of the tool ----------'
    Write-Host $Result.ErrorOutput
    Write-Host '---------- screens of the failed test ----------'
    Write-Host $Result.Screens
    $locsid = Join-Path $script:loc $sid
    if (Test-Path -LiteralPath $locsid) {
        foreach ($f in @(Get-ChildItem -LiteralPath $locsid -File -Filter 'EXP_IMP_LOG_*.txt')) {
            Write-Host "---------- $($f.Name) ----------"
            foreach ($line in @(Get-Content -LiteralPath $f.FullName)) { Write-Host $line }
        }
        Write-Host '---------- files ----------'
        foreach ($f in @(Get-ChildItem -LiteralPath $locsid -Recurse)) { Write-Host $f.FullName }
    }
    Write-Host '------------------------------------------------'
}

function Edit-Text {
    param([string]$Text, [string]$Old, [string]$New)
    if (-not $Text.Contains($Old)) { throw "text not found: $Old" }
    return $Text.Replace($Old, $New)
}

function Test-FileLine {
    param([string]$Path, [string]$Pattern)
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    return (@(Select-String -LiteralPath $Path -Pattern $Pattern).Count -gt 0)
}

function Get-LogFile {
    $locsid = Join-Path $script:loc $sid
    $logs = @()
    if (Test-Path -LiteralPath $locsid) { $logs = @(Get-ChildItem -LiteralPath $locsid -File -Filter 'EXP_IMP_LOG_*.txt') }
    if ($logs.Count -eq 0) { return (Join-Path $locsid 'no_logfile') }
    return $logs[0].FullName
}

$templates = @(Get-ChildItem -LiteralPath (Join-Path $repo 'templates') -File | Sort-Object Name | ForEach-Object { $_.Name })

# keys to select templates in the checklist (names in the order of the list) and confirm
function Get-SelectKeys {
    param([string[]]$Names)
    $keys = @()
    $pos  = 0
    foreach ($n in $Names) {
        $idx = [array]::IndexOf($templates, $n)
        if ($idx -lt $pos) { throw "template $n not found or not in the order of the list" }
        while ($pos -lt $idx) { $keys += $DOWN; $pos++ }
        $keys += $SPACE
    }
    $keys += $ENTER
    return $keys
}

# runs the tool in its own console window, returns the exit code, the screens and
# the number of keys that were not used
function Invoke-Tool {
    param([string[]]$Keys = @(), [hashtable]$Config = @{}, [int]$Rows = 45, [switch]$NoR3trans)

    # fresh copy of the scripts
    $copy = Join-Path $work 'repo'
    if (Test-Path -LiteralPath $copy) { Remove-Item -LiteralPath $copy -Recurse -Force }
    $null = New-Item -ItemType Directory -Path (Join-Path $copy 'script')
    Copy-Item -LiteralPath (Join-Path $repo 'templates') -Destination $copy -Recurse
    foreach ($f in @('script\sap_expimp_ui.ps1', 'script\sap_export_tables.ps1', 'script\sap_import_tables.ps1')) {
        Copy-Item -LiteralPath (Join-Path $repo $f) -Destination (Join-Path $copy $f)
    }
    Add-Content -LiteralPath (Join-Path $copy 'script\sap_expimp_ui.ps1') -Value $mock

    # main script: user checks disabled, config of the test
    $main = [System.IO.File]::ReadAllText((Join-Path $repo 'sap_tab_exp_imp.ps1'))
    $main = Edit-Text $main 'if ($isBuiltInAdmin) {' 'if ($false) {'
    $main = Edit-Text $main 'if ($username -ne $sidadm) {' 'if ($false) {'
    $cfg = @{ EXPIMPLOC = "'$($script:loc)'"; EXPIMPGROUP = "''" }
    foreach ($k in @($Config.Keys)) { $cfg[$k] = $Config[$k] }
    foreach ($k in @($cfg.Keys)) {
        $rx = New-Object System.Text.RegularExpressions.Regex ('(?m)^\$' + $k + ' = [^\r\n]*')
        if (-not $rx.IsMatch($main)) { throw "config line of $k not found" }
        $main = $rx.Replace($main, ('$' + $k + ' = ' + $cfg[$k]).Replace('$', '$$'), 1)
    }
    $mainfile = Join-Path $copy 'sap_tab_exp_imp.ps1'
    [System.IO.File]::WriteAllText($mainfile, $main, (New-Object System.Text.UTF8Encoding $true))

    # the copies must be valid scripts
    foreach ($f in @($mainfile, (Join-Path $copy 'script\sap_expimp_ui.ps1'))) {
        $tokens = $null
        $errors = $null
        $null = [System.Management.Automation.Language.Parser]::ParseFile($f, [ref]$tokens, [ref]$errors)
        foreach ($e in @($errors)) { Write-Host "  syntax error in the copy $f, line $($e.Extent.StartLineNumber): $($e.Message)" }
    }

    $keyfile = Join-Path $work 'keys.txt'
    $scrfile = Join-Path $work 'screens.txt'
    $errfile = Join-Path $work 'error.txt'
    $cmderr  = Join-Path $work 'error_cmd.txt'
    [System.IO.File]::WriteAllLines($keyfile, [string[]]$Keys)
    if (Test-Path -LiteralPath $scrfile) { Remove-Item -LiteralPath $scrfile -Force }
    if (Test-Path -LiteralPath $errfile) { Remove-Item -LiteralPath $errfile -Force }

    # own console window with a defined size
    $ps      = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $cmdfile = Join-Path $work 'run.cmd'
    $cmdlines = @(
        '@echo off',
        "mode con: cols=100 lines=$Rows >nul 2>&1",
        "`"$ps`" -NoProfile -ExecutionPolicy Bypass -File `"$mainfile`" 2> `"$errfile`"",
        'exit /b %errorlevel%'
    )
    [System.IO.File]::WriteAllLines($cmdfile, [string[]]$cmdlines, (New-Object System.Text.ASCIIEncoding))

    $oldpath = $env:PATH
    $env:SAPSYSTEMNAME       = $sid
    $env:EXPIMP_TEST_KEYS    = $keyfile
    $env:EXPIMP_TEST_SCREENS = $scrfile
    if (-not $NoR3trans) { $env:PATH = "$fakebin;$oldpath" }
    $exitcode = -1
    try {
        $p = Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\cmd.exe') -ArgumentList "/c `"$cmdfile`"" -PassThru -RedirectStandardError $cmderr
        $null = $p.Handle
        if ($p.WaitForExit(900000)) {
            $exitcode = $p.ExitCode
        } else {
            & (Join-Path $env:SystemRoot 'System32\taskkill.exe') /T /F /PID $p.Id | Out-Null
            Write-Host '  the tool did not end within 15 minutes'
        }
    } finally {
        $env:PATH = $oldpath
    }

    $screens = ''
    if (Test-Path -LiteralPath $scrfile) { $screens = [System.IO.File]::ReadAllText($scrfile) }
    $erroroutput = ''
    if (Test-Path -LiteralPath $errfile) { $erroroutput = [System.IO.File]::ReadAllText($errfile) }
    if (Test-Path -LiteralPath $cmderr)  { $erroroutput = $erroroutput + [System.IO.File]::ReadAllText($cmderr) }
    $keysleft = @(Get-Content -LiteralPath $keyfile).Count
    return [PSCustomObject]@{ ExitCode = $exitcode; Screens = $screens; KeysLeft = $keysleft; ErrorOutput = $erroroutput }
}

# ---------------------------------------------------------------------------
Start-Test 'syntax of all scripts'
foreach ($f in @('sap_tab_exp_imp.ps1', 'script\sap_expimp_ui.ps1', 'script\sap_export_tables.ps1', 'script\sap_import_tables.ps1')) {
    $tokens = $null
    $errors = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $repo $f), [ref]$tokens, [ref]$errors)
    Assert-That (@($errors).Count -eq 0) "$f has no syntax errors"
    foreach ($e in @($errors)) { Write-Host "       line $($e.Extent.StartLineNumber): $($e.Message)" }
}

# ---------------------------------------------------------------------------
Start-Test 'export of two templates'
$script:loc = Join-Path $work 'loc1'
$locsid = Join-Path $script:loc $sid
$conf   = Join-Path $locsid 'exported_tables.conf'
$r = Invoke-Tool -Keys (@($ENTER) + @(Get-SelectKeys @('AL11', 'SM59')) + @($ENTER, $ENTER, $ENTER))
Assert-That ($r.ExitCode -eq 0) "exit code 0 (is $($r.ExitCode))"
Assert-That ($r.KeysLeft -eq 0) "all keys used ($($r.KeysLeft) left)"
Assert-That (Test-FileLine $conf '^AL11\|RC=0\|SHA256=[0-9a-f]{64}$') 'AL11 exported with checksum'
Assert-That (Test-FileLine $conf '^SM59\|RC=0\|SHA256=[0-9a-f]{64}$') 'SM59 exported with checksum'
Assert-That (Test-FileLine (Join-Path $locsid 'AL11.tpl') ('^' + [regex]::Escape("file = '" + (Join-Path $locsid 'AL11.dat') + "'") + '$')) 'control file with data file'
$tplbytes = @()
if (Test-Path -LiteralPath (Join-Path $locsid 'AL11.tpl')) { $tplbytes = @([System.IO.File]::ReadAllBytes((Join-Path $locsid 'AL11.tpl'))) }
Assert-That ($tplbytes.Count -gt 0 -and $tplbytes[0] -eq 0x65) 'control file without BOM'
Assert-That ((Test-Path -LiteralPath $locsid) -and (Get-Acl -LiteralPath $locsid).AreAccessRulesProtected) 'permissions of EXPIMPLOC are protected'
Assert-That ($r.Screens.Contains('EXPORT or IMPORT Tables?')) 'screen: start dialog'
Assert-That ($r.Screens.Contains('(*) EXPORT')) 'screen: EXPORT is marked'
Assert-That ($r.Screens.Contains('Select the Templates for Export:')) 'screen: template selection'
Assert-That ($r.Screens.Contains('R3trans (test) message on stderr')) 'screen: error output of R3trans'
Assert-That ($r.Screens.Contains('Export procedure finished with RC=0')) 'screen: summary'
Complete-Test $r

# ---------------------------------------------------------------------------
Start-Test 'export with a failed table, ESC in the overview'
$r = Invoke-Tool -Keys (@($ENTER, $ENTER) + @(Get-SelectKeys @('AL11', 'RZ04')) + @($ENTER, $ESC, $ENTER))
Assert-That ($r.ExitCode -eq 13) "exit code 13 (is $($r.ExitCode))"
Assert-That ($r.KeysLeft -eq 0) "all keys used ($($r.KeysLeft) left)"
$backups = @()
if (Test-Path -LiteralPath (Join-Path $locsid 'backup')) { $backups = @(Get-ChildItem -LiteralPath (Join-Path $locsid 'backup') -Directory) }
Assert-That ($backups.Count -eq 1) 'backup of the previous run'
Assert-That ($r.Screens.Contains('at least one table failed')) 'screen: hint in the summary'
Complete-Test $r

# ---------------------------------------------------------------------------
Start-Test 'export, ESC in the overview'
$r = Invoke-Tool -Keys (@($ENTER, $ENTER) + @(Get-SelectKeys @('AL11', 'SM59')) + @($ENTER, $ESC, $ENTER))
Assert-That ($r.ExitCode -eq 0) "exit code 0 (is $($r.ExitCode))"
Assert-That ($r.KeysLeft -eq 0) "all keys used ($($r.KeysLeft) left)"
Complete-Test $r

# ---------------------------------------------------------------------------
Start-Test 'import from a backup (list with one choice: cursor = selection), ESC in the overview'
# start dialog: DOWN ENTER (IMPORT) - export: DOWN ENTER (newest backup) - exports: ENTER -
# confirmation: LEFT ENTER (Import) - progress: ENTER - overview: ESC - summary: ENTER
$r = Invoke-Tool -Keys @($DOWN, $ENTER, $DOWN, $ENTER, $ENTER, $LEFT, $ENTER, $ENTER, $ESC, $ENTER)
Assert-That ($r.ExitCode -eq 0) "exit code 0 (is $($r.ExitCode))"
Assert-That ($r.KeysLeft -eq 0) "all keys used ($($r.KeysLeft) left)"
Assert-That (Test-FileLine (Get-LogFile) 'INFO: import from .*\\backup\\[0-9_]+$') 'import from the backup'
Assert-That ($r.Screens.Contains('(*) IMPORT')) 'screen: IMPORT is marked after DOWN'
Assert-That ($r.Screens.Contains('[ Import ]')) 'screen: button Import'
Assert-That ($r.Screens.Contains('Import procedure finished with RC=0')) 'screen: summary'
Complete-Test $r

# ---------------------------------------------------------------------------
Start-Test 'import with a failed table, ESC in the overview'
if (Test-Path -LiteralPath (Join-Path $locsid 'SM59.dat')) {
    Copy-Item -LiteralPath (Join-Path $locsid 'SM59.dat') -Destination (Join-Path $locsid 'FAIL.dat')
    $lines = @(Get-Content -LiteralPath $conf | ForEach-Object { $_; if ($_ -like 'SM59|*') { $_ -replace '^SM59', 'FAIL' } })
    [System.IO.File]::WriteAllLines($conf, [string[]]$lines, (New-Object System.Text.ASCIIEncoding))
}
# start dialog: DOWN ENTER - export: ENTER (current) - exports: ENTER - confirmation: y -
# progress: ENTER - overview: ESC - summary: ENTER
$r = Invoke-Tool -Keys @($DOWN, $ENTER, $ENTER, $ENTER, 'c:y', $ENTER, $ESC, $ENTER)
Assert-That ($r.ExitCode -eq 25) "exit code 25 (is $($r.ExitCode))"
Assert-That ($r.KeysLeft -eq 0) "all keys used ($($r.KeysLeft) left)"
Assert-That (Test-FileLine (Join-Path $locsid 'imported_tables.conf') '^FAIL\|RC=12$') 'return code of the failed table'
Assert-That ($r.Screens.Contains('Import procedure finished with RC=25')) 'screen: summary'
Complete-Test $r

# ---------------------------------------------------------------------------
Start-Test 'import with a changed data file'
if (Test-Path -LiteralPath (Join-Path $locsid 'AL11.dat')) { Add-Content -LiteralPath (Join-Path $locsid 'AL11.dat') -Value 'changed' }
# start dialog: DOWN ENTER - export: ENTER - previous selection: ENTER (Continue) - exports: ENTER -
# checksum error: ENTER - summary: ENTER
$r = Invoke-Tool -Keys @($DOWN, $ENTER, $ENTER, $ENTER, $ENTER, $ENTER, $ENTER)
Assert-That ($r.ExitCode -eq 27) "exit code 27 (is $($r.ExitCode))"
Assert-That ($r.KeysLeft -eq 0) "all keys used ($($r.KeysLeft) left)"
Assert-That ($r.Screens.Contains('Checksum verification FAILED')) 'screen: checksum error'
Complete-Test $r

# ---------------------------------------------------------------------------
Start-Test 'import of an export without metadata (SID has to be typed in)'
$script:loc = Join-Path $work 'loc2'
$locsid = Join-Path $script:loc $sid
$conf   = Join-Path $locsid 'exported_tables.conf'
$r = Invoke-Tool -Keys (@($ENTER) + @(Get-SelectKeys @('AL11')) + @($ENTER, $ENTER, $ENTER))
Assert-That ($r.ExitCode -eq 0) "export: exit code 0 (is $($r.ExitCode))"
Complete-Test $r
if (Test-Path -LiteralPath $conf) {
    $lines = @(Get-Content -LiteralPath $conf | Where-Object { $_ -notmatch '^# (SID|HOST|CLIENT|USER|DATE)=' })
    [System.IO.File]::WriteAllLines($conf, [string[]]$lines, (New-Object System.Text.ASCIIEncoding))
}
# start dialog: DOWN ENTER - exports: ENTER - confirmation: y - SID: T S T ENTER -
# progress: ENTER - overview: ENTER - summary: ENTER
$r = Invoke-Tool -Keys @($DOWN, $ENTER, $ENTER, 'c:y', 'c:T', 'c:S', 'c:T', $ENTER, $ENTER, $ENTER, $ENTER)
Assert-That ($r.ExitCode -eq 0) "import: exit code 0 (is $($r.ExitCode))"
Assert-That ($r.KeysLeft -eq 0) "all keys used ($($r.KeysLeft) left)"
Assert-That ($r.Screens.Contains('> TST_')) 'screen: typed SID'
Assert-That (Test-FileLine (Get-LogFile) 'NO CHECKSUM') 'log: export without checksum'
Complete-Test $r

# ---------------------------------------------------------------------------
Start-Test 'ESC at the STMS_QA hint'
$script:loc = Join-Path $work 'loc3'
$locsid = Join-Path $script:loc $sid
$r = Invoke-Tool -Keys (@($ENTER) + @(Get-SelectKeys @('STMS_QA')) + @($ESC, $ENTER))
Assert-That ($r.ExitCode -eq 96) "exit code 96 (is $($r.ExitCode))"
Assert-That ($r.KeysLeft -eq 0) "all keys used ($($r.KeysLeft) left)"
Assert-That (-not (Test-Path -LiteralPath (Join-Path $locsid 'exported_tables.conf'))) 'no info file'
Assert-That (-not (Test-Path -LiteralPath (Join-Path $locsid 'selected_tables_for_export.conf'))) 'no selection file'
Complete-Test $r

# ---------------------------------------------------------------------------
Start-Test 'all templates, window with 30 rows: the confirmation of the import can be scrolled'
$script:loc = Join-Path $work 'loc4'
$locsid = Join-Path $script:loc $sid
# start dialog: ENTER - templates: a (all) ENTER - STMS_QA hint: ENTER - progress: ENTER -
# overview: ENTER - summary: ENTER
$r = Invoke-Tool -Rows 30 -Keys @($ENTER, 'c:a', $ENTER, $ENTER, $ENTER, $ENTER, $ENTER)
Assert-That ($r.ExitCode -eq 13) "export: exit code 13, RZ04 fails (is $($r.ExitCode))"
Assert-That ($r.KeysLeft -eq 0) "export: all keys used ($($r.KeysLeft) left)"
Assert-That ($r.Screens.Contains("selected: $($templates.Count)")) 'screen: all templates selected'
Complete-Test $r
# start dialog: DOWN ENTER - exports: ENTER - confirmation: PGDN LEFT ENTER -
# progress: ENTER - overview: ENTER - summary: ENTER
$r = Invoke-Tool -Rows 30 -Keys @($DOWN, $ENTER, $ENTER, $PGDN, $LEFT, $ENTER, $ENTER, $ENTER, $ENTER)
Assert-That ($r.ExitCode -eq 0) "import: exit code 0 (is $($r.ExitCode))"
Assert-That ($r.KeysLeft -eq 0) "import: all keys used ($($r.KeysLeft) left)"
Assert-That ($r.Screens -match 'scroll - lines 1-\d+ of \d+') 'screen: scroll position of the first page'
Assert-That ($r.Screens.Contains('[ Exit ]')) 'screen: button Exit is visible (default)'
Assert-That ($r.Screens.Contains('Continue with the import?')) 'screen: end of the text after PGDN'
Assert-That ($r.Screens.Contains('[ Import ]')) 'screen: button Import after LEFT'
Complete-Test $r

# ---------------------------------------------------------------------------
Start-Test 'config values'
$script:loc = Join-Path $work 'loc5'
$locsid = Join-Path $script:loc $sid
$r = Invoke-Tool -Config @{ PARALLEL = '08' } -Keys (@($ENTER) + @(Get-SelectKeys @('AL11')) + @($ENTER, $ENTER, $ENTER))
Assert-That ($r.ExitCode -eq 0) "PARALLEL = 08: exit code 0 (is $($r.ExitCode))"
Assert-That (Test-FileLine (Join-Path $locsid 'AL11.tpl') '^parallel = 8$') 'PARALLEL = 08 is 8'
Complete-Test $r
$r = Invoke-Tool -Config @{ PARALLEL = '1234567890' }
Assert-That ($r.ExitCode -eq 91) "PARALLEL = 1234567890: exit code 91 (is $($r.ExitCode))"
$r = Invoke-Tool -Config @{ EXPIMPLOC = ("'C:\expimp_" + [char]0xFC + "'"); ADDSIDTOEXPIMP = "'FALSE'" }
Assert-That ($r.ExitCode -eq 91) "EXPIMPLOC with a non-ASCII character: exit code 91 (is $($r.ExitCode))"
Complete-Test $r

# ---------------------------------------------------------------------------
Start-Test 'EXPIMPLOC with other files: the permissions are not changed'
$script:loc = Join-Path $work 'loc6'
$locsid = Join-Path $script:loc $sid
$null = New-Item -ItemType Directory -Path $locsid
Set-Content -LiteralPath (Join-Path $locsid 'notes.txt') -Value 'other file'
$r = Invoke-Tool -Keys @($ESC)
Assert-That ($r.ExitCode -eq 96) "exit code 96 (is $($r.ExitCode))"
Assert-That (Test-FileLine (Get-LogFile) 'WARNING: .*do not belong to this tool \(e\.g\. notes\.txt\)') 'log: warning'
Assert-That ((Test-Path -LiteralPath $locsid) -and -not (Get-Acl -LiteralPath $locsid).AreAccessRulesProtected) 'permissions of EXPIMPLOC are not changed'
Complete-Test $r

# ---------------------------------------------------------------------------
Start-Test 'R3trans not found'
$script:loc = Join-Path $work 'loc7'
$r = Invoke-Tool -NoR3trans
Assert-That ($r.ExitCode -eq 95) "exit code 95 (is $($r.ExitCode))"
Complete-Test $r

# ---------------------------------------------------------------------------
try { Remove-Item -LiteralPath $work -Recurse -Force } catch { Write-Host "cannot delete $work" }

Write-Host ''
if ($script:failed -ne 0) {
    Write-Host "$($script:failed) check(s) FAILED"
    exit 1
}
Write-Host 'all checks ok'
exit 0
