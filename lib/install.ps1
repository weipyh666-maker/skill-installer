<#
.SYNOPSIS
    Install a Claude Code skill from GitHub or a local directory.

.DESCRIPTION
    Validates inputs, stages the source, verifies the skill contract, creates a
    junction/symlink, and optionally records an idempotent memory entry.
    Downloaded content is treated as untrusted. Smoke tests are opt-in.
#>

[CmdletBinding()]
param(
    [string]$Repo,
    [string]$Ref,
    [string]$LocalPath,
    [string]$Name,
    [switch]$LinkOnly,
    [switch]$Force,
    [switch]$DryRun,
    [switch]$RunSmokeTest,
    [switch]$SkipSmokeTest,
    [switch]$UpdateMemory,
    [switch]$SkipMemoryUpdate,
    [switch]$SkipCatalogUpdate,
    [string]$ExpectedSha256,
    [switch]$RequirePinnedRef
)

$ErrorActionPreference = 'Stop'
$IsWindowsHost = $env:OS -eq 'Windows_NT'
$TempRoot = $null
$Mode = $null
$InstallMode = 'not-run'
$SmokeResult = 'not-run'
$MemoryResult = 'not-run'
$CatalogResult = 'not-run'
$ResolvedCommit = ''
$DownloadedDigest = ''

function Fail([string]$Message) { throw $Message }

function Write-Step([int]$Number, [string]$Message) {
    Write-Host ''
    Write-Host "[$Number/7] $Message" -ForegroundColor Cyan
}

function Write-Ok([string]$Message) { Write-Host "  + $Message" -ForegroundColor Green }
function Write-Warn([string]$Message) { Write-Host "  ! $Message" -ForegroundColor Yellow }

function Get-FullPath([string]$Path) {
    if ($Path -eq '~') {
        $Path = $env:USERPROFILE
    } elseif ($Path.StartsWith('~\') -or $Path.StartsWith('~/')) {
        $Path = Join-Path $env:USERPROFILE $Path.Substring(2)
    }
    return [IO.Path]::GetFullPath($Path)
}

function Test-ExistingPath([string]$Path) {
    return $null -ne (Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue)
}

function Assert-ChildPath([string]$Base, [string]$Child, [string]$Label) {
    $baseFull = (Get-FullPath $Base).TrimEnd('\')
    $childFull = (Get-FullPath $Child).TrimEnd('\')
    $prefix = $baseFull + [IO.Path]::DirectorySeparatorChar
    if ($childFull -eq $baseFull -or -not $childFull.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
        Fail "$Label escapes its allowed directory: $childFull"
    }
}

function Assert-ValidName([string]$Value) {
    if ([string]::IsNullOrWhiteSpace($Value) -or $Value -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$') {
        Fail "Invalid skill name '$Value'. Use 1-64 letters, numbers, dots, hyphens, or underscores."
    }
}

function Assert-ValidRepo([string]$Value) {
    if ($Value -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,99}/[A-Za-z0-9][A-Za-z0-9._-]{0,99}$') {
        Fail "Invalid GitHub repository '$Value'. Expected owner/name."
    }
}

function Assert-ValidRef([string]$Value) {
    if ($Value -notmatch '^[A-Za-z0-9][A-Za-z0-9._/-]{0,127}$' -or $Value.Contains('..')) {
        Fail "Invalid Git ref '$Value'. Use a branch, tag, or commit SHA without spaces or traversal segments."
    }
}

function Assert-ValidHash([string]$Value) {
    if ($Value -and $Value -notmatch '^[A-Fa-f0-9]{64}$') {
        Fail 'ExpectedSha256 must be exactly 64 hexadecimal characters.'
    }
}

function Assert-NoSensitiveFiles([string]$Path) {
    $bad = @(Get-ChildItem -LiteralPath $Path -Recurse -Force -File -ErrorAction Stop |
        Where-Object {
            $_.Name -match '^\.env($|\.)' -or
            $_.Extension -in @('.key', '.pem', '.p12', '.pfx') -or
            $_.FullName -match '[\\/]secrets[\\/]' -or
            $_.FullName -match '[\\/]\.git[\\/]'
        } | Select-Object -First 5)
    if ($bad.Count -gt 0) {
        $names = ($bad | ForEach-Object { $_.FullName }) -join ', '
        Fail "Refusing to copy sensitive or repository-internal files: $names"
    }
}

function Assert-SkillLayout([string]$Path) {
    $skillFile = Join-Path $Path 'SKILL.md'
    if (-not (Test-Path -LiteralPath $skillFile -PathType Leaf)) {
        Fail "SKILL.md not found at $Path"
    }
    $content = Get-Content -Raw -LiteralPath $skillFile
    if ($content -notmatch '(?ms)^---\s*\r?\n.*?^name:\s*[a-z0-9][a-z0-9-]{0,63}\s*\r?\n.*?^description:\s*.+?\r?\n---') {
        Fail "SKILL.md at $Path has invalid or incomplete YAML frontmatter."
    }
}

function Copy-DirectoryContents([string]$Source, [string]$Destination) {
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    Get-ChildItem -LiteralPath $Source -Force | Copy-Item -Destination $Destination -Recurse -Force
}

function Remove-InstallEntry([string]$Path) {
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if ($null -eq $item) { return }
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
        Remove-Item -LiteralPath $Path -Force
    } else {
        Remove-Item -LiteralPath $Path -Recurse -Force
    }
}

function Backup-Existing([string]$Path, [string]$Label, [string]$BackupRoot, [string]$SkillName) {
    if (-not (Test-ExistingPath $Path)) { return '' }
    New-Item -ItemType Directory -Path $BackupRoot -Force | Out-Null
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $destination = Join-Path $BackupRoot "$SkillName-$stamp-$Label"
    Move-Item -LiteralPath $Path -Destination $destination
    return $destination
}

function Invoke-GhApiBinary([string]$ApiPath, [string]$OutputPath, [string]$ErrorPath) {
    $ghPath = (Get-Command gh -ErrorAction Stop).Source
    $process = Start-Process -FilePath $ghPath -ArgumentList @('api', $ApiPath) -RedirectStandardOutput $OutputPath -RedirectStandardError $ErrorPath -Wait -PassThru -NoNewWindow
    if ($process.ExitCode -ne 0) {
        $detail = if (Test-Path -LiteralPath $ErrorPath) { Get-Content -Raw -LiteralPath $ErrorPath } else { '' }
        Fail "gh api download failed. $detail"
    }
}

function Create-InstallLink([string]$Source, [string]$Link) {
    try {
        if ($IsWindowsHost) {
            New-Item -ItemType Junction -Path $Link -Target $Source -ErrorAction Stop | Out-Null
            return 'junction'
        }
        New-Item -ItemType SymbolicLink -Path $Link -Target $Source -ErrorAction Stop | Out-Null
        return 'symlink'
    } catch {
        Copy-DirectoryContents $Source $Link
        return 'copy-fallback'
    }
}

function Invoke-SmokeTest([string]$Source, [string]$SkillName) {
    Write-Warn 'Smoke test executes downloaded code. Only use it for a reviewed, trusted source.'
    $candidates = @("$SkillName.cmd", "$SkillName.ps1", "$SkillName.sh", $SkillName)
    foreach ($candidate in $candidates) {
        $path = Join-Path $Source $candidate
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            try {
                $out = & $path --version 2>$null
                if ($LASTEXITCODE -eq 0) { return "pass: $out" }
                $out = & $path --help 2>$null
                if ($LASTEXITCODE -eq 0) { return 'pass (--help)' }
            } catch { }
        }
    }
    $binDir = Join-Path $Source 'bin'
    if (Test-Path -LiteralPath $binDir -PathType Container) {
        foreach ($file in Get-ChildItem -LiteralPath $binDir -File) {
            try {
                $out = & $file.FullName --version 2>$null
                if ($LASTEXITCODE -eq 0) { return "pass: $out" }
            } catch { }
        }
    }
    return 'no executable found (manual test needed)'
}

function Update-MemoryRecord([string]$Path, [string]$SkillName, [string]$RepoName, [string]$Source, [string]$Link, [string]$Smoke) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return 'memory file not found (skip)'
    }
    $escaped = [regex]::Escape($SkillName)
    $existing = Get-Content -LiteralPath $Path
    if ($existing -match "^\|\s*$escaped\s*\|") { return 'already present' }
    $row = "| $SkillName | $RepoName | $Source | → $Link | $Smoke | $(Get-Date -Format 'yyyy-MM-dd') |"
    $utf8 = [Text.UTF8Encoding]::new($false)
    [IO.File]::AppendAllText($Path, $row + [Environment]::NewLine, $utf8)
    return "appended to $Path"
}

function Refresh-CatalogIndex([string]$SkillName, [string]$RepoName, [string]$Commit, [string]$Digest) {
    $catalogScript = Join-Path $PSScriptRoot 'catalog.ps1'
    if (-not (Test-Path -LiteralPath $catalogScript -PathType Leaf)) { return 'catalog script not found (skip)' }
    $hostCommand = @(Get-Command pwsh, powershell.exe -ErrorAction SilentlyContinue | Select-Object -First 1)[0]
    if ($null -eq $hostCommand) { return 'PowerShell host not found (skip)' }
    $sourceDescriptor = if ($RepoName) { "github:$RepoName" } else { 'local' }
    $arguments = @('-NoProfile', '-File', $catalogScript, '-Command', 'refresh', '-RegisterName', $SkillName, '-RegisterSource', $sourceDescriptor, '-RegisterInstalledAt', [DateTime]::UtcNow.ToString('o'))
    if ($Commit) { $arguments += @('-RegisterCommit', $Commit) }
    if ($Digest) { $arguments += @('-RegisterSha256', $Digest) }
    & $hostCommand.Source @arguments *> $null
    if ($LASTEXITCODE -ne 0) { return 'catalog refresh failed' }
    return 'refreshed'
}

try {
    if ($Repo -and $LocalPath) { Fail 'Use either -Repo or -LocalPath, not both.' }
    if ($Ref -and -not $Repo) { Fail '-Ref can only be used with -Repo.' }
    if ($ExpectedSha256 -and -not $Repo) { Fail '-ExpectedSha256 can only be used with -Repo.' }
    if ($RequirePinnedRef -and -not $Repo) { Fail '-RequirePinnedRef can only be used with -Repo.' }
    if ($RunSmokeTest -and $SkipSmokeTest) { Fail 'Use either -RunSmokeTest or -SkipSmokeTest, not both.' }
    if ($UpdateMemory -and $SkipMemoryUpdate) { Fail 'Use either -UpdateMemory or -SkipMemoryUpdate, not both.' }
    if ($RequirePinnedRef -and -not $Ref) { Fail 'RequirePinnedRef needs an explicit -Ref tag or commit SHA.' }
    if (-not $Repo -and -not $LocalPath -and -not $LinkOnly) { Fail 'Provide -Repo, -LocalPath, or -LinkOnly with -Name.' }

    $Mode = if ($LinkOnly) { 'LinkOnly' } elseif ($Repo) { 'GitHub' } else { 'Local' }
    if ($Repo) { Assert-ValidRepo $Repo }
    if ($Ref) { Assert-ValidRef $Ref }
    Assert-ValidHash $ExpectedSha256

    if (-not $Name) {
        if ($Repo) { $Name = ($Repo -split '/')[-1] }
        elseif ($LocalPath) { $Name = Split-Path -Leaf ((Resolve-Path -LiteralPath $LocalPath).Path) }
    }
    Assert-ValidName $Name

    $SkillsDir = if ($env:CLAUDE_SKILLS_DIR) { $env:CLAUDE_SKILLS_DIR } else { Join-Path $env:USERPROFILE 'Claude-Code' }
    $LinkBase = if ($env:CLAUDE_SKILLS_LINK_DIR) { $env:CLAUDE_SKILLS_LINK_DIR } else { Join-Path $env:USERPROFILE '.claude\skills' }
    $SourcePath = Join-Path $SkillsDir $Name
    $LinkPath = Join-Path $LinkBase $Name
    Assert-ChildPath $SkillsDir $SourcePath 'Source path'
    Assert-ChildPath $LinkBase $LinkPath 'Link path'

    Write-Step 1 'Pre-flight and input validation'
    if ($Mode -eq 'GitHub' -and -not $DryRun) {
        if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { Fail 'gh CLI not found. Install it, then run gh auth login.' }
        & gh auth status *> $null
        if ($LASTEXITCODE -ne 0) { Fail 'gh is not authenticated. Run gh auth login.' }
        Write-Ok 'gh authenticated'
    } else {
        Write-Ok "mode = $Mode; no GitHub authentication required"
    }
    Write-Ok "skill name = $Name"

    if ($Mode -eq 'Local') {
        $localResolved = (Resolve-Path -LiteralPath $LocalPath -ErrorAction Stop).Path
        if (-not (Test-Path -LiteralPath $localResolved -PathType Container)) { Fail "LocalPath is not a directory: $LocalPath" }
        $sourceFull = Get-FullPath $SourcePath
        $localFull = Get-FullPath $localResolved
        if ($localFull -eq $sourceFull -or $localFull.StartsWith($sourceFull + '\', [StringComparison]::OrdinalIgnoreCase) -or $sourceFull.StartsWith($localFull + '\', [StringComparison]::OrdinalIgnoreCase)) {
            Fail 'LocalPath cannot be the install target or contain the install target.'
        }
        Assert-NoSensitiveFiles $localResolved
        Assert-SkillLayout $localResolved
    }

    if ($Mode -eq 'LinkOnly') {
        if (-not (Test-ExistingPath $SourcePath)) { Fail "Source is missing for LinkOnly: $SourcePath" }
        Assert-SkillLayout $SourcePath
    }

    if (-not $DryRun -and -not (Test-Path -LiteralPath $SkillsDir -PathType Container)) {
        New-Item -ItemType Directory -Path $SkillsDir -Force | Out-Null
    }

    $sourceExists = Test-ExistingPath $SourcePath
    $linkExists = Test-ExistingPath $LinkPath
    if ($DryRun) {
        Write-Step 2 'Dry-run plan'
        if (($sourceExists -or $linkExists) -and -not $Force) { Write-Warn 'Existing install detected; a real replacement would require -Force.' }
        Write-Ok "source = $SourcePath"
        Write-Ok "link = $LinkPath"
        Write-Ok 'DRY RUN: no files, links, network requests, smoke tests, or memory records changed'
        return
    }

    if (($sourceExists -or $linkExists) -and -not $Force) { Fail "Install target already exists. Use -Force to replace it safely: $Name" }
    if ($LinkOnly -and $linkExists -and -not $Force) { Fail "Link already exists. Use -Force to recreate it: $LinkPath" }

    if (-not $LinkOnly) {
        Write-Step 2 'Prepare source'
        $TempRoot = Join-Path $env:TEMP "skill-installer-$([guid]::NewGuid().ToString('N'))"
        New-Item -ItemType Directory -Path $TempRoot -Force | Out-Null
        $stagePath = Join-Path $TempRoot 'stage'

        if ($Mode -eq 'Local') {
            Copy-DirectoryContents $LocalPath $stagePath
            Write-Ok "staged local source: $LocalPath"
        } else {
            $tarball = Join-Path $TempRoot 'source.tar.gz'
            $stderr = Join-Path $TempRoot 'gh-error.txt'
            $apiPath = "repos/$Repo/tarball"
            if ($Ref) { $apiPath += "/$Ref" }
            Invoke-GhApiBinary $apiPath $tarball $stderr
            $actualHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $tarball).Hash
            $DownloadedDigest = $actualHash
            if ($ExpectedSha256 -and $actualHash -ne $ExpectedSha256.ToUpperInvariant()) {
                Fail "Tarball SHA256 mismatch. Expected $ExpectedSha256, got $actualHash"
            }
            $commitRef = if ($Ref) { $Ref } else { 'HEAD' }
            $ResolvedCommit = (& gh api "repos/$Repo/commits/$commitRef" --jq '.sha' 2>$null | Out-String).Trim()
            if ($LASTEXITCODE -ne 0 -or $ResolvedCommit -notmatch '^[A-Fa-f0-9]{40}$') {
                Fail 'Could not resolve the downloaded ref to a commit SHA.'
            }
            $extractDir = Join-Path $TempRoot 'extract'
            New-Item -ItemType Directory -Path $extractDir -Force | Out-Null
            & tar -xzf $tarball -C $extractDir 2>$null
            if ($LASTEXITCODE -ne 0) { Fail 'tar extraction failed.' }
            $inners = @(Get-ChildItem -LiteralPath $extractDir -Directory)
            if ($inners.Count -ne 1) { Fail 'Unexpected GitHub tarball layout.' }
            Copy-DirectoryContents $inners[0].FullName $stagePath
            Write-Ok "downloaded $Repo at commit $ResolvedCommit"
            Write-Ok "tarball SHA256 = $actualHash"
        }

        Assert-NoSensitiveFiles $stagePath
        Assert-SkillLayout $stagePath
        if ($sourceExists) {
            $backupRoot = Join-Path $SkillsDir '.backups'
            $backup = Backup-Existing $SourcePath 'source' $backupRoot $Name
            Write-Ok "previous source backed up to $backup"
        }
        Move-Item -LiteralPath $stagePath -Destination $SourcePath
        Write-Ok "source installed at $SourcePath"
    } else {
        Write-Step 2 'Use existing source'
    }

    Write-Step 3 'Create link'
    if ($linkExists) { Remove-InstallEntry $LinkPath }
    $InstallMode = Create-InstallLink $SourcePath $LinkPath
    Write-Ok "$($InstallMode): $SourcePath -> $LinkPath"

    Write-Step 4 'Verify skill contract'
    Assert-SkillLayout $SourcePath
    if (-not (Test-ExistingPath $LinkPath)) { Fail "Link missing after installation: $LinkPath" }
    $sourceHash = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $SourcePath 'SKILL.md')).Hash
    $linkHash = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $LinkPath 'SKILL.md')).Hash
    if ($sourceHash -ne $linkHash) { Fail 'Source and link SKILL.md hashes differ.' }
    Write-Ok "source and link verified; SKILL.md SHA256 = $sourceHash"

    Write-Step 5 'Smoke test'
    if ($RunSmokeTest -and -not $SkipSmokeTest -and -not $env:SKIP_SMOKE_TEST) {
        $SmokeResult = Invoke-SmokeTest $SourcePath $Name
    } elseif ($SkipSmokeTest -or $env:SKIP_SMOKE_TEST) {
        $SmokeResult = 'skipped by request'
    } else {
        $SmokeResult = 'not run (opt-in with -RunSmokeTest)'
    }
    Write-Ok $SmokeResult

    Write-Step 6 'Memory update'
    if ($UpdateMemory -and -not $SkipMemoryUpdate -and -not $env:SKIP_MEMORY_UPDATE) {
        $memFile = Join-Path $SkillsDir 'installed-tools-summary.md'
        $MemoryResult = Update-MemoryRecord $memFile $Name $Repo $SourcePath $LinkPath $SmokeResult
    } else {
        $MemoryResult = 'not run (opt-in with -UpdateMemory)'
    }
    Write-Ok $MemoryResult

    Write-Step 7 'Catalog index and final result'
    if ($SkipCatalogUpdate -or $env:SKIP_CATALOG_UPDATE) {
        $CatalogResult = 'not run (opt-out)'
    } else {
        $CatalogResult = Refresh-CatalogIndex $Name $Repo $ResolvedCommit $DownloadedDigest
    }
    Write-Ok $CatalogResult
    Write-Host ''
    Write-Host '| Field | Value |'
    Write-Host '|-------|-------|'
    Write-Host "| Mode | $Mode |"
    Write-Host "| Source | $SourcePath |"
    Write-Host "| Link | $LinkPath |"
    Write-Host "| Install mode | $InstallMode |"
    Write-Host "| Resolved commit | $ResolvedCommit |"
    Write-Host "| Smoke test | $SmokeResult |"
    Write-Host "| Memory update | $MemoryResult |"
    Write-Host "| Catalog index | $CatalogResult |"
    Write-Host "| Timestamp | $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') |"
    Write-Host ''
    Write-Host 'Restart Claude Code so the new skill appears in the system prompt.' -ForegroundColor Yellow
} catch {
    Write-Host ''
    Write-Host "INSTALL FAILED: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
} finally {
    if ($TempRoot -and (Test-Path -LiteralPath $TempRoot)) {
        Remove-Item -LiteralPath $TempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
