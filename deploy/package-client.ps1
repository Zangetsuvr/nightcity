# Puts the built multiplayer mod into a modpack folder, laid out like the game folder.
#
# After building the client on Windows (xmake build -y Client), run from the project folder:
#   powershell -ExecutionPolicy Bypass -File deploy\package-client.ps1
#
# Result: modpack\red4ext\plugins\CyberpunkMP\ with CyberpunkMP.dll and its assets.
# Add the other required mods (RED4ext, redscript, ArchiveXL, TweakXL, Codeware,
# Input Loader, ...) to the same modpack folder, then upload it to the server's
# data/modpack folder.

param(
    [string]$Out = "modpack",
    [string]$Mode = "release"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$dll = Join-Path $root "build\windows\x64\$Mode\CyberpunkMP.dll"
if (-not (Test-Path $dll)) {
    throw "CyberpunkMP.dll isn't built yet ($dll). Run:  xmake f -m $Mode -y  then  xmake build -y Client"
}

$dest = Join-Path $root "$Out\red4ext\plugins\CyberpunkMP"
if (Test-Path $dest) { Remove-Item -Recurse -Force $dest }
New-Item -ItemType Directory -Force $dest | Out-Null

Copy-Item $dll $dest

# Scripts, keeping their folders (World\..., Plugins\...).
$scripts = Join-Path $root "code\assets\redscript"
Get-ChildItem $scripts -Recurse -Filter *.reds | ForEach-Object {
    $rel = $_.FullName.Substring($scripts.Length).TrimStart('\')
    $target = Join-Path $dest "assets\redscript\$rel"
    New-Item -ItemType Directory -Force (Split-Path -Parent $target) | Out-Null
    Copy-Item $_.FullName $target
}

$archives = Join-Path $dest "assets\Archives"
New-Item -ItemType Directory -Force $archives | Out-Null
Copy-Item (Join-Path $root "code\assets\Archives\packed\archive\pc\mod\CyberpunkMP.archive") $archives

$inputs = Join-Path $dest "assets\Inputs"
New-Item -ItemType Directory -Force $inputs | Out-Null
Copy-Item (Join-Path $root "code\assets\Inputs\CyberpunkMP.xml") $inputs

$tweaks = Join-Path $dest "assets\Tweaks"
New-Item -ItemType Directory -Force $tweaks | Out-Null
Copy-Item (Join-Path $root "code\assets\Tweaks\CyberpunkMP.tweak") $tweaks

$count = (Get-ChildItem $dest -Recurse -File).Count
Write-Host "Done: $count files in $dest"
