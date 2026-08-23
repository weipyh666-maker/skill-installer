# adapters/codex/detect.ps1 - Codex environment detection without CLI execution

function Get-CodexCliCommand {
    if ($env:SKILL_MANAGER_CODEX_CLI_PATH) {
        if (Test-Path -LiteralPath $env:SKILL_MANAGER_CODEX_CLI_PATH -PathType Leaf) { return $env:SKILL_MANAGER_CODEX_CLI_PATH }
        return $null
    }
    $command = Get-Command codex, codex.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) { return ($command.Path ?? $command.Source ?? $command.Definition) }
    return $null
}

function Get-CodexStatus {
    $cliPath = Get-CodexCliCommand
    $userRoot = Get-CodexUserSkillRoot
    $compatibilityRoot = Get-CodexCompatibilitySkillRoot
    $systemRoot = Get-CodexSystemSkillRoot
    return [pscustomobject]@{
        CliResolved = [bool]$cliPath
        CliPath = $cliPath
        ExecutableTest = 'not-run'
        CodexHome = Get-CodexHome
        UserRoot = $userRoot
        UserRootExists = (Test-Path -LiteralPath $userRoot -PathType Container)
        CompatibilityRoot = $compatibilityRoot
        CompatibilityRootExists = (Test-Path -LiteralPath $compatibilityRoot -PathType Container)
        SystemRoot = $systemRoot
        SystemRootExists = (Test-Path -LiteralPath $systemRoot -PathType Container)
        Usable = [bool]$cliPath -or (Test-Path -LiteralPath (Get-CodexHome) -PathType Container)
    }
}

function Test-CodexInstalled { return (Get-CodexStatus).Usable }
