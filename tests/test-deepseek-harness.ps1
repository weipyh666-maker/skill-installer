[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$root = (Get-Item (Join-Path $PSScriptRoot '..')).FullName
. "$root\adapters\_base.ps1"
. "$root\adapters\deepseek-harness\paths.ps1"
. "$root\adapters\deepseek-harness\detect.ps1"

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw "ASSERTION FAILED: $Message" }
}

function New-TestSkill([string]$Directory, [string]$Name, [string]$Description, [string]$Extra = '') {
    $null = New-Item -ItemType Directory -Force -Path $Directory
    @('---', "name: $Name", "description: $Description", $Extra, '---', '', "# $Name") | Where-Object { $_ -ne '' -or $true } | Set-Content -LiteralPath (Join-Path $Directory 'SKILL.md') -Encoding utf8
}

function Invoke-DshCatalog([string[]]$Arguments) {
    $catalog = Join-Path $root 'lib\catalog.ps1'
    $output = & pwsh -NoProfile -File $catalog @Arguments 2>&1 | Out-String
    return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = $output }
}

$sandbox = Join-Path ([System.IO.Path]::GetTempPath()) ("skill-manager-dsh-" + [Guid]::NewGuid().ToString('N'))
$oldValues = @{}
$names = @('SKILL_MANAGER_DSH_HOME', 'SKILL_MANAGER_DSH_AGENTS_HOME', 'SKILL_MANAGER_DSH_BUNDLED_DIR', 'SKILL_MANAGER_DSH_CWD', 'SKILL_MANAGER_DSH_INDEX_PATH', 'SKILL_MANAGER_DSH_CLI_PATH', 'SKILL_MANAGER_DSH_SETTINGS_PATH', 'SKILL_MANAGER_DSH_PRESET')

try {
    foreach ($name in $names) { $oldValues[$name] = [Environment]::GetEnvironmentVariable($name, 'Process') }

    $dshHome = Join-Path $sandbox 'dsh-home'
    $agentsHome = Join-Path $sandbox 'agents-home'
    $bundledDir = Join-Path $sandbox 'bundled'
    $customDir = Join-Path $sandbox 'custom'
    $repo = Join-Path $sandbox 'repo'
    $cwd = Join-Path $repo 'apps\web'
    $userSkills = Join-Path $dshHome 'skills'
    $sharedSkills = Join-Path $agentsHome 'skills'
    $repoDshSkills = Join-Path $repo '.dsh\skills'
    $repoAgentsSkills = Join-Path $repo '.agents\skills'

    $env:SKILL_MANAGER_DSH_CLI_PATH = (Join-Path $sandbox 'missing-dsh.exe')
    $env:SKILL_MANAGER_DSH_HOME = (Join-Path $sandbox 'missing-dsh-home')
    $env:SKILL_MANAGER_DSH_AGENTS_HOME = $agentsHome
    $env:SKILL_MANAGER_DSH_CWD = $cwd

    # Phase 1: an unrelated ~/.agents skills directory alone must not make DSH usable.
    $null = New-Item -ItemType Directory -Force -Path $sharedSkills
    $status = Get-DshStatus
    Assert-True (-not $status.Usable) 'an unrelated agents directory alone must not make DeepSeek Harness usable'

    # Phase 2: DSH-specific home state + preset composition.
    $null = New-Item -ItemType Directory -Force -Path $userSkills, "$dshHome\.agent-presets\test-preset", $bundledDir, $customDir, (Join-Path $repo '.git'), $repoDshSkills, $repoAgentsSkills, $cwd
    $env:SKILL_MANAGER_DSH_HOME = $dshHome
    $env:SKILL_MANAGER_DSH_BUNDLED_DIR = $bundledDir
    $env:SKILL_MANAGER_DSH_INDEX_PATH = (Join-Path $sandbox 'index\index.json')
    $env:SKILL_MANAGER_DSH_SETTINGS_PATH = (Join-Path $dshHome 'settings.yaml')
    Set-Content -LiteralPath (Join-Path $dshHome 'settings.yaml') -Value "agent-presets:`n  default: test-preset" -Encoding utf8
    Set-Content -LiteralPath (Join-Path $dshHome '.agent-presets\test-preset\agent.cordis.yml') -Value @"
- id: skill-filesystem
  name: '@deepseek-ai/dsh-skill-filesystem'
  config:
    includeDefaultRoots: true
    watch: true
    customSkillDirs:
      - $customDir
- id: tool-skill
  name: '@deepseek-ai/dsh-tool-skill'
"@ -Encoding utf8

    New-TestSkill (Join-Path $userSkills 'frontend-design') 'frontend-design' 'Use when the user asks to build web UI from the user root.'
    New-TestSkill (Join-Path $userSkills 'duplicate-skill') 'duplicate-skill' 'Use when the user-dsh variant is needed.'
    New-TestSkill (Join-Path $sharedSkills 'duplicate-skill') 'duplicate-skill' 'Use when the user-agents variant is needed.'
    New-TestSkill (Join-Path $repoDshSkills 'duplicate-skill') 'duplicate-skill' 'Use when the project-dsh variant is needed.'
    New-TestSkill (Join-Path $repoAgentsSkills 'duplicate-skill') 'duplicate-skill' 'Use when the project-agents variant is needed.'
    New-TestSkill (Join-Path $customDir 'duplicate-skill') 'duplicate-skill' 'Use when the custom variant is needed.'
    New-TestSkill (Join-Path $bundledDir 'duplicate-skill') 'duplicate-skill' 'Use when the bundled variant is needed.'
    New-TestSkill (Join-Path $repoAgentsSkills 'project-helper') 'project-helper' 'Use when the project helper is needed.'
    New-TestSkill (Join-Path $customDir 'custom-helper') 'custom-helper' 'Use when the custom helper is needed.'
    New-TestSkill (Join-Path $bundledDir 'bundled-helper') 'bundled-helper' 'Use when the bundled helper is needed.'
    New-TestSkill (Join-Path $userSkills 'model-off') 'model-off' 'model invocation disabled' 'disable-model-invocation: true'
    New-TestSkill (Join-Path $userSkills 'legacy-key') 'legacy-key' 'legacy invocation key' 'disableModelInvocation: true'
    New-TestSkill (Join-Path $userSkills 'user-off') 'user-off' 'user invocation disabled' 'user-invocable: false'
    New-TestSkill (Join-Path $userSkills '.system\sys-hidden') 'sys-hidden' 'reserved namespace'
    $null = New-Item -ItemType Directory -Force -Path $userSkills
    Set-Content -LiteralPath (Join-Path $userSkills 'flat-skill.md') -Value "---`nname: flat-skill`ndescription: flat markdown skill`n---`n`n# flat`n" -Encoding utf8

    $status = Get-DshStatus
    Assert-True ($status.Usable) 'DSH home state must make DeepSeek Harness usable'
    Assert-True ($status.DshHome -eq $dshHome) 'status must report resolved DSH_HOME'
    Assert-True ($status.Consumer -eq 'tool-skill') 'consumer must be detected from the preset'
    Assert-True ($status.ProviderEnabled) 'provider must be detected from the preset'
    Assert-True ($status.SharedRootExists) 'shared-root existence must be reported independently'
    Assert-True ($status.Detected) 'DSH home + preset must set detected=true'
    Assert-True ($status.DshHomeDetected) 'dsh_home_detected must be reported'
    Assert-True ($status.ConfigDetected) 'settings+preset files must set config_detected=true'
    Assert-True (-not $status.PackageDetected) 'no local dsh package marker in sandbox'
    Assert-True ($status.ConsumerDetected) 'tool-skill consumer must be detected'
    Assert-True ($status.SkillRuntimeReady) 'provider+consumer must yield skill_runtime_ready=true'
    Assert-True ($status.UsableReason -eq 'detected-and-runtime-ready') 'usable_reason must explain the ready state'

    $roots = @(Get-DshDiscoveryRoots $cwd)
    Assert-True (@($roots | Where-Object { $_.class -eq 'project-dsh' -and $_.rank -eq 100 -and $_.path -eq (Resolve-DshPath $repoDshSkills) }).Count -eq 1) 'project-dsh root at rank 100'
    Assert-True (@($roots | Where-Object { $_.class -eq 'project-agents' -and $_.rank -eq 200 }).Count -eq 1) 'project-agents root at rank 200'
    Assert-True (@($roots | Where-Object { $_.class -eq 'custom' -and $_.rank -eq 300 -and $_.path -eq (Resolve-DshPath $customDir) }).Count -eq 1) 'custom root at rank 300 from preset customSkillDirs'
    Assert-True (@($roots | Where-Object { $_.class -eq 'user-dsh' -and $_.rank -eq 400 -and $_.system_reserved }).Count -eq 1) 'user-dsh root at rank 400 with reserved .system namespace'
    Assert-True (@($roots | Where-Object { $_.class -eq 'user-agents' -and $_.rank -eq 500 }).Count -eq 1) 'user-agents root at rank 500'
    Assert-True (@($roots | Where-Object { $_.class -eq 'bundled' -and $_.rank -eq 600 -and $_.write_policy -eq 'diagnostic-only' }).Count -eq 1) 'bundled root at rank 600 diagnostic-only'
    Assert-True (@($roots | Where-Object { $_.protected }).Count -eq 0) 'no DSH root may be marked protected (DSH defines no protected roots)'
    Assert-True (@($roots | Where-Object { $_.class -eq 'custom' -and $_.platform_protected -eq 'unknown' -and $_.write_policy -eq 'diagnostic-only' }).Count -eq 1) 'custom root: platform_protected unknown, write_policy diagnostic-only'
    Assert-True (@($roots | Where-Object { $_.class -eq 'user-agents' -and $_.platform_protected -eq 'false' -and $_.write_policy -eq 'writable/shared' }).Count -eq 1) 'user-agents root: platform_protected false, write_policy writable/shared'
    Assert-True (@($roots | Where-Object { $_.class -eq 'bundled' -and $_.platform_protected -eq 'unknown' }).Count -eq 1) 'bundled root: platform_protected unknown (DSH mutability undefined)'
    Assert-True (@($roots | Where-Object { $_.class -eq 'user-dsh' -and $_.platform_protected -eq 'false' }).Count -eq 1) 'user-dsh root: platform_protected false'
    Assert-True (@($roots | Where-Object { $_.class -eq 'project-dsh' -and $_.platform_protected -eq 'false' }).Count -eq 1) 'project-dsh root: platform_protected false'

    $refresh = Invoke-DshCatalog @('-Command', 'refresh', '-Agent', 'deepseek-harness')
    Assert-True ($refresh.ExitCode -eq 0) "DSH refresh must succeed. Output: $($refresh.Output)"
    $index = Get-Content -LiteralPath $env:SKILL_MANAGER_DSH_INDEX_PATH -Raw | ConvertFrom-Json
    $duplicate = @($index.skills | Where-Object { $_.name -eq 'duplicate-skill' })[0]
    $dshDup = $duplicate.agents.'deepseek-harness'
    Assert-True ($dshDup.paths.Count -eq 6) 'duplicate must retain every discovery path'
    Assert-True ($dshDup.precedence -eq 'within-layer-rank') 'duplicate precedence must be the verified within-layer rule'
    Assert-True ($dshDup.winner_confidence -eq 'within-layer-only') 'winner confidence must not claim cross-layer knowledge'
    Assert-True ($null -eq $dshDup.runtime_winner) 'runtime winner must remain null (cross-layer not observable)'
    Assert-True ($dshDup.metadata_conflict -eq $true) 'different duplicate metadata must be reported as a conflict'
    Assert-True ($dshDup.predicted_winner.path.EndsWith('repo\.dsh\skills\duplicate-skill') -or $dshDup.predicted_winner.path -like "$repoDshSkills\duplicate-skill") 'predicted within-layer winner must be the project-dsh variant (rank 100)'
    Assert-True ($dshDup.predicted_winner.rank -eq 100) 'predicted winner rank must be 100'
    Assert-True ($dshDup.visible) 'duplicate with a mounted catalog consumer must be visible'

    $modelOff = @($index.skills | Where-Object { $_.name -eq 'model-off' })[0].agents.'deepseek-harness'
    Assert-True (-not $modelOff.discoverable -eq $false -and -not $modelOff.eligible) 'model-disabled skill must be discoverable but not eligible'
    Assert-True (-not $modelOff.visible -and $modelOff.reason -eq 'not-model-invocable') 'model-disabled skill must be invisible with the right reason'

    $legacy = @($index.skills | Where-Object { $_.name -eq 'legacy-key' })[0].agents.'deepseek-harness'
    Assert-True (-not $legacy.discoverable -and -not $legacy.paths[0].dsh_valid) 'legacy invocation keys must make DSH reject the skill'

    Assert-True (@($index.skills | Where-Object { $_.name -eq 'sys-hidden' }).Count -eq 0) 'reserved .system namespace must not be indexed'
    Assert-True (@($index.dsh_reserved_namespace | Where-Object { $_ -like "$userSkills\.system" }).Count -eq 1) 'reserved .system namespace must be recorded as a fact'
    Assert-True (@($index.skills | Where-Object { $_.name -eq 'flat-skill' }).Count -eq 1) 'flat <name>.md skills must be discovered'

    $bundledHelper = @($index.skills | Where-Object { $_.name -eq 'bundled-helper' })[0].agents.'deepseek-harness'
    Assert-True ($bundledHelper.visible) 'bundled skills are catalog-visible to DSH'
    Assert-True (-not $bundledHelper.protected) 'bundled roots must NOT be marked protected (DSH fact)'
    Assert-True ($bundledHelper.paths[0].write_policy -eq 'diagnostic-only') 'skill-manager write policy for bundled must be diagnostic-only (separate field)'

    Assert-True ($index.dsh_preset.consumer -eq 'tool-skill' -and $index.dsh_preset.provider_enabled) 'index must record provider AND consumer state'

    # Visibility is inferred (expected), never confirmed from disk; winner basis is explicit.
    Assert-True ($dshDup.visibility_confidence -eq 'inferred') 'visibility_confidence must be inferred (no live session)'
    Assert-True ($dshDup.visibility_status -eq 'expected') 'visibility_status must be expected, not confirmed'
    Assert-True ($dshDup.winner_basis -eq 'filesystem-rank-root-order') 'winner_basis must name the deterministic filesystem ordering'
    Assert-True (@($dshDup.paths | Where-Object { $_.class -eq 'bundled' -and $_.platform_protected -eq 'unknown' }).Count -eq 1) 'bundled duplicate variant: platform_protected unknown'
    Assert-True (@($dshDup.paths | Where-Object { $_.class -eq 'custom' -and $_.platform_protected -eq 'unknown' -and $_.write_policy -eq 'diagnostic-only' }).Count -eq 1) 'custom duplicate variant: platform_protected unknown, diagnostic-only'

    # Fixture B: the static adapter observes only the filesystem provider, so it never
    # fabricates a cross-provider/runtime winner. precedence is within-layer, not global.
    Assert-True (@($dshDup.providers | Where-Object { $_ -eq 'filesystem' }).Count -eq 1 -and $dshDup.providers.Count -eq 1) 'only the filesystem provider is observed statically'
    Assert-True ($dshDup.precedence -eq 'within-layer-rank') 'precedence must stay within-layer, never global'
    Assert-True ($null -eq $dshDup.runtime_winner) 'no cross-provider runtime winner is claimed'

    $customHelper = @($index.skills | Where-Object { $_.name -eq 'custom-helper' })[0].agents.'deepseek-harness'
    Assert-True ($customHelper.paths[0].platform_protected -eq 'unknown' -and $customHelper.paths[0].write_policy -eq 'diagnostic-only') 'custom-helper variant: platform_protected unknown, diagnostic-only'

    # user-invocable:false affects explicit /name only, never model visibility/eligibility.
    $userOff = @($index.skills | Where-Object { $_.name -eq 'user-off' })[0].agents.'deepseek-harness'
    Assert-True ($userOff.discoverable -and $userOff.eligible -and $userOff.visible) 'user-invocable:false must not affect model visibility'
    Assert-True (-not $userOff.invocation.user_invocable) 'user-invocable:false must surface as user_invocable=false'
    Assert-True ($userOff.invocation.model_invocable) 'user-invocable:false must not disable model invocation'

    # Duplicate statistics reconciliation: every metric named explicitly.
    $summary = $index.dsh_duplicate_summary
    Assert-True ($null -ne $summary) 'index must carry dsh_duplicate_summary'
    Assert-True ($summary.physical_skill_entries -eq 14) 'physical_skill_entries must count every scanned variant'
    Assert-True ($summary.unique_skill_names -eq 9) 'unique_skill_names must count indexed names'
    Assert-True ($summary.duplicate_names -eq 1) 'one duplicate name (duplicate-skill)'
    Assert-True ($summary.duplicate_variants -eq 6) 'duplicate-skill has 6 variants'
    Assert-True ($summary.duplicate_candidate_variants -eq 6) 'all 6 duplicate variants are valid candidates'
    Assert-True ($summary.predicted_winners -eq 8) 'predicted winners = skills with a valid within-layer winner'
    Assert-True ($summary.confirmed_runtime_winners -eq 0) 'no confirmed runtime winners (cross-layer not observable)'

    $find = Invoke-DshCatalog @('-Command', 'find', '-Agent', 'deepseek-harness', '-Query', '做网页 UI')
    Assert-True ($find.ExitCode -eq 0 -and $find.Output -match 'frontend-design') 'DSH Find must reuse the shared scorer over visible inventory'

    $doctor = Invoke-DshCatalog @('-Command', 'doctor', '-Agent', 'deepseek-harness')
    Assert-True ($doctor.ExitCode -eq 0) "DSH doctor must succeed. Output: $($doctor.Output)"
    Assert-True ($doctor.Output -match 'Duplicate DeepSeek Harness Skill name') 'DSH Doctor must report duplicates'
    Assert-True ($doctor.Output -match 'predicted within-layer winner') 'DSH Doctor must report the predicted within-layer winner'
    Assert-True ($doctor.Output -match 'does not claim a runtime winner') 'DSH Doctor must not claim a runtime winner'
    Assert-True ($doctor.Output -match 'reserved .system namespace') 'DSH Doctor must note the reserved .system namespace'
    Assert-True ($doctor.Output -match 'watch:') 'DSH Doctor must report watch state'
    Assert-True ($doctor.Output -match 'no restart needed') 'watch=true must not recommend a restart'
    Assert-True ($doctor.Output -match 'catalog visibility: expected') 'DSH Doctor must say visibility is expected, not confirmed'

    $bundledFix = Invoke-DshCatalog @('-Command', 'fix', '-Agent', 'deepseek-harness', '-Name', 'bundled-helper', '-DryRun')
    Assert-True ($bundledFix.ExitCode -ne 0 -and $bundledFix.Output -match 'diagnostic-only') 'DSH fix dry-run must refuse a bundled skill (diagnostic-only)'

    $legacyFix = Invoke-DshCatalog @('-Command', 'fix', '-Agent', 'deepseek-harness', '-Name', 'legacy-key', '-DryRun')
    Assert-True ($legacyFix.ExitCode -ne 0 -and $legacyFix.Output -match 'DSH would reject') 'DSH fix dry-run must refuse a skill DSH rejects'

    # Phase 3: consumer gate — a preset without any consumer keeps skills conditional and invisible.
    $null = New-Item -ItemType Directory -Force -Path "$dshHome\.agent-presets\no-consumer"
    Set-Content -LiteralPath (Join-Path $dshHome '.agent-presets\no-consumer\agent.cordis.yml') -Value @"
- id: skill-filesystem
  name: '@deepseek-ai/dsh-skill-filesystem'
"@ -Encoding utf8
    $env:SKILL_MANAGER_DSH_PRESET = 'no-consumer'
    $refreshNoConsumer = Invoke-DshCatalog @('-Command', 'refresh', '-Agent', 'deepseek-harness')
    Assert-True ($refreshNoConsumer.ExitCode -eq 0) "no-consumer refresh must succeed. Output: $($refreshNoConsumer.Output)"
    $index2 = Get-Content -LiteralPath $env:SKILL_MANAGER_DSH_INDEX_PATH -Raw | ConvertFrom-Json
    $fe = @($index2.skills | Where-Object { $_.name -eq 'frontend-design' })[0].agents.'deepseek-harness'
    Assert-True (-not $fe.visible -and $fe.conditional -and $fe.reason -eq 'no-catalog-consumer-mounted') 'skills must be conditional and invisible without a mounted consumer'
    $statusNoConsumer = Get-DshStatus
    Assert-True (-not $statusNoConsumer.Usable) 'no-consumer preset must yield usable=false'
    Assert-True (-not $statusNoConsumer.SkillRuntimeReady) 'provider without consumer must yield skill_runtime_ready=false'
    Assert-True ($statusNoConsumer.UsableReason -eq 'no-catalog-consumer-mounted') 'usable_reason must explain the missing consumer'
    Remove-Item Env:SKILL_MANAGER_DSH_PRESET

    # Phase 4: fake CLI detection without executing it.
    $fakeBin = Join-Path $sandbox 'bin'
    $null = New-Item -ItemType Directory -Force -Path $fakeBin
    Set-Content -LiteralPath (Join-Path $fakeBin 'dsh.cmd') -Value '@exit /b 0' -Encoding ascii
    $env:SKILL_MANAGER_DSH_CLI_PATH = (Join-Path $fakeBin 'dsh.cmd')
    $status = Get-DshStatus
    Assert-True ($status.CliResolved) 'resolved fake CLI must be reported'
    Assert-True ($status.Usable) 'resolved CLI must make DeepSeek Harness usable'
    Assert-True ($status.ExecutableTest -eq 'not-run') 'detection must not execute the CLI'

    # Phase 5: a ~/.dsh home with no preset provider/consumer must NOT be usable.
    $bareHome = Join-Path $sandbox 'bare-dsh-home'
    $null = New-Item -ItemType Directory -Force -Path (Join-Path $bareHome 'skills')
    $env:SKILL_MANAGER_DSH_HOME = $bareHome
    $env:SKILL_MANAGER_DSH_SETTINGS_PATH = (Join-Path $bareHome 'settings.yaml')
    Remove-Item Env:SKILL_MANAGER_DSH_PRESET -ErrorAction SilentlyContinue
    $env:SKILL_MANAGER_DSH_CLI_PATH = (Join-Path $sandbox 'missing-dsh.exe')
    $statusBare = Get-DshStatus
    Assert-True ($statusBare.DshHomeDetected -and $statusBare.Detected) 'bare dsh home is detected'
    Assert-True (-not $statusBare.ProviderEnabled) 'bare dsh home has no preset provider'
    Assert-True (-not $statusBare.SkillRuntimeReady) 'bare dsh home is not runtime-ready'
    Assert-True (-not $statusBare.Usable) 'a ~/.dsh home with no provider/consumer must not be usable'
    Assert-True ($statusBare.UsableReason -eq 'provider-not-enabled') 'usable_reason must name the missing provider'

    Write-Host 'PASS: DeepSeek Harness root, detection, duplicate, visibility, doctor and fix tests'
} finally {
    foreach ($name in $names) {
        if ($null -eq $oldValues[$name]) { Remove-Item "Env:$name" -ErrorAction SilentlyContinue }
        else { [Environment]::SetEnvironmentVariable($name, $oldValues[$name], 'Process') }
    }
    Remove-Item -LiteralPath $sandbox -Recurse -Force -ErrorAction SilentlyContinue
}