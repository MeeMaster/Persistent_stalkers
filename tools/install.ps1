# Installs (or refreshes) Persistent Stalkers into Mod Organizer as a real folder of
# hardlinks to the files in this repo, creates the target profile from the
# G.A.M.M.A one if it does not exist yet, and enables the mod in it.
#
#   powershell -ExecutionPolicy Bypass -File D:\Code\Persistent_stalkers\tools\install.ps1
#   ... -GammaDir E:\GAMMA -ProfileName GEM -SourceProfile G.A.M.M.A
#   ... -WhatIf    lists what it would do
#
# Run it after edits: editors often replace a file instead of writing into
# it, which breaks its hardlink, and the game then keeps reading the old copy
# (strings, UI layouts, ltx). Not a junction: the game's file hook does not
# follow them. Files only in the install (not in the repo) are left alone.
# Close Mod Organizer first: it rewrites modlist.txt when it exits.

param(
	[string]$GammaDir = 'D:\GAMMA',
	[string]$ProfileName = 'GEM',
	[string]$SourceProfile = 'G.A.M.M.A',
	[string]$ModName = 'Persistent_stalkers',
	[switch]$WhatIf
)

$ErrorActionPreference = 'Stop'

$src = Split-Path $PSScriptRoot -Parent
$modsDir = Join-Path $GammaDir 'mods'
$profilesDir = Join-Path $GammaDir 'profiles'
$dstMod = Join-Path $modsDir $ModName
$dstProfile = Join-Path $profilesDir $ProfileName
$srcProfile = Join-Path $profilesDir $SourceProfile

if (-not (Test-Path (Join-Path $GammaDir 'ModOrganizer.exe'))) {
	throw "no ModOrganizer.exe in $GammaDir"
}
if (-not (Test-Path (Join-Path $src 'gamedata'))) {
	throw "no gamedata folder in $src"
}

# 1. Mod folder: hardlinks to the repo files (a copy if the drives differ).

$files = @(Get-ChildItem -Path (Join-Path $src 'gamedata') -Recurse -File)
$meta = Join-Path $src 'meta.ini'
if (Test-Path $meta) { $files += Get-Item $meta }
$linked = 0
$copied = 0
foreach ($f in $files) {
	$rel = $f.FullName.Substring($src.Length).TrimStart('\')
	$dst = Join-Path $dstMod $rel
	if ($WhatIf) {
		Write-Output "link $dst -> $($f.FullName)"
		continue
	}
	$dir = Split-Path $dst -Parent
	if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
	if (Test-Path $dst) { Remove-Item -Force $dst }
	try {
		New-Item -ItemType HardLink -Path $dst -Target $f.FullName | Out-Null
		$linked++
	} catch {
		Copy-Item -Path $f.FullName -Destination $dst
		$copied++
	}
}
if (-not $WhatIf) {
	Write-Output "${dstMod}: $linked files linked, $copied copied"
	if ($copied -gt 0) {
		Write-Warning 'copied files do not follow repo edits: run this script again after changing them'
	}
}

# 2. Profile: a copy of the source profile, made once.

if (Test-Path $dstProfile) {
	Write-Output "profile $ProfileName exists, not copied"
} else {
	if (-not (Test-Path $srcProfile)) {
		throw "no source profile $srcProfile"
	}
	if ($WhatIf) {
		Write-Output "copy profile $srcProfile -> $dstProfile"
	} else {
		Copy-Item -Path $srcProfile -Destination $dstProfile -Recurse
		Write-Output "profile $ProfileName created from $SourceProfile"
	}
}

# 3. Enable the mod in the profile. Smaller line numbers win in modlist.txt,
#    so a new entry goes right under the header comments.

$modlist = Join-Path $dstProfile 'modlist.txt'
if ($WhatIf -and -not (Test-Path $modlist)) {
	$modlist = Join-Path $srcProfile 'modlist.txt'
}
$lines = [System.Collections.Generic.List[string]]@([System.IO.File]::ReadAllLines($modlist))
$actions = @()

$index = -1
for ($i = 0; $i -lt $lines.Count; $i++) {
	if ($lines[$i] -eq "+$ModName" -or $lines[$i] -eq "-$ModName") { $index = $i; break }
}
if ($index -ge 0 -and $lines[$index] -eq "+$ModName") {
	Write-Output "$ModName already enabled in $ProfileName"
} elseif ($index -ge 0) {
	$lines[$index] = "+$ModName"
	$actions += "enabled $ModName (line $($index + 1))"
} else {
	$at = 0
	while ($at -lt $lines.Count -and $lines[$at].StartsWith('#')) { $at++ }
	$lines.Insert($at, "+$ModName")
	$actions += "added +$ModName at line $($at + 1)"
}
if ($actions.Count -eq 0) {
	return
}
$action = $actions -join '; '
if ($WhatIf) {
	Write-Output "$modlist`: $action"
	return
}
Copy-Item -Path $modlist -Destination "$modlist.bak" -Force
# Mod Organizer writes UTF-8 without a BOM, CRLF.
$text = ($lines -join "`r`n") + "`r`n"
[System.IO.File]::WriteAllText($modlist, $text, (New-Object System.Text.UTF8Encoding($false)))
Write-Output "$modlist`: $action (backup in modlist.txt.bak)"
