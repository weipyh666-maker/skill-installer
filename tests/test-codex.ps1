[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$root = (Get-Item (Join-Path $PSScriptRoot '..')).FullName
. "$root\adapters\_base.ps1"
. "$root\adapters\codex\paths.ps1"
. "$root\adapters\codex\detect.ps1"

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw "ASSERTION FAILED: $Message" }
}

function New-TestSkill([string]$Directory, [string]$Name, [string]$Description) {
    $null = New-Item -ItemType Directory -Force -Path $Directory
    @('---', "name: $Name", "description: $Description", '---', '', "# $Name") | Set-Content -LiteralPath (Join-Path $Directory 'SKILL.md') -Encoding utf8
}

function Invoke-CodexCatalog([string[]]$Arguments) {
    $catalog = Join-Path $root 'lib\catalog.ps1'
    $output = & pwsh -NoProfile -File $catalog @Arguments 2>&1 | Out-String
    return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = $output }
}

$sandbox = Join-Path ([System.IO.Path]::GetTempPath()) ("skill-manager-codex-" + [Guid]::NewGuid().ToString('N'))
$oldValues = @{}
$names = @('SKILL_MANAGER_CODEX_HOME', 'SKILL_MANAGER_CODEX_USER_HOME', 'SKILL_MANAGER_CODEX_CWD', 'SKILL_MANAGER_CODEX_INDEX_PATH', 'SKILL_MANAGER_CODEX_CLI_PATH', 'SKILL_MANAGER_CODEX_PLUGIN_ROOT', 'CODEX_HOME')

try {
    foreach ($name in $names) { $oldValues[$name] = [Environment]::GetEnvironmentVariable($name, 'Process') }

    $userHome = Join-Path $sandbox 'user-home'
    $codexHome = Join-Path $sandbox 'codex-home'
    $repo = Join-Path $sandbox 'repo'
    $cwd = Join-Path $repo 'apps\web'
    $userSkills = Join-Path $userHome '.agents\skills'
    $compatibilitySkills = Join-Path $codexHome 'skills'
    $systemSkills = Join-Path $compatibilitySkills '.system'
    $pluginRoot = Join-Path $sandbox 'plugin-cache'
    $rootProjectSkills = Join-Path $repo '.agents\skills'
    $appProjectSkills = Join-Path $repo 'apps\.agents\skills'

    $null = New-Item -ItemType Directory -Force -Path $userSkills, $rootProjectSkills, $appProjectSkills, $cwd
    $null = New-Item -ItemType Directory -Force -Path (Join-Path $repo '.git')
    $env:SKILL_MANAGER_CODEX_HOME = $codexHome
    $env:SKILL_MANAGER_CODEX_USER_HOME = $userHome
    $env:SKILL_MANAGER_CODEX_CWD = $cwd
    $env:SKILL_MANAGER_CODEX_INDEX_PATH = (Join-Path $sandbox 'index\codex-index.json')
    $env:SKILL_MANAGER_CODEX_CLI_PATH = (Join-Path $sandbox 'missing-codex.exe')
    $env:SKILL_MANAGER_CODEX_PLUGIN_ROOT = $pluginRoot

    $status = Get-CodexStatus
    Assert-True (-not $status.Usable) 'an unrelated .agents directory alone must not make Codex usable'

    $null = New-Item -ItemType Directory -Force -Path $compatibilitySkills, $systemSkills
    $roots = @(Get-CodexDiscoveryRoots $cwd)
    Assert-True (@($roots | Where-Object { $_.class -eq 'agents' -and $_.scope -eq 'user' -and $_.path -eq $userSkills }).Count -eq 1) 'user .agents root must be discovered'
    Assert-True (@($roots | Where-Object { $_.class -eq 'compatibility' -and $_.path -eq $compatibilitySkills -and $_.writable }).Count -eq 1) 'codex-home must be a writable compatibility install target'
    Assert-True (@($roots | Where-Object { $_.class -eq 'system' -and $_.path -eq $systemSkills -and $_.protected }).Count -eq 1) 'system root must be protected'
    Assert-True (@($roots | Where-Object { $_.scope -eq 'project' }).Count -eq 2) 'all project ancestor roots must be retained'
    Assert-True (@($roots | Where-Object { $_.path -match '\.codex\skills$' -and $_.scope -eq 'project' }).Count -eq 0) 'project .codex skills must never be discovered'

    $status = Get-CodexStatus
    Assert-True ($status.CodexHome -eq $codexHome) 'status must report resolved CODEX_HOME'
    Assert-True ($status.UserRootExists) 'user-root existence must be reported independently'
    Assert-True ($status.CompatibilityRootExists) 'compatibility-root existence must be reported independently'
    Assert-True ($status.SystemRootExists) 'system-root existence must be reported independently'
    Assert-True ($status.Usable) 'Codex-specific home state must be distinguishable from a generic .agents root'

    New-TestSkill (Join-Path $userSkills 'frontend-design') 'frontend-design' 'Use when the user asks to build web UI from the user root.'
    New-TestSkill (Join-Path $userSkills 'duplicate-skill') 'duplicate-skill' 'Use when the user needs the user variant.'
    New-TestSkill (Join-Path $compatibilitySkills 'duplicate-skill') 'duplicate-skill' 'Use when the user needs the compatibility variant.'
    New-TestSkill (Join-Path $rootProjectSkills 'project-helper') 'project-helper' 'Use when the repository root helper is needed.'
    New-TestSkill (Join-Path $appProjectSkills 'app-helper') 'app-helper' 'Use when the application helper is needed.'
    New-TestSkill (Join-Path $systemSkills 'openai-docs') 'openai-docs' 'Use when official Codex documentation is needed.'
    New-TestSkill (Join-Path $pluginRoot 'example\skills\plugin-helper') 'plugin-helper' 'Use when a plugin supplied workflow is needed.'
    $externalSkillPath = Join-Path $sandbox 'external\external-helper\SKILL.md'
    @(
        '[[skills.config]]'
        "path = `"$(Join-Path $appProjectSkills 'app-helper\SKILL.md')`""
        'enabled = false'
        ''
        '[[skills.config]]'
        "path = `"$externalSkillPath`""
        'enabled = true'
    ) | Set-Content -LiteralPath (Join-Path $codexHome 'config.toml') -Encoding utf8

    $refresh = Invoke-CodexCatalog @('-Command', 'refresh', '-Agent', 'codex')
    Assert-True ($refresh.ExitCode -eq 0) "Codex refresh must succeed. Output: $($refresh.Output)"
    $index = Get-Content -LiteralPath $env:SKILL_MANAGER_CODEX_INDEX_PATH -Raw | ConvertFrom-Json
    $duplicate = @($index.skills | Where-Object { $_.name -eq 'duplicate-skill' })[0]
    Assert-True ($duplicate.agents.codex.paths.Count -eq 2) 'duplicate must retain every Codex path'
    Assert-True ($duplicate.agents.codex.precedence -eq 'unknown') 'duplicate precedence must remain unknown'
    Assert-True ($duplicate.agents.codex.metadata_conflict -eq $true) 'different duplicate metadata must be reported as a conflict'
    $disabled = @($index.skills | Where-Object { $_.name -eq 'app-helper' })[0]
    Assert-True (-not $disabled.agents.codex.visible -and -not $disabled.agents.codex.enabled -and $disabled.agents.codex.reason -eq 'disabled-by-codex-config') 'disabled config entry must remain on disk but invisible'
    Assert-True (@($index.codex_config_external | Where-Object { $_.path -eq $externalSkillPath -and $_.status -eq 'unknown' }).Count -eq 1) 'external config-only path must remain unknown rather than invalid'
    Assert-True (@($index.skills | Where-Object { $_.name -eq 'openai-docs' -and $_.agents.codex.protected }).Count -eq 1) 'system skills must be indexed as protected'
    Assert-True (@($index.skills | Where-Object { $_.name -eq 'plugin-helper' -and $_.agents.codex.reason -eq 'plugin-enablement-dependent' -and -not $_.agents.codex.visible }).Count -eq 1) 'plugin cache visibility must remain conditional'

    $find = Invoke-CodexCatalog @('-Command', 'find', '-Agent', 'codex', '-Query', '做网页 UI')
    Assert-True ($find.ExitCode -eq 0 -and $find.Output -match 'frontend-design') 'Codex Find must reuse the shared scorer over visible inventory'

    $doctor = Invoke-CodexCatalog @('-Command', 'doctor', '-Agent', 'codex')
    Assert-True ($doctor.ExitCode -eq 0 -and $doctor.Output -match 'Duplicate Codex Skill name') 'Codex Doctor must report duplicates without choosing a winner'

    $protectedFix = Invoke-CodexCatalog @('-Command', 'fix', '-Agent', 'codex', '-Name', 'openai-docs', '-DryRun')
    Assert-True ($protectedFix.ExitCode -ne 0 -and $protectedFix.Output -match 'protected Codex SYSTEM Skill') 'Codex fix dry-run must refuse a protected system skill'

    $fakeBin = Join-Path $sandbox 'bin'
    $null = New-Item -ItemType Directory -Force -Path $fakeBin
    Set-Content -LiteralPath (Join-Path $fakeBin 'codex.cmd') -Value '@exit /b 0' -Encoding ascii
    $env:SKILL_MANAGER_CODEX_CLI_PATH = (Join-Path $fakeBin 'codex.cmd')
    $status = Get-CodexStatus
    Assert-True ($status.CliResolved) 'resolved fake CLI must be reported'
    Assert-True ($status.Usable) 'resolved CLI must make Codex usable'
    Assert-True ($status.ExecutableTest -eq 'not-run') 'detection must not execute the CLI'

    Write-Host 'PASS: Codex root and detection tests'
} finally {
    foreach ($name in $names) {
        if ($null -eq $oldValues[$name]) { Remove-Item "Env:$name" -ErrorAction SilentlyContinue }
        else { [Environment]::SetEnvironmentVariable($name, $oldValues[$name], 'Process') }
    }
    Remove-Item -LiteralPath $sandbox -Recurse -Force -ErrorAction SilentlyContinue
}
