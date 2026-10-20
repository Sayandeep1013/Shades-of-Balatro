<#
.SYNOPSIS
    Shades of Balatro: installs, checks and switches a pinned Balatro modpack
    (Lovely + Steamodded + Multiplayer + content mods) on Windows.

.DESCRIPTION
    Finds your own Steam copy of Balatro, installs Lovely next to it, downloads every mod from
    its official release at a pinned version (SHA-256 checked), and applies a preset that turns
    mods on or off. Nothing from Balatro itself is downloaded or shared.

    One-liner (PowerShell):
        irm https://raw.githubusercontent.com/Sayandeep1013/Shades-of-Balatro/main/shades.ps1 | iex

.EXAMPLE
    .\shades.ps1                      # interactive menu
    .\shades.ps1 install              # install / repair with the default preset
    .\shades.ps1 install -Preset pokermon
    .\shades.ps1 check                # report what is installed vs. the modpack
    .\shades.ps1 preset stacking      # switch which mods are on
    .\shades.ps1 presets              # list presets
    .\shades.ps1 uninstall            # remove Lovely + managed mods (backed up first)
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('menu', 'install', 'check', 'preset', 'presets', 'uninstall', 'help')]
    [string]$Command = 'menu',
    [Parameter(Position = 1)]
    [string]$Name,
    [string]$Preset,
    [string]$GameDir,
    [string]$ModsDir = (Join-Path $env:APPDATA 'Balatro\Mods'),
    [string]$Source,
    [string]$Ref = 'main',
    [switch]$NoShortcuts,
    [switch]$Yes
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Repo = 'Sayandeep1013/Shades-of-Balatro'
$Home_ = Join-Path $env:LOCALAPPDATA 'ShadesOfBalatro'
$Cache = Join-Path $Home_ 'cache'
$StateFile = Join-Path $Home_ 'state.json'
$Stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$BackupRoot = Join-Path (Split-Path $ModsDir -Parent) "ShadesBackups\$Stamp"

# ---------------------------------------------------------------- output

function Say([string]$text, [string]$color = 'Gray') { Write-Host $text -ForegroundColor $color }
function Step([string]$text) { Write-Host ''; Write-Host "== $text" -ForegroundColor Cyan }
function Ok([string]$text) { Write-Host "  [ok]   $text" -ForegroundColor Green }
function Warn([string]$text) { Write-Host "  [warn] $text" -ForegroundColor Yellow }
function Bad([string]$text) { Write-Host "  [fail] $text" -ForegroundColor Red }

function Confirm-Action([string]$question) {
    if ($Yes) { return $true }
    $answer = Read-Host "$question [Y/n]"
    return ($answer -eq '' -or $answer -match '^[Yy]')
}

# ---------------------------------------------------------------- state + manifest

function Read-State {
    if (Test-Path $StateFile) { return Get-Content $StateFile -Raw | ConvertFrom-Json }
    return $null
}

function Save-State($state) {
    New-Item -ItemType Directory -Force $Home_ | Out-Null
    $state | ConvertTo-Json -Depth 5 | Set-Content -Encoding UTF8 $StateFile
}

function Get-RawUrl([string]$path) { "https://raw.githubusercontent.com/$Repo/$Ref/$path" }

function Get-Manifest {
    if ($Source) { return Get-Content (Join-Path $Source 'modpack.json') -Raw | ConvertFrom-Json }
    $local = Join-Path $PSScriptRoot 'modpack.json'
    if ($PSScriptRoot -and (Test-Path $local)) { return Get-Content $local -Raw | ConvertFrom-Json }
    return Invoke-RestMethod (Get-RawUrl 'modpack.json')
}

# ---------------------------------------------------------------- finding Balatro

function Get-SteamLibraries {
    $roots = @()
    foreach ($key in 'HKCU:\Software\Valve\Steam', 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam', 'HKLM:\SOFTWARE\Valve\Steam') {
        $p = Get-ItemProperty $key -ErrorAction SilentlyContinue
        if ($p) {
            foreach ($v in $p.SteamPath, $p.InstallPath) { if ($v) { $roots += ($v -replace '/', '\') } }
        }
    }
    $libs = @()
    foreach ($root in ($roots | Select-Object -Unique)) {
        $libs += $root
        $vdf = Join-Path $root 'steamapps\libraryfolders.vdf'
        if (Test-Path $vdf) {
            foreach ($m in [regex]::Matches((Get-Content $vdf -Raw), '"path"\s+"([^"]+)"')) {
                $libs += ($m.Groups[1].Value -replace '\\\\', '\')
            }
        }
    }
    return $libs | Select-Object -Unique
}

function Find-Balatro {
    if ($GameDir) {
        if (Test-Path (Join-Path $GameDir 'Balatro.exe')) { return (Resolve-Path $GameDir).Path }
        throw "Balatro.exe not found in -GameDir '$GameDir'."
    }
    $state = Read-State
    if ($state -and $state.game_dir -and (Test-Path (Join-Path $state.game_dir 'Balatro.exe'))) { return $state.game_dir }
    foreach ($lib in Get-SteamLibraries) {
        $dir = Join-Path $lib 'steamapps\common\Balatro'
        if (Test-Path (Join-Path $dir 'Balatro.exe')) { return $dir }
    }
    Say ''
    Say 'Could not find Balatro automatically (looked in every Steam library).' Yellow
    $typed = Read-Host 'Paste the folder that contains Balatro.exe'
    $typed = $typed.Trim('" ')
    if ($typed -and (Test-Path (Join-Path $typed 'Balatro.exe'))) { return (Resolve-Path $typed).Path }
    throw 'Balatro.exe not found. Install Balatro from Steam first, or pass -GameDir.'
}

function Assert-GameClosed {
    $running = Get-Process -Name Balatro -ErrorAction SilentlyContinue
    if ($running) {
        if (Confirm-Action 'Balatro is running and has to close first. Close it now?') {
            $running | Stop-Process -Force
            Start-Sleep -Seconds 1
        } else { throw 'Close Balatro and run this again.' }
    }
}

# ---------------------------------------------------------------- downloads

function Get-Verified([string]$url, [string]$sha256, [string]$fileName) {
    New-Item -ItemType Directory -Force $Cache | Out-Null
    $file = Join-Path $Cache $fileName
    if ((Test-Path $file) -and ((Get-FileHash $file -Algorithm SHA256).Hash -eq $sha256.ToUpper())) { return $file }
    Say "         downloading $url"
    Invoke-WebRequest -Uri $url -OutFile $file -UseBasicParsing
    $actual = (Get-FileHash $file -Algorithm SHA256).Hash
    if ($actual -ne $sha256.ToUpper()) {
        Remove-Item $file -Force
        throw "Checksum mismatch for $fileName (expected $sha256, got $actual). The upstream file changed; not installing it."
    }
    return $file
}

function Expand-ToTemp([string]$zip) {
    $dir = Join-Path $env:TEMP ("shades-" + [guid]::NewGuid().ToString('N'))
    Expand-Archive -Path $zip -DestinationPath $dir -Force
    return $dir
}

$script:RepoTree = $null
function Get-RepoTree {
    # Our own mods (MobileMemFix, EquilibriumDeck) come from this repository.
    if ($Source) { return $Source }
    if ($PSScriptRoot -and (Test-Path (Join-Path $PSScriptRoot 'mods'))) { return $PSScriptRoot }
    if (-not $script:RepoTree) {
        New-Item -ItemType Directory -Force $Cache | Out-Null
        $zip = Join-Path $Cache "repo-$Ref.zip"
        Invoke-WebRequest -Uri "https://github.com/$Repo/archive/$Ref.zip" -OutFile $zip -UseBasicParsing
        $tmp = Expand-ToTemp $zip
        $script:RepoTree = (Get-ChildItem $tmp -Directory | Select-Object -First 1).FullName
    }
    return $script:RepoTree
}

# ---------------------------------------------------------------- Lovely

function Get-LovelyState([string]$game, $lovely) {
    $dll = Join-Path $game $lovely.dll
    $winmm = Join-Path $game 'winmm.dll'
    $result = [ordered]@{ installed = $false; matches = $false; other = $null; conflict = $null }
    if (Test-Path $dll) {
        $result.installed = $true
        $result.matches = ((Get-FileHash $dll -Algorithm SHA256).Hash -eq $lovely.dll_sha256.ToUpper())
    }
    if ((Test-Path $winmm) -and (Select-String -Path $winmm -Pattern 'lovely' -SimpleMatch -Quiet)) {
        $result.conflict = $winmm
    }
    return $result
}

function Install-Lovely([string]$game, $lovely) {
    $state = Get-LovelyState $game $lovely
    if ($state.conflict) {
        $moved = "$($state.conflict).disabled-$Stamp"
        Move-Item $state.conflict $moved
        Warn "A second Lovely (winmm.dll, 0.10+) was next to the game; renamed it to $(Split-Path $moved -Leaf) so the two don't clash."
    }
    if ($state.matches) { Ok "Lovely $($lovely.version) already installed"; return }
    $zip = Get-Verified $lovely.url $lovely.sha256 "lovely-$($lovely.version).zip"
    $tmp = Expand-ToTemp $zip
    $target = Join-Path $game $lovely.dll
    if (Test-Path $target) {
        Move-Item $target "$target.bak-$Stamp"
        Warn "Replaced an older $($lovely.dll) (kept as $($lovely.dll).bak-$Stamp)"
    }
    Copy-Item (Join-Path $tmp $lovely.dll) $target
    Remove-Item $tmp -Recurse -Force
    Ok "Lovely $($lovely.version) installed into $game"
}

# ---------------------------------------------------------------- mods

function Get-InstalledVersion([string]$folder, $mod) {
    if (-not (Test-Path $folder)) { return $null }
    if ($mod.id -eq 'smods') {
        $v = Join-Path $folder 'version.lua'
        if (Test-Path $v) { if ((Get-Content $v -Raw) -match 'return\s+"([^"]+)"') { return ($Matches[1] -replace '-STEAMODDED$', '') } }
        return 'unknown'
    }
    $json = Get-ChildItem $folder -Filter '*.json' -File | Where-Object { $_.Name -notin 'manifest.json' }
    foreach ($j in $json) {
        try {
            $meta = Get-Content $j.FullName -Raw | ConvertFrom-Json
            if ($meta.id -and $meta.version) { return [string]$meta.version }
        } catch { }
    }
    return 'unknown'
}

function Test-ModCurrent([string]$installed, $mod) {
    if (-not $installed) { return $false }
    return ($installed -eq $mod.version -or $installed.StartsWith("$($mod.version)-"))
}

function Install-Mod($mod) {
    $target = Join-Path $ModsDir $mod.folder
    $installed = Get-InstalledVersion $target $mod
    if (Test-ModCurrent $installed $mod) { Ok "$($mod.name) $($mod.version) already installed"; return }

    if ($mod.local) {
        $from = Join-Path (Get-RepoTree) $mod.local
        $tmp = $null
    } else {
        $zip = Get-Verified $mod.url $mod.sha256 "$($mod.id)-$($mod.version).zip"
        $tmp = Expand-ToTemp $zip
        $marker = Get-ChildItem $tmp -Recurse -File -Filter $mod.marker |
            Sort-Object { $_.FullName.Split('\').Count } | Select-Object -First 1
        if (-not $marker) { throw "Could not find $($mod.marker) inside the $($mod.name) download." }
        $from = $marker.DirectoryName
    }

    $wasDisabled = Test-Path (Join-Path $target '.lovelyignore')
    if (Test-Path $target) {
        New-Item -ItemType Directory -Force $BackupRoot | Out-Null
        Move-Item $target (Join-Path $BackupRoot $mod.folder)
    }
    New-Item -ItemType Directory -Force $target | Out-Null
    Copy-Item (Join-Path $from '*') $target -Recurse -Force
    Get-ChildItem $from -Force -Filter '.*' -File | Copy-Item -Destination $target -Force
    if ($wasDisabled) { New-Item -ItemType File -Force (Join-Path $target '.lovelyignore') | Out-Null }
    if ($tmp) { Remove-Item $tmp -Recurse -Force }

    if ($installed) { Ok "$($mod.name) updated $installed -> $($mod.version)" }
    else { Ok "$($mod.name) $($mod.version) installed" }
}

function Set-Preset($manifest, [string]$presetName) {
    $p = $manifest.presets.$presetName
    if (-not $p) { throw "Unknown preset '$presetName'. Run: shades presets" }
    foreach ($mod in $manifest.mods) {
        $dir = Join-Path $ModsDir $mod.folder
        if (-not (Test-Path $dir)) { continue }
        $ignore = Join-Path $dir '.lovelyignore'
        $on = ($p.enabled -contains $mod.id) -or $mod.required
        if ($on -and (Test-Path $ignore)) { Remove-Item $ignore -Force }
        if (-not $on -and -not (Test-Path $ignore)) { New-Item -ItemType File -Force $ignore | Out-Null }
    }
    Ok "Preset '$presetName' applied: $($p.label)"
}

# ---------------------------------------------------------------- shortcuts

function New-Shortcut([string]$path, [string]$target, [string]$arguments, [string]$workDir, [string]$icon, [string]$description) {
    $ws = New-Object -ComObject WScript.Shell
    $s = $ws.CreateShortcut($path)
    $s.TargetPath = $target
    if ($arguments) { $s.Arguments = $arguments }
    $s.WorkingDirectory = $workDir
    $s.IconLocation = $icon
    $s.Description = $description
    $s.Save()
}

function Install-Shortcuts([string]$game) {
    $exe = Join-Path $game 'Balatro.exe'
    $startMenu = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'
    $desktop = [Environment]::GetFolderPath('Desktop')

    # Keep a copy of this tool so presets can be switched later from the Start menu.
    New-Item -ItemType Directory -Force $Home_ | Out-Null
    $self = Join-Path $Home_ 'shades.ps1'
    if ($PSCommandPath -and (Test-Path $PSCommandPath)) { Copy-Item $PSCommandPath $self -Force }
    else { Invoke-WebRequest -Uri (Get-RawUrl 'shades.ps1') -OutFile $self -UseBasicParsing }
    $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'

    foreach ($dir in $startMenu, $desktop) {
        New-Shortcut (Join-Path $dir 'Balatro.lnk') $exe '' $game "$exe,0" 'Balatro with the Shades of Balatro modpack'
        New-Shortcut (Join-Path $dir 'Balatro (Vanilla).lnk') $exe '--vanilla' $game "$exe,0" 'Balatro with every mod turned off'
    }
    New-Shortcut (Join-Path $startMenu 'Shades of Balatro.lnk') $ps "-NoProfile -ExecutionPolicy Bypass -File `"$self`"" $Home_ "$exe,0" 'Check the modpack or switch presets'
    Ok 'Shortcuts: Balatro, Balatro (Vanilla) on Desktop + Start menu; "Shades of Balatro" in Start menu'
}

# ---------------------------------------------------------------- commands

function Invoke-Install([string]$presetName) {
    $manifest = Get-Manifest
    if (-not $presetName) {
        $state = Read-State
        $presetName = if ($state -and $state.preset) { $state.preset } else { $manifest.default_preset }
    }
    Say ''
    Say "Shades of Balatro $($manifest.modpack_version)  -  preset: $presetName" White

    Step 'Finding Balatro'
    $game = Find-Balatro
    Ok "Balatro found: $game"
    Assert-GameClosed

    Step 'Lovely (mod loader)'
    Install-Lovely $game $manifest.lovely

    Step "Mods -> $ModsDir"
    New-Item -ItemType Directory -Force $ModsDir | Out-Null
    foreach ($mod in $manifest.mods) { Install-Mod $mod }
    if (Test-Path $BackupRoot) { Warn "Older copies were moved to $BackupRoot" }

    Step 'Preset'
    Set-Preset $manifest $presetName

    if (-not $NoShortcuts) { Step 'Shortcuts'; Install-Shortcuts $game }

    Save-State ([ordered]@{ game_dir = $game; mods_dir = $ModsDir; preset = $presetName; modpack_version = $manifest.modpack_version; installed = (Get-Date -Format s) })
    Say ''
    Say 'Done. Start "Balatro" from the Desktop or Start menu.' Green
    Say 'First launch takes a little longer while Steamodded builds its cache.' Gray
}

function Invoke-Check {
    $manifest = Get-Manifest
    $problems = 0
    Step 'Balatro'
    try { $game = Find-Balatro; Ok $game } catch { Bad $_.Exception.Message; return 1 }

    Step 'Lovely'
    $ls = Get-LovelyState $game $manifest.lovely
    if ($ls.matches) { Ok "Lovely $($manifest.lovely.version)" }
    elseif ($ls.installed) { Warn "A different Lovely build is installed (not $($manifest.lovely.version))"; $problems++ }
    else { Bad 'Lovely is not installed'; $problems++ }
    if ($ls.conflict) { Bad "Second Lovely found ($($ls.conflict)); the game will refuse to start"; $problems++ }

    Step "Mods ($ModsDir)"
    $state = Read-State
    $presetName = if ($state -and $state.preset) { $state.preset } else { $manifest.default_preset }
    $enabledByPreset = $manifest.presets.$presetName.enabled
    foreach ($mod in $manifest.mods) {
        $dir = Join-Path $ModsDir $mod.folder
        $v = Get-InstalledVersion $dir $mod
        $on = -not (Test-Path (Join-Path $dir '.lovelyignore'))
        $flag = if ($on) { 'on ' } else { 'off' }
        $want = ($enabledByPreset -contains $mod.id) -or $mod.required
        if ($v -and $on -ne $want) { $flag = "$flag, preset says $(if ($want) { 'on' } else { 'off' })" }
        if (-not $v) { Bad ("{0,-22} missing" -f $mod.name); $problems++ }
        elseif (-not (Test-ModCurrent $v $mod)) { Warn ("{0,-22} {1} (modpack wants {2})  [{3}]" -f $mod.name, $v, $mod.version, $flag); $problems++ }
        else { Ok ("{0,-22} {1}  [{2}]" -f $mod.name, $v, $flag) }
    }
    $managed = $manifest.mods | ForEach-Object { $_.folder }
    $extra = Get-ChildItem $ModsDir -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -ne 'lovely' -and $managed -notcontains $_.Name -and -not (Test-Path (Join-Path $_.FullName '.lovelyignore')) }
    foreach ($e in $extra) { Warn "Extra mod not in the modpack (on): $($e.Name). Fine for single player; your opponent needs it too in Multiplayer." }

    Say ''
    Say "Preset: $presetName  ($($manifest.presets.$presetName.label))" White
    if ($problems -eq 0) { Say 'Everything matches the modpack.' Green; return 0 }
    Say "$problems problem(s). Run: shades install   (it repairs only what is wrong)" Yellow
    return 1
}

function Invoke-Presets {
    $manifest = Get-Manifest
    $state = Read-State
    $current = if ($state) { $state.preset } else { $null }
    Step 'Presets'
    foreach ($prop in $manifest.presets.PSObject.Properties) {
        $mark = if ($prop.Name -eq $current) { '*' } else { ' ' }
        Say (" {0} {1,-12} {2}" -f $mark, $prop.Name, $prop.Value.label) White
        Say ("                 {0}" -f $prop.Value.description)
    }
}

function Invoke-Preset([string]$presetName) {
    if (-not $presetName) { Invoke-Presets; $presetName = Read-Host 'Preset to switch to' }
    $manifest = Get-Manifest
    Assert-GameClosed
    Set-Preset $manifest $presetName
    $state = Read-State
    if (-not $state) { $state = [pscustomobject]@{ preset = $presetName } }
    $state | Add-Member -NotePropertyName preset -NotePropertyValue $presetName -Force
    Save-State $state
    Say 'Both players need the same preset for Multiplayer.' Gray
}

function Invoke-Uninstall {
    $manifest = Get-Manifest
    $game = Find-Balatro
    if (-not (Confirm-Action "Remove Lovely and the modpack's mods? (moved to $BackupRoot, not deleted)")) { return }
    Assert-GameClosed
    New-Item -ItemType Directory -Force $BackupRoot | Out-Null
    foreach ($mod in $manifest.mods) {
        $dir = Join-Path $ModsDir $mod.folder
        if (Test-Path $dir) { Move-Item $dir (Join-Path $BackupRoot $mod.folder); Ok "removed $($mod.name)" }
    }
    $dll = Join-Path $game $manifest.lovely.dll
    if ((Get-LovelyState $game $manifest.lovely).matches) { Move-Item $dll (Join-Path $BackupRoot $manifest.lovely.dll); Ok 'removed Lovely' }
    foreach ($lnk in (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Shades of Balatro.lnk')) { if (Test-Path $lnk) { Remove-Item $lnk } }
    Say "Balatro is vanilla again. Backups: $BackupRoot" Green
}

function Show-Menu {
    while ($true) {
        Say ''
        Say '  SHADES OF BALATRO' Magenta
        Say '  1) Install / repair everything'
        Say '  2) Check my setup'
        Say '  3) Switch preset (which mods are on)'
        Say '  4) Uninstall'
        Say '  5) Quit'
        switch (Read-Host '  Choose') {
            '1' { Invoke-Install $Preset }
            '2' { [void](Invoke-Check) }
            '3' { Invoke-Preset $null }
            '4' { Invoke-Uninstall }
            default { return }
        }
    }
}

# Under `irm ... | iex` there is no script file, and `exit` would close the user's window.
function Exit-With([int]$code) { if ($PSCommandPath) { exit $code } }

try {
    switch ($Command) {
        'install' { Invoke-Install $(if ($Preset) { $Preset } else { $Name }) }
        'check' { Exit-With (Invoke-Check) }
        'preset' { Invoke-Preset $Name }
        'presets' { Invoke-Presets }
        'uninstall' { Invoke-Uninstall }
        'help' { Get-Help $PSCommandPath -Detailed }
        default { Show-Menu }
    }
} catch {
    Bad $_.Exception.Message
    Exit-With 1
}
