# wrapper.ps1.tpl
#
# Optional template for a reviewed CLI bundle. This template is not generated
# automatically by the V0.2 installer.

$ErrorActionPreference = 'Stop'

$skillRoot = if ($env:CLAUDE_SKILLS_DIR) {
    Join-Path $env:CLAUDE_SKILLS_DIR '{{SKILL_NAME}}'
} else {
    Join-Path $env:USERPROFILE 'Claude-Code\{{SKILL_NAME}}'
}

if (-not (Test-Path -LiteralPath $skillRoot -PathType Container)) {
    Write-Error "Skill not installed at $skillRoot. Run install.ps1 first."
    exit 1
}

$binary = Join-Path $skillRoot '{{BINARY_REL_PATH}}'
if (-not (Test-Path -LiteralPath $binary -PathType Leaf)) {
    Write-Error "Binary not found: $binary"
    exit 1
}

& node $binary $args

