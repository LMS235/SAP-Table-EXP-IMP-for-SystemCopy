# stand-in for R3trans.exe (tests), called by R3trans.cmd
# export (-w <log> <control file>): writes the data file of the control file,
#                                   the template RZ04 ends with RC 8
# import (-w <log> -i <data file>): a data file with FAIL in its name ends with RC 12

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$list = @($args)
if ($list.Count -lt 3 -or "$($list[0])" -ne '-w') {
    Write-Output 'R3trans (test): unexpected arguments'
    exit 16
}
$log = "$($list[1])"

if ("$($list[2])" -eq '-i') {
    if ($list.Count -lt 4) { exit 16 }
    $dat = "$($list[3])"
    Set-Content -LiteralPath $log -Value "import $dat"
    Write-Output "R3trans (test) import $dat"
    if ($dat -like '*FAIL*') { exit 12 }
    exit 0
}

$tpl = "$($list[2])"
$dat = ''
foreach ($line in @(Get-Content -LiteralPath $tpl)) {
    if ($line -match "^file = '(.*)'$") { $dat = $Matches[1] }
}
Set-Content -LiteralPath $log -Value "export $tpl"
Write-Output "R3trans (test) export $tpl"
[Console]::Error.WriteLine('R3trans (test) message on stderr')
if ($tpl -like '*RZ04*') { exit 8 }
if (-not $dat) { exit 12 }
Set-Content -LiteralPath $dat -Value "data of $tpl"
exit 0
