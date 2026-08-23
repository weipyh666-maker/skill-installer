# adapters/claude/paths.ps1 - Claude Code filesystem paths

function Get-ClaudeSourceDir {
    if ($env:CLAUDE_SKILLS_DIR) { return $env:CLAUDE_SKILLS_DIR }
    return (Join-Path $HOME 'Claude-Code')
}

function Get-ClaudeLinkDir {
    if ($env:CLAUDE_SKILLS_LINK_DIR) { return $env:CLAUDE_SKILLS_LINK_DIR }
    return (Join-Path (Join-Path $HOME '.claude') 'skills')
}

function Get-ClaudeIndexPath {
    if ($env:CLAUDE_SKILLS_INDEX_PATH) { return $env:CLAUDE_SKILLS_INDEX_PATH }
    return (Join-Path (Get-ClaudeSourceDir) 'installed-skills-index.json')
}
