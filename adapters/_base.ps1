# adapters/_base.ps1 - Base multi-agent adapter specifications

$global:SupportedAgents = @('claude', 'codex', 'antigravity')

function Resolve-AgentName([string]$Requested) {
    if ($Requested) { return $Requested.ToLowerInvariant() }
    if ($env:SKILL_MANAGER_AGENT) { return $env:SKILL_MANAGER_AGENT.ToLowerInvariant() }
    if ($env:CLAUDE_SKILLS_AGENT) { return $env:CLAUDE_SKILLS_AGENT.ToLowerInvariant() }
    return 'claude'
}

function Test-ValidAgentName([string]$Agent) {
    if ($global:SupportedAgents -contains $Agent) { return $true }
    Write-Error "Unknown agent '$Agent'. Supported agents: $($global:SupportedAgents -join ', ')"
    return $false
}
