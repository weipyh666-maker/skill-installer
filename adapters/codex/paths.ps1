# adapters/codex/paths.ps1 - OpenAI Codex CLI filesystem paths

function Get-CodexSourceDir {
    if ($env:CODEX_SKILLS_DIR) { return $env:CODEX_SKILLS_DIR }
    return (Join-Path (Join-Path $HOME '.codex') 'skills')
}

function Get-CodexLinkDir {
    if ($env:CODEX_SKILLS_LINK_DIR) { return $env:CODEX_SKILLS_LINK_DIR }
    return (Join-Path (Join-Path (Join-Path $HOME '.config') 'codex') 'skills')
}

function Test-CodexInstalled {
    throw "not-yet-implemented: see adapters/codex/stub-note.md"
}
