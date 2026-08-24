# adapters/deepseek-harness/paths.ps1 - DeepSeek Harness multi-root Skill discovery
#
# Mirrors the verified DSH semantics (Phase A analysis):
#   roots: project-dsh 100 / project-agents 200 / custom 300 / user-dsh 400 /
#          user-agents 500 / bundled 600; rank decides duplicates only within
#          one provider layer (rank asc -> root order -> name order, first wins).
#   user-dsh root skips the reserved `.system` namespace (not a system-skill root).

function Get-DshUserHome {
    if ($env:SKILL_MANAGER_DSH_USER_HOME) { return [IO.Path]::GetFullPath($env:SKILL_MANAGER_DSH_USER_HOME) }
    if ($env:USERPROFILE) { return [IO.Path]::GetFullPath($env:USERPROFILE) }
    return [IO.Path]::GetFullPath($HOME)
}

function Get-DshHome {
    if ($env:SKILL_MANAGER_DSH_HOME) { return [IO.Path]::GetFullPath($env:SKILL_MANAGER_DSH_HOME) }
    if ($env:DSH_HOME -and $env:DSH_HOME.Trim().Length -gt 0) { return [IO.Path]::GetFullPath($env:DSH_HOME) }
    return (Join-Path (Get-DshUserHome) '.dsh')
}

function Get-DshAgentsHome {
    if ($env:SKILL_MANAGER_DSH_AGENTS_HOME) { return [IO.Path]::GetFullPath($env:SKILL_MANAGER_DSH_AGENTS_HOME) }
    if ($env:DSH_AGENTS_HOME) { return [IO.Path]::GetFullPath($env:DSH_AGENTS_HOME) }
    return (Join-Path (Get-DshUserHome) '.agents')
}

function Get-DshBundledDir {
    if ($env:SKILL_MANAGER_DSH_BUNDLED_DIR) { return [IO.Path]::GetFullPath($env:SKILL_MANAGER_DSH_BUNDLED_DIR) }
    if ($env:DSH_BUNDLED_SKILL_DIR) { return [IO.Path]::GetFullPath($env:DSH_BUNDLED_SKILL_DIR) }
    return $null
}

function Get-DshCwd {
    if ($env:SKILL_MANAGER_DSH_CWD) { return [IO.Path]::GetFullPath($env:SKILL_MANAGER_DSH_CWD) }
    return (Get-Location).Path
}

function Get-DshUserSkillRoot { return (Join-Path (Get-DshHome) 'skills') }
function Get-DshSharedSkillRoot { return (Join-Path (Get-DshAgentsHome) 'skills') }
function Get-DshUserSystemRoot { return (Join-Path (Get-DshUserSkillRoot) '.system') }
function Get-DshSettingsPath { if ($env:SKILL_MANAGER_DSH_SETTINGS_PATH) { return [IO.Path]::GetFullPath($env:SKILL_MANAGER_DSH_SETTINGS_PATH) }; return (Join-Path (Get-DshHome) 'settings.yaml') }
function Get-DshIndexPath { if ($env:SKILL_MANAGER_DSH_INDEX_PATH) { return [IO.Path]::GetFullPath($env:SKILL_MANAGER_DSH_INDEX_PATH) }; return (Join-Path (Get-DshHome) 'skill-manager-catalog.json') }
function Get-DshBackupRoot { return (Join-Path (Get-DshHome) 'skill-manager\backups') }

function Resolve-DshPath([string]$Path) {
    if (Test-Path -LiteralPath $Path) { return (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) }
    $parent = Split-Path -Parent $Path
    $leaf = Split-Path -Leaf $Path
    if ($parent -and (Test-Path -LiteralPath $parent)) { return (Join-Path ((Resolve-Path -LiteralPath $parent -ErrorAction Stop).Path) $leaf).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) }
    return [IO.Path]::GetFullPath($Path).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
}

# platform_protected is a DSH-platform fact distinct from skill-manager's own
# write_policy: 'false' = DSH scans this as an unprotected user/project root;
# 'unknown' = DSH defines no protection/mutability API here (bundled, custom).
# protected (bool) stays false for every root because DSH defines no protected roots.
function New-DshRoot([string]$Path, [string]$Scope, [string]$Class, [bool]$Writable, [bool]$Protected, [string]$PlatformProtected, [string]$WritePolicy, [bool]$SystemReserved, [string]$Source, [int]$Rank) {
    return [pscustomobject]@{
        path = Resolve-DshPath $Path
        scope = $Scope
        class = $Class
        writable = $Writable
        protected = $Protected
        platform_protected = $PlatformProtected
        write_policy = $WritePolicy
        system_reserved = $SystemReserved
        source = $Source
        rank = $Rank
    }
}

# Nearest `.git` ancestor, else the working directory itself (DSH projectRoot rule).
function Get-DshProjectRoot([string]$WorkingDirectory) {
    $current = Get-Item -LiteralPath $WorkingDirectory -Force -ErrorAction Stop
    if (-not $current.PSIsContainer) { $current = $current.Directory }
    while ($null -ne $current) {
        if (Test-Path -LiteralPath (Join-Path $current.FullName '.git')) { return $current.FullName }
        $current = $current.Parent
    }
    return (Get-Item -LiteralPath $WorkingDirectory -Force -ErrorAction Stop).FullName
}

# DSH preset composition state: provider enablement + mounted skill consumer.
# Best-effort YAML-lite parsing of settings.yaml (`agent-presets.default`) and
# `<DSH_HOME>/.agent-presets/<name>/agent.cordis.yml`; evidence records what was read.
function Get-DshPresetState {
    $state = [pscustomobject]@{
        ActivePreset = $null
        SettingsPath = $null
        PresetPath = $null
        ProviderEnabled = $false
        Consumer = 'unknown'
        IncludeDefaultRoots = $true
        CustomDirs = @()
        Watch = $null
        Evidence = @()
    }
    $settings = Get-DshSettingsPath
    $state.SettingsPath = $settings
    if (Test-Path -LiteralPath $settings -PathType Leaf) {
        $state.Evidence += "settings:$settings"
        $raw = Get-Content -LiteralPath $settings -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
        $block = [regex]::Match($raw, '(?ms)^agent-presets:\s*\r?\n(.*?)(?=^[a-zA-Z0-9_.-]+:|\z)')
        if ($block.Success) {
            $def = [regex]::Match($block.Groups[1].Value, '(?mi)^\s*default:\s*"?([^"\s#]+)')
            if ($def.Success) { $state.ActivePreset = $def.Groups[1].Value.Trim() }
        }
    }
    if ($env:SKILL_MANAGER_DSH_PRESET) { $state.ActivePreset = $env:SKILL_MANAGER_DSH_PRESET }
    if (-not $state.ActivePreset) {
        $state.Evidence += 'no-active-preset'
        return $state
    }
    $presetFile = Join-Path (Join-Path (Get-DshHome) '.agent-presets') (Join-Path $state.ActivePreset 'agent.cordis.yml')
    $state.PresetPath = $presetFile
    if (-not (Test-Path -LiteralPath $presetFile -PathType Leaf)) {
        $state.Evidence += 'preset-file-missing'
        return $state
    }
    $state.Evidence += "preset:$presetFile"
    $raw = Get-Content -LiteralPath $presetFile -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
    $state.ProviderEnabled = ($raw -match '(?m)^\s*- id:\s*skill-filesystem\s*$') -or ($raw -match '@deepseek-ai/dsh-skill-filesystem')
    if (-not $state.ProviderEnabled -and ($raw -match '(?m)^\s*- id:\s*skill-filesystem\s*') ) { $state.ProviderEnabled = $true }
    if ($raw -match '(?m)^\s*- id:\s*tool-skill\s*$' -or $raw -match '@deepseek-ai/dsh-tool-skill') { $state.Consumer = 'tool-skill' }
    elseif ($raw -match '(?m)^\s*- id:\s*skill-search\s*$') { $state.Consumer = 'skill-search' }
    else { $state.Consumer = 'none' }
    $row = [regex]::Match($raw, '(?ms)^\s*- id:\s*skill-filesystem\s*(.*?)(?=^\s*- id:|\z)')
    if ($row.Success) {
        $cfg = $row.Groups[1].Value
        $idr = [regex]::Match($cfg, '(?mi)^\s*includeDefaultRoots:\s*(true|false)')
        if ($idr.Success) { $state.IncludeDefaultRoots = ($idr.Groups[1].Value.ToLowerInvariant() -eq 'true') }
        $watch = [regex]::Match($cfg, '(?mi)^\s*watch:\s*(true|false)')
        if ($watch.Success) { $state.Watch = ($watch.Groups[1].Value.ToLowerInvariant() -eq 'true') }
        $list = [regex]::Match($cfg, '(?ms)customSkillDirs:\s*(.*?)(?=^\S|\z)')
        if ($list.Success) {
            $body = $list.Groups[1].Value
            $inline = [regex]::Match($body, '^\s*\[(?<inline>[^\]]*)\]')
            if ($inline.Success) {
                foreach ($part in ($inline.Groups['inline'].Value -split ',')) {
                    $p = $part.Trim().Trim('"').Trim("'")
                    if ($p) { $state.CustomDirs += $p }
                }
            } else {
                foreach ($line in ($body -split "`r?`n")) {
                    $m = [regex]::Match($line, '^\s*-\s*(.+)$')
                    if ($m.Success) {
                        $p = $m.Groups[1].Value.Trim().Trim('"').Trim("'")
                        if ($p) { $state.CustomDirs += $p }
                    }
                }
            }
        }
    }
    return $state
}

function Get-DshDiscoveryRoots([string]$WorkingDirectory) {
    if (-not $WorkingDirectory) { $WorkingDirectory = Get-DshCwd }
    $state = Get-DshPresetState
    $roots = [System.Collections.Generic.List[object]]::new()
    if ($state.IncludeDefaultRoots) {
        $projectRoot = Get-DshProjectRoot $WorkingDirectory
        if ($projectRoot) {
            $roots.Add((New-DshRoot (Join-Path $projectRoot '.dsh\skills') 'project' 'project-dsh' $false $false 'false' 'conditional' $false 'dsh-project-dsh-root' 100))
            $roots.Add((New-DshRoot (Join-Path $projectRoot '.agents\skills') 'project' 'project-agents' $false $false 'false' 'conditional' $false 'dsh-project-agents-root' 200))
        }
    }
    foreach ($dir in $state.CustomDirs) {
        $roots.Add((New-DshRoot $dir 'custom' 'custom' $false $false 'unknown' 'diagnostic-only' $false 'dsh-custom-root' 300))
    }
    if ($state.IncludeDefaultRoots) {
        $roots.Add((New-DshRoot (Get-DshUserSkillRoot) 'user' 'user-dsh' $true $false 'false' 'writable' $true 'dsh-user-root' 400))
        $roots.Add((New-DshRoot (Get-DshSharedSkillRoot) 'user' 'user-agents' $true $false 'false' 'writable/shared' $false 'dsh-shared-root' 500))
    }
    $bundled = Get-DshBundledDir
    if ($bundled) {
        $roots.Add((New-DshRoot $bundled 'deployment' 'bundled' $false $false 'unknown' 'diagnostic-only' $false 'dsh-bundled-root' 600))
    }
    return @($roots)
}

# Install target resolution by scope: user (default) / user-agents / project.
function Get-DshInstallRoot([string]$Scope, [string]$WorkingDirectory) {
    if (-not $WorkingDirectory) { $WorkingDirectory = Get-DshCwd }
    if ($Scope -eq 'user-agents') { return (Get-DshSharedSkillRoot) }
    if ($Scope -eq 'project') { return (Join-Path (Get-DshProjectRoot $WorkingDirectory) '.dsh\skills') }
    return (Get-DshUserSkillRoot)
}

# skill-manager's own write policy guards (not DSH protection facts):
# refuse bundled roots and the reserved `.system` namespace.
function Test-DshProtectedTarget([string]$Path) {
    $candidate = Resolve-DshPath $Path
    foreach ($root in @((Get-DshBundledDir), (Get-DshUserSystemRoot))) {
        if (-not $root) { continue }
        $protected = Resolve-DshPath $root
        if ($candidate -eq $protected -or $candidate.StartsWith($protected + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    return $false
}