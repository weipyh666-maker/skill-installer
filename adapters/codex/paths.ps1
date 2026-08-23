# adapters/codex/paths.ps1 - Codex multi-root Skill discovery

function Get-CodexUserHome {
    if ($env:SKILL_MANAGER_CODEX_USER_HOME) { return [IO.Path]::GetFullPath($env:SKILL_MANAGER_CODEX_USER_HOME) }
    if ($env:USERPROFILE) { return [IO.Path]::GetFullPath($env:USERPROFILE) }
    return [IO.Path]::GetFullPath($HOME)
}

function Get-CodexHome {
    if ($env:SKILL_MANAGER_CODEX_HOME) { return [IO.Path]::GetFullPath($env:SKILL_MANAGER_CODEX_HOME) }
    if ($env:CODEX_HOME) { return [IO.Path]::GetFullPath($env:CODEX_HOME) }
    return (Join-Path (Get-CodexUserHome) '.codex')
}

function Get-CodexUserSkillRoot { if ($env:SKILL_MANAGER_CODEX_USER_ROOT) { return [IO.Path]::GetFullPath($env:SKILL_MANAGER_CODEX_USER_ROOT) }; return (Join-Path (Join-Path (Get-CodexUserHome) '.agents') 'skills') }
function Get-CodexCompatibilitySkillRoot { return (Join-Path (Get-CodexHome) 'skills') }
function Get-CodexSystemSkillRoot { return (Join-Path (Get-CodexCompatibilitySkillRoot) '.system') }
function Get-CodexPluginSkillRoots {
    if ($env:SKILL_MANAGER_CODEX_PLUGIN_ROOT) { return @($env:SKILL_MANAGER_CODEX_PLUGIN_ROOT) }
    $cache = Join-Path (Join-Path (Get-CodexHome) 'plugins') 'cache'
    if (Test-Path -LiteralPath $cache -PathType Container) { return @($cache) }
    return @()
}

function Resolve-CodexPath([string]$Path) {
    if (Test-Path -LiteralPath $Path) { return (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) }
    return [IO.Path]::GetFullPath($Path).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
}

function Test-CodexProtectedPath([string]$Path) {
    $candidate = Resolve-CodexPath $Path
    $roots = @((Get-CodexSystemSkillRoot), (Get-CodexAdminSkillRoot)) | Where-Object { $_ }
    foreach ($root in $roots) {
        $protected = Resolve-CodexPath $root
        if ($candidate -eq $protected -or $candidate.StartsWith($protected + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    return $false
}

function New-CodexRoot([string]$Path, [string]$Scope, [string]$Class, [bool]$Writable, [bool]$Protected, [string]$Source) {
    return [pscustomobject]@{ path = Resolve-CodexPath $Path; scope = $Scope; class = $Class; writable = $Writable; protected = $Protected; source = $Source }
}

function Get-CodexProjectRoot([string]$WorkingDirectory) {
    $current = Get-Item -LiteralPath $WorkingDirectory -Force
    if (-not $current.PSIsContainer) { $current = $current.Directory }
    while ($null -ne $current) {
        if (Test-Path -LiteralPath (Join-Path $current.FullName '.git')) { return $current.FullName }
        $current = $current.Parent
    }
    return $null
}

function Get-CodexProjectSkillRoots([string]$WorkingDirectory) {
    if (-not $WorkingDirectory) { return @() }
    $current = Get-Item -LiteralPath $WorkingDirectory -Force -ErrorAction Stop
    if (-not $current.PSIsContainer) { $current = $current.Directory }
    $repoRoot = Get-CodexProjectRoot $current.FullName
    $roots = [Collections.Generic.List[object]]::new()
    while ($null -ne $current) {
        $candidate = Join-Path (Join-Path $current.FullName '.agents') 'skills'
        if (Test-Path -LiteralPath $candidate -PathType Container) { $roots.Add((New-CodexRoot $candidate 'project' 'agents' $false $false 'project-discovery')) }
        if (-not $repoRoot -or ((Resolve-CodexPath $current.FullName) -eq (Resolve-CodexPath $repoRoot))) { break }
        $current = $current.Parent
    }
    return @($roots)
}

function Get-CodexAdminSkillRoot {
    if ($env:SKILL_MANAGER_CODEX_ADMIN_ROOT) { return [IO.Path]::GetFullPath($env:SKILL_MANAGER_CODEX_ADMIN_ROOT) }
    if ($env:OS -eq 'Windows_NT') { return $null }
    return '/etc/codex/skills'
}

function Get-CodexDiscoveryRoots([string]$WorkingDirectory) {
    if (-not $WorkingDirectory) { $WorkingDirectory = if ($env:SKILL_MANAGER_CODEX_CWD) { $env:SKILL_MANAGER_CODEX_CWD } else { (Get-Location).Path } }
    $roots = [Collections.Generic.List[object]]::new()
    $roots.Add((New-CodexRoot (Get-CodexUserSkillRoot) 'user' 'agents' $true $false 'codex-user-root'))
    $roots.Add((New-CodexRoot (Get-CodexCompatibilitySkillRoot) 'compatibility' 'compatibility' $true $false 'codex-home-install-root'))
    $roots.Add((New-CodexRoot (Get-CodexSystemSkillRoot) 'system' 'system' $false $true 'codex-system-root'))
    foreach ($root in (Get-CodexProjectSkillRoots $WorkingDirectory)) { $roots.Add($root) }
    foreach ($root in (Get-CodexPluginSkillRoots)) { $roots.Add((New-CodexRoot $root 'plugin' 'plugin-cache' $false $false 'plugin-enablement-dependent')) }
    $adminRoot = Get-CodexAdminSkillRoot
    if ($adminRoot) { $roots.Add((New-CodexRoot $adminRoot 'admin' 'admin' $false $true 'codex-admin-root')) }
    return @($roots | Sort-Object path -Unique)
}

function Get-CodexIndexPath {
    if ($env:SKILL_MANAGER_CODEX_INDEX_PATH) { return $env:SKILL_MANAGER_CODEX_INDEX_PATH }
    return (Join-Path (Get-CodexHome) 'skill-manager-catalog.json')
}
