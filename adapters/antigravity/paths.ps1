# adapters/antigravity/paths.ps1 - Antigravity CLI filesystem paths

function Get-AntigravitySourceDir {
    if ($env:ANTIGRAVITY_SKILLS_DIR) { return $env:ANTIGRAVITY_SKILLS_DIR }
    return (Join-Path (Join-Path $HOME '.agents') 'skills')
}

function Get-AntigravityLinkDir {
    if ($env:ANTIGRAVITY_SKILLS_LINK_DIR) { return $env:ANTIGRAVITY_SKILLS_LINK_DIR }
    return (Join-Path (Join-Path (Join-Path $HOME '.gemini') 'antigravity-cli') 'skills')
}

function Test-AntigravityInstalled {
    throw "not-yet-implemented: see adapters/antigravity/stub-note.md"
}
