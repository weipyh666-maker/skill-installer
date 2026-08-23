# adapters/claude/detect.ps1 - Claude Code environment detection

function Test-ClaudeInstalled {
    $sourceDir = if ($env:CLAUDE_SKILLS_DIR) { $env:CLAUDE_SKILLS_DIR } else { (Join-Path $HOME 'Claude-Code') }
    $linkDir = if ($env:CLAUDE_SKILLS_LINK_DIR) { $env:CLAUDE_SKILLS_LINK_DIR } else { (Join-Path (Join-Path $HOME '.claude') 'skills') }
    return ((Test-Path -LiteralPath $linkDir) -or (Test-Path -LiteralPath $sourceDir))
}
