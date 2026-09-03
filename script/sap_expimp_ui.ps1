# SAP(R) Table EXP/IMP for SystemCopy (c) Florian Lamml 2026
# www.florian-lamml.de
# Console UI helper (PowerShell / Windows) - replacement for the linux 'dialog' command
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

# --- key codes -----------------------------------------------------------
$Global:UiKeyEnter = 13
$Global:UiKeyEsc   = 27
$Global:UiKeySpace = 32
$Global:UiKeyPgUp  = 33
$Global:UiKeyPgDn  = 34
$Global:UiKeyEnd   = 35
$Global:UiKeyHome  = 36
$Global:UiKeyUp    = 38
$Global:UiKeyDown  = 40

# --- colors (mimics the look of 'dialog') --------------------------------
$Global:UiScreenBg = 'DarkBlue'
$Global:UiScreenFg = 'Gray'
$Global:UiBoxBg    = 'Gray'
$Global:UiBoxFg    = 'Black'
$Global:UiFrameFg  = 'DarkGray'
$Global:UiTitleFg  = 'DarkBlue'
$Global:UiSelBg    = 'DarkBlue'
$Global:UiSelFg    = 'White'

$Global:UiFrameHeight = 0

# -------------------------------------------------------------------------
# Host capabilities - the console host must support ReadKey and cursor moves
# (this is the windows equivalent of the "is 'dialog' available" check)
# -------------------------------------------------------------------------
function Test-UiHost {
    if ($Host.Name -like '*ISE*') { return $false }
    try {
        $null = $Host.UI.RawUI.WindowSize
        $null = $Host.UI.RawUI.CursorPosition
        $null = $Host.UI.RawUI.KeyAvailable
    } catch {
        return $false
    }
    return $true
}

# -------------------------------------------------------------------------
# logfile helper (shared by main / export / import script)
# -------------------------------------------------------------------------
function Write-ExpImpLog {
    param([string]$Message)
    Add-Content -LiteralPath $Global:EXPIMPLOGFILE -Value $Message -Encoding ascii
}

function Read-UiKey {
    return $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
}

# -------------------------------------------------------------------------
# frame primitives
# -------------------------------------------------------------------------
function New-UiSeg {
    param([string]$Text = '', [string]$Fg = $Global:UiScreenFg, [string]$Bg = $Global:UiScreenBg)
    return [PSCustomObject]@{ Text = $Text; Fg = $Fg; Bg = $Bg }
}

# window / buffer size of the console - falls back to the classic 80x45 dialog
# size if the host does not report a usable size (e.g. redirected output)
function Get-UiScreenSize {
    $w = 80; $h = 45; $bw = 80
    try {
        $ws = $Host.UI.RawUI.WindowSize
        if ([int]$ws.Width  -gt 0) { $w = [int]$ws.Width }
        if ([int]$ws.Height -gt 0) { $h = [int]$ws.Height }
    } catch { }
    try {
        $bs = $Host.UI.RawUI.BufferSize
        if ([int]$bs.Width -gt 0) { $bw = [int]$bs.Width } else { $bw = $w }
    } catch { $bw = $w }
    if ($bw -lt $w) { $w = $bw }
    return [PSCustomObject]@{ W = $w; H = $h; BW = $bw }
}

function Get-UiBoxSize {
    $s    = Get-UiScreenSize
    $scrW = $s.W
    $scrH = $s.H

    $w = [Math]::Min([int]$Global:global_width,  $scrW - 2)
    $h = [Math]::Min([int]$Global:global_height, $scrH - 4)
    if ($w -lt 40) { $w = [Math]::Max(40, $scrW - 2) }
    if ($h -lt 12) { $h = [Math]::Max(12, $scrH - 4) }

    $pad = [Math]::Max(0, [int](($scrW - $w) / 2))

    return [PSCustomObject]@{
        W    = $w
        H    = $h
        InW  = $w - 4
        InH  = $h - 2
        ScrW = $scrW
        ScrH = $scrH
        Pad  = (' ' * $pad)
    }
}

function New-UiInnerRow {
    param($Box, [string]$Text = '', [string]$Fg = $Global:UiBoxFg, [string]$Bg = $Global:UiBoxBg)
    if ($null -eq $Text) { $Text = '' }
    if ($Text.Length -gt $Box.InW) { $Text = $Text.Substring(0, $Box.InW) }
    return ,@(
        (New-UiSeg $Box.Pad),
        (New-UiSeg '| ' $Global:UiFrameFg $Global:UiBoxBg),
        (New-UiSeg $Text.PadRight($Box.InW) $Fg $Bg),
        (New-UiSeg ' |' $Global:UiFrameFg $Global:UiBoxBg)
    )
}

function New-UiBorderRow {
    param($Box, [string]$Title = '')
    $inner = $Box.W - 2
    if ($Title) {
        $t = " $Title "
        if ($t.Length -gt $inner - 2) { $t = $t.Substring(0, $inner - 2) }
        $left  = [int](($inner - $t.Length) / 2)
        $right = $inner - $t.Length - $left
        return ,@(
            (New-UiSeg $Box.Pad),
            (New-UiSeg ('+' + ('-' * $left)) $Global:UiFrameFg $Global:UiBoxBg),
            (New-UiSeg $t $Global:UiTitleFg $Global:UiBoxBg),
            (New-UiSeg (('-' * $right) + '+') $Global:UiFrameFg $Global:UiBoxBg)
        )
    }
    return ,@(
        (New-UiSeg $Box.Pad),
        (New-UiSeg ('+' + ('-' * $inner) + '+') $Global:UiFrameFg $Global:UiBoxBg)
    )
}

# builds the complete screen: backtitle, separator, centered box, blue backdrop
function Build-UiFrame {
    param($Box, [string]$Title, $InnerRows)

    $frame = New-Object System.Collections.Generic.List[object]
    $frame.Add(@((New-UiSeg (' ' + $Global:global_backtitle) 'White' $Global:UiScreenBg)))
    $frame.Add(@((New-UiSeg ('=' * ($Box.ScrW - 1)) 'DarkCyan' $Global:UiScreenBg)))
    $frame.Add((New-UiBorderRow $Box $Title))

    $count = 0
    foreach ($row in $InnerRows) {
        if ($count -ge $Box.InH) { break }
        $frame.Add($row)
        $count++
    }
    while ($count -lt $Box.InH) {
        $frame.Add((New-UiInnerRow $Box ''))
        $count++
    }

    $frame.Add((New-UiBorderRow $Box))
    return $frame
}

function Write-UiFrame {
    param($Frame)
    $rui = $Host.UI.RawUI
    $scr = Get-UiScreenSize
    $w   = $scr.W - 1
    try {
        $rui.CursorPosition = New-Object System.Management.Automation.Host.Coordinates 0, 0
    } catch {
        Clear-Host
    }

    $rows = 0
    foreach ($row in $Frame) {
        $used = 0
        foreach ($seg in $row) {
            if ($used -ge $w) { break }
            $t = $seg.Text
            if ($null -eq $t) { $t = '' }
            if ($used + $t.Length -gt $w) { $t = $t.Substring(0, $w - $used) }
            if ($t.Length -gt 0) {
                $fg = $seg.Fg; if (-not $fg) { $fg = 'Gray' }
                $bg = $seg.Bg; if (-not $bg) { $bg = 'DarkBlue' }
                Write-Host $t -NoNewline -ForegroundColor $fg -BackgroundColor $bg
                $used += $t.Length
            }
        }
        if ($used -lt $w) {
            Write-Host (' ' * ($w - $used)) -NoNewline -ForegroundColor $Global:UiScreenFg -BackgroundColor $Global:UiScreenBg
        }
        Write-Host ''
        $rows++
    }

    # blue backdrop for the rest of the screen / clear leftovers of the last frame
    $fill = [Math]::Max($Global:UiFrameHeight, $scr.H - 1)
    for ($i = $rows; $i -lt $fill; $i++) {
        Write-Host (' ' * $w) -NoNewline -ForegroundColor $Global:UiScreenFg -BackgroundColor $Global:UiScreenBg
        Write-Host ''
    }
    $Global:UiFrameHeight = $rows
}

function Split-UiText {
    param([string]$Text, [int]$Width)
    $out = New-Object System.Collections.Generic.List[string]
    if ($null -eq $Text) { $Text = '' }
    foreach ($raw in ($Text -split "`r?`n")) {
        if ($raw.Length -le $Width) {
            $out.Add($raw)
            continue
        }
        $line = ''
        foreach ($word in ($raw -split ' ')) {
            if ($line.Length -eq 0) {
                $line = $word
            } elseif (($line.Length + 1 + $word.Length) -le $Width) {
                $line = "$line $word"
            } else {
                $out.Add($line)
                $line = $word
            }
            while ($line.Length -gt $Width) {
                $out.Add($line.Substring(0, $Width))
                $line = $line.Substring($Width)
            }
        }
        $out.Add($line)
    }
    return $out
}

function New-UiButtonRow {
    param($Box, [string[]]$Buttons)
    $text = '  ' + ($Buttons -join '   ')
    $left = [Math]::Max(0, [int](($Box.InW - $text.Length) / 2))
    return (New-UiInnerRow $Box ((' ' * $left) + $text) $Global:UiTitleFg $Global:UiBoxBg)
}

# -------------------------------------------------------------------------
# msgbox   -> returns 0 (ok) or 255 (ESC)
# -------------------------------------------------------------------------
function Show-UiMsgBox {
    param([string]$Text, [string]$OkLabel = 'OK')
    Clear-Host
    $Global:UiFrameHeight = 0
    while ($true) {
        $box  = Get-UiBoxSize
        $rows = New-Object System.Collections.Generic.List[object]
        $rows.Add((New-UiInnerRow $box ''))
        foreach ($l in (Split-UiText $Text ($box.InW - 2))) {
            $rows.Add((New-UiInnerRow $box (' ' + $l)))
        }
        while ($rows.Count -lt ($box.InH - 2)) { $rows.Add((New-UiInnerRow $box '')) }
        $rows.Add((New-UiButtonRow $box @("< $OkLabel >")))
        $rows.Add((New-UiInnerRow $box ''))
        Write-UiFrame (Build-UiFrame $box $Global:global_title $rows)

        $key = Read-UiKey
        if ($key.VirtualKeyCode -eq $Global:UiKeyEsc) { Clear-Host; return 255 }
        if ($key.VirtualKeyCode -eq $Global:UiKeyEnter -or $key.VirtualKeyCode -eq $Global:UiKeySpace) { Clear-Host; return 0 }
    }
}

# -------------------------------------------------------------------------
# yesno    -> returns 0 (yes) / 1 (no) / 255 (ESC)
# -------------------------------------------------------------------------
function Show-UiYesNo {
    param([string]$Text, [string]$YesLabel = 'Yes', [string]$NoLabel = 'No')
    Clear-Host
    $Global:UiFrameHeight = 0
    $cur = 0
    while ($true) {
        $box  = Get-UiBoxSize
        $rows = New-Object System.Collections.Generic.List[object]
        $rows.Add((New-UiInnerRow $box ''))
        foreach ($l in (Split-UiText $Text ($box.InW - 2))) {
            $rows.Add((New-UiInnerRow $box (' ' + $l)))
        }
        while ($rows.Count -lt ($box.InH - 3)) { $rows.Add((New-UiInnerRow $box '')) }

        $y = if ($cur -eq 0) { "[ $YesLabel ]" } else { "  $YesLabel  " }
        $n = if ($cur -eq 1) { "[ $NoLabel ]" }  else { "  $NoLabel  " }
        $txt  = "$y    $n"
        $left = [Math]::Max(0, [int](($box.InW - $txt.Length) / 2))
        $rows.Add((New-UiInnerRow $box ((' ' * $left) + $txt) $Global:UiTitleFg $Global:UiBoxBg))
        $rows.Add((New-UiInnerRow $box ''))
        $rows.Add((New-UiInnerRow $box '  [LEFT/RIGHT/TAB] switch   [ENTER] confirm   [ESC] cancel' $Global:UiFrameFg $Global:UiBoxBg))
        Write-UiFrame (Build-UiFrame $box $Global:global_title $rows)

        $key = Read-UiKey
        switch ($key.VirtualKeyCode) {
            $Global:UiKeyEsc   { Clear-Host; return 255 }
            $Global:UiKeyEnter { Clear-Host; return $cur }
            37 { $cur = 0 }                 # left
            39 { $cur = 1 }                 # right
            9  { $cur = 1 - $cur }          # tab
            default {
                $c = "$($key.Character)".ToLower()
                if ($c -eq 'y') { Clear-Host; return 0 }
                if ($c -eq 'n') { Clear-Host; return 1 }
            }
        }
    }
}

# -------------------------------------------------------------------------
# radiolist -> returns [PSCustomObject] Cancelled / Tag
# Items: objects with .Tag, .Item, .On
# -------------------------------------------------------------------------
function Show-UiRadioList {
    param([string]$Text, $Items)
    Clear-Host
    $Global:UiFrameHeight = 0
    $list = @($Items)
    $cur = 0
    $set = 0
    for ($i = 0; $i -lt $list.Count; $i++) { if ($list[$i].On) { $set = $i; $cur = $i; break } }
    $top = 0

    while ($true) {
        $box  = Get-UiBoxSize
        $head = @(Split-UiText $Text ($box.InW - 2))
        # drop leading header lines (ascii art) until the list and the buttons fit
        while ($head.Count -gt 0 -and ($box.InH - $head.Count - 4) -lt [Math]::Min(3, $list.Count)) {
            $head = @($head[1..($head.Count - 1)])
        }
        $avail = $box.InH - $head.Count - 4
        if ($avail -lt 1) { $avail = 1 }
        if ($cur -lt $top) { $top = $cur }
        if ($cur -ge $top + $avail) { $top = $cur - $avail + 1 }

        $rows = New-Object System.Collections.Generic.List[object]
        foreach ($l in $head) { $rows.Add((New-UiInnerRow $box (' ' + $l))) }
        $rows.Add((New-UiInnerRow $box ''))
        for ($i = $top; $i -lt [Math]::Min($top + $avail, $list.Count); $i++) {
            $mark = if ($i -eq $set) { '(*)' } else { '( )' }
            $line = "  $mark $($list[$i].Item)"
            if ($i -eq $cur) {
                $rows.Add((New-UiInnerRow $box $line $Global:UiSelFg $Global:UiSelBg))
            } else {
                $rows.Add((New-UiInnerRow $box $line))
            }
        }
        while ($rows.Count -lt ($box.InH - 3)) { $rows.Add((New-UiInnerRow $box '')) }
        $rows.Add((New-UiButtonRow $box @('< OK >', '<Cancel>')))
        $rows.Add((New-UiInnerRow $box ''))
        $rows.Add((New-UiInnerRow $box '  [UP/DOWN] move   [SPACE] select   [ENTER] OK   [ESC] cancel' $Global:UiFrameFg $Global:UiBoxBg))
        Write-UiFrame (Build-UiFrame $box $Global:global_title $rows)

        $key = Read-UiKey
        switch ($key.VirtualKeyCode) {
            $Global:UiKeyEsc   { Clear-Host; return [PSCustomObject]@{ Cancelled = $true;  Tag = $null } }
            $Global:UiKeyUp    { if ($cur -gt 0) { $cur-- } }
            $Global:UiKeyDown  { if ($cur -lt $list.Count - 1) { $cur++ } }
            $Global:UiKeyHome  { $cur = 0 }
            $Global:UiKeyEnd   { $cur = $list.Count - 1 }
            $Global:UiKeySpace { $set = $cur }
            $Global:UiKeyEnter { $set = $cur; Clear-Host; return [PSCustomObject]@{ Cancelled = $false; Tag = $list[$set].Tag } }
        }
    }
}

# -------------------------------------------------------------------------
# checklist -> returns [PSCustomObject] Cancelled / Tags
# Items: objects with .Tag, .Item, .On
# -------------------------------------------------------------------------
function Show-UiCheckList {
    param([string]$Text, $Items)
    Clear-Host
    $Global:UiFrameHeight = 0
    $list = @($Items)
    if ($list.Count -eq 0) {
        return [PSCustomObject]@{ Cancelled = $false; Tags = @() }
    }
    $state = New-Object 'bool[]' $list.Count
    for ($i = 0; $i -lt $list.Count; $i++) { $state[$i] = [bool]$list[$i].On }
    $cur = 0
    $top = 0

    while ($true) {
        $box   = Get-UiBoxSize
        $head  = Split-UiText $Text ($box.InW - 2)
        $avail = $box.InH - $head.Count - 4
        if ($avail -lt 1) { $avail = 1 }
        if ($cur -lt $top) { $top = $cur }
        if ($cur -ge $top + $avail) { $top = $cur - $avail + 1 }

        $checked = 0
        foreach ($s in $state) { if ($s) { $checked++ } }

        $rows = New-Object System.Collections.Generic.List[object]
        foreach ($l in $head) { $rows.Add((New-UiInnerRow $box (' ' + $l))) }
        $rows.Add((New-UiInnerRow $box ("  ($($cur + 1)/$($list.Count))  selected: $checked" ) $Global:UiFrameFg $Global:UiBoxBg))
        for ($i = $top; $i -lt [Math]::Min($top + $avail, $list.Count); $i++) {
            $mark = if ($state[$i]) { '[X]' } else { '[ ]' }
            $scroll = ' '
            if ($i -eq $top -and $top -gt 0) { $scroll = '^' }
            if ($i -eq $top + $avail - 1 -and ($top + $avail) -lt $list.Count) { $scroll = 'v' }
            $line = "$scroll $mark $($list[$i].Item)"
            if ($i -eq $cur) {
                $rows.Add((New-UiInnerRow $box $line $Global:UiSelFg $Global:UiSelBg))
            } else {
                $rows.Add((New-UiInnerRow $box $line))
            }
        }
        while ($rows.Count -lt ($box.InH - 3)) { $rows.Add((New-UiInnerRow $box '')) }
        $rows.Add((New-UiButtonRow $box @('< OK >', '<Cancel>')))
        $rows.Add((New-UiInnerRow $box ''))
        $rows.Add((New-UiInnerRow $box '  [SPACE] toggle  [A] all  [N] none  [ENTER] OK  [ESC] cancel' $Global:UiFrameFg $Global:UiBoxBg))
        Write-UiFrame (Build-UiFrame $box $Global:global_title $rows)

        $key = Read-UiKey
        switch ($key.VirtualKeyCode) {
            $Global:UiKeyEsc   { Clear-Host; return [PSCustomObject]@{ Cancelled = $true; Tags = @() } }
            $Global:UiKeyUp    { if ($cur -gt 0) { $cur-- } }
            $Global:UiKeyDown  { if ($cur -lt $list.Count - 1) { $cur++ } }
            $Global:UiKeyPgUp  { $cur = [Math]::Max(0, $cur - $avail) }
            $Global:UiKeyPgDn  { $cur = [Math]::Min($list.Count - 1, $cur + $avail) }
            $Global:UiKeyHome  { $cur = 0 }
            $Global:UiKeyEnd   { $cur = $list.Count - 1 }
            $Global:UiKeySpace { $state[$cur] = -not $state[$cur] }
            $Global:UiKeyEnter {
                $tags = @()
                for ($i = 0; $i -lt $list.Count; $i++) { if ($state[$i]) { $tags += $list[$i].Tag } }
                Clear-Host
                return [PSCustomObject]@{ Cancelled = $false; Tags = $tags }
            }
            default {
                $c = "$($key.Character)".ToLower()
                if ($c -eq 'a') { for ($i = 0; $i -lt $list.Count; $i++) { $state[$i] = $true } }
                if ($c -eq 'n') { for ($i = 0; $i -lt $list.Count; $i++) { $state[$i] = $false } }
            }
        }
    }
}

# -------------------------------------------------------------------------
# textbox  -> returns 0 (ok) or 255 (ESC)
# -------------------------------------------------------------------------
function Show-UiTextBox {
    param([string]$Path, [string]$ExitLabel = 'Continue')
    Clear-Host
    $Global:UiFrameHeight = 0
    $content = @()
    if (Test-Path -LiteralPath $Path) { $content = @(Get-Content -LiteralPath $Path) }
    $top = 0

    while ($true) {
        $box   = Get-UiBoxSize
        $avail = $box.InH - 4
        if ($avail -lt 1) { $avail = 1 }
        $max = [Math]::Max(0, $content.Count - $avail)
        if ($top -gt $max) { $top = $max }
        if ($top -lt 0)    { $top = 0 }

        $rows = New-Object System.Collections.Generic.List[object]
        $rows.Add((New-UiInnerRow $box ''))
        for ($i = $top; $i -lt [Math]::Min($top + $avail, $content.Count); $i++) {
            $rows.Add((New-UiInnerRow $box (' ' + $content[$i])))
        }
        while ($rows.Count -lt ($box.InH - 3)) { $rows.Add((New-UiInnerRow $box '')) }
        $rows.Add((New-UiButtonRow $box @("< $ExitLabel >")))
        $rows.Add((New-UiInnerRow $box ''))
        $rows.Add((New-UiInnerRow $box "  [UP/DOWN/PGUP/PGDN] scroll   [ENTER] $ExitLabel   [ESC] cancel" $Global:UiFrameFg $Global:UiBoxBg))
        Write-UiFrame (Build-UiFrame $box $Global:global_title $rows)

        $key = Read-UiKey
        switch ($key.VirtualKeyCode) {
            $Global:UiKeyEsc   { Clear-Host; return 255 }
            $Global:UiKeyEnter { Clear-Host; return 0 }
            $Global:UiKeyUp    { $top-- }
            $Global:UiKeyDown  { $top++ }
            $Global:UiKeyPgUp  { $top -= $avail }
            $Global:UiKeyPgDn  { $top += $avail }
            $Global:UiKeyHome  { $top = 0 }
            $Global:UiKeyEnd   { $top = $max }
        }
    }
}

# -------------------------------------------------------------------------
# progressbox - streaming output area (R3trans writes into it)
# -------------------------------------------------------------------------
function Start-UiProgressView {
    param([string]$Text)
    Clear-Host
    $Global:UiFrameHeight = 0
    $w = (Get-UiScreenSize).W - 1
    Write-Host (' ' + $Global:global_backtitle).PadRight($w) -ForegroundColor White -BackgroundColor $Global:UiScreenBg
    Write-Host ('=' * $w) -ForegroundColor DarkCyan -BackgroundColor $Global:UiScreenBg
    Write-Host ''
    Write-Host "  $Text" -ForegroundColor Yellow
    Write-Host ('  ' + ('-' * [Math]::Max(1, $w - 4))) -ForegroundColor DarkGray
    Write-Host ''
}

function Complete-UiProgressView {
    Write-Host ''
    Write-Host '  ... press any key to continue' -ForegroundColor Yellow
    [void](Read-UiKey)
    Clear-Host
    $Global:UiFrameHeight = 0
}
