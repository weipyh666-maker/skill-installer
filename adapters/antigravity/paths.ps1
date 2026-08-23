# adapters/antigravity/paths.ps1 - Antigravity CLI filesystem paths and discovery roots

function Get-AntigravityGlobalSkillDir {
    if ($env:ANTIGRAVITY_SKILLS_LINK_DIR) { return $env:ANTIGRAVITY_SKILLS_LINK_DIR }
    if ($env:ANTIGRAVITY_SKILLS_DIR) { return $env:ANTIGRAVITY_SKILLS_DIR }
    if ($env:SKILL_MANAGER_STORE_DIR) { return $env:SKILL_MANAGER_STORE_DIR }
    return (Join-Path (Join-Path $HOME '.agents') 'skills')
}

function Get-AntigravitySourceDir {
    if ($env:ANTIGRAVITY_SKILLS_DIR) { return $env:ANTIGRAVITY_SKILLS_DIR }
    if ($env:SKILL_MANAGER_STORE_DIR) { return $env:SKILL_MANAGER_STORE_DIR }
    return (Join-Path (Join-Path $HOME '.agents') 'skills')
}

function Get-AntigravityLinkDir {
    if ($env:ANTIGRAVITY_SKILLS_LINK_DIR) { return $env:ANTIGRAVITY_SKILLS_LINK_DIR }
    if ($env:ANTIGRAVITY_SKILLS_DIR) { return $env:ANTIGRAVITY_SKILLS_DIR }
    return (Join-Path (Join-Path $HOME '.agents') 'skills')
}

function Get-AntigravityBuiltinDir {
    if ($env:ANTIGRAVITY_BUILTIN_DIR) { return $env:ANTIGRAVITY_BUILTIN_DIR }
    return (Join-Path (Join-Path (Join-Path $HOME '.gemini') 'antigravity-cli') 'builtin\skills')
}

function Get-AntigravityProjectSkillRoots([string]$WorkspaceRoot) {
    $roots = [System.Collections.Generic.List[string]]::new()
    if (-not $WorkspaceRoot) { return @() }
    
    $candidates = @('.agents\skills', '.agent\skills', '_agents\skills', '_agent\skills')
    foreach ($cand in $candidates) {
        $p = Join-Path $WorkspaceRoot $cand
        if (Test-Path -LiteralPath $p -PathType Container) {
            $roots.Add($p)
        }
    }
    
    $configPath = Join-Path $WorkspaceRoot '.agents\skills.json'
    if (Test-Path -LiteralPath $configPath -PathType Leaf) {
        try {
            $conf = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($conf.entries) {
                foreach ($entry in $conf.entries) {
                    if ($entry.path) {
                        $resolved = if ([System.IO.Path]::IsPathRooted($entry.path)) { $entry.path } else { Join-Path $WorkspaceRoot $entry.path }
                        if (Test-Path -LiteralPath $resolved -PathType Container) {
                            $roots.Add($resolved)
                        }
                    }
                }
            }
        } catch {}
    }
    return @($roots | Select-Object -Unique)
}

function Get-AntigravityIndexPath {
    if ($env:ANTIGRAVITY_SKILLS_INDEX_PATH) { return $env:ANTIGRAVITY_SKILLS_INDEX_PATH }
    if ($env:SKILL_MANAGER_INDEX_PATH) { return $env:SKILL_MANAGER_INDEX_PATH }
    return (Join-Path (Get-AntigravitySourceDir) 'installed-skills-index.json')
}
