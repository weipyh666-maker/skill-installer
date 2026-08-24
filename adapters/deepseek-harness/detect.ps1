# adapters/deepseek-harness/detect.ps1 - DeepSeek Harness environment detection without CLI execution
#
# Detection is split into two stages so callers cannot mistake "something DSH-shaped
# exists on disk" for "the skill runtime is ready to surface skills to a model":
#   detected        = cli_detected OR package_detected OR dsh_home_detected OR config_detected
#   skill_runtime_ready = provider_enabled AND consumer_detected (tool-skill / skill-search)
#   usable          = detected AND skill_runtime_ready
# A bare ~/.agents/skills directory, or a ~/.dsh home with no active preset provider+consumer,
# therefore yields usable=false. The CLI is resolved but never executed (executable_test=not-run).

function Get-DshCliCommand {
    if ($env:SKILL_MANAGER_DSH_CLI_PATH) {
        if (Test-Path -LiteralPath $env:SKILL_MANAGER_DSH_CLI_PATH -PathType Leaf) { return $env:SKILL_MANAGER_DSH_CLI_PATH }
        return $null
    }
    $command = Get-Command dsh, dsh.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) { return ($command.Path ?? $command.Source ?? $command.Definition) }
    return $null
}

# Best-effort npm package marker probe (no execution). Tests override via
# SKILL_MANAGER_DSH_PACKAGE_DETECTED=true|false; otherwise a local
# node_modules/@deepseek-ai/dsh* package.json marker counts as detected.
function Get-DshPackageDetected {
    $override = "$env:SKILL_MANAGER_DSH_PACKAGE_DETECTED".Trim().ToLowerInvariant()
    if ($override -eq 'true') { return $true }
    if ($override -eq 'false') { return $false }
    $cwd = Get-DshCwd
    foreach ($candidate in @(
        (Join-Path $cwd 'node_modules\@deepseek-ai\dsh\package.json'),
        (Join-Path $cwd 'node_modules\@deepseek-ai\dsh-cli\package.json')
    )) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $true }
    }
    return $false
}

function Get-DshStatus {
    $cliPath = Get-DshCliCommand
    $state = Get-DshPresetState
    $dshHome = Get-DshHome
    $agentsHome = Get-DshAgentsHome
    $bundled = Get-DshBundledDir
    $settings = Get-DshSettingsPath
    $dshHomeDetected = Test-Path -LiteralPath $dshHome -PathType Container
    $agentsHomeDetected = Test-Path -LiteralPath $agentsHome -PathType Container
    $configDetected = (Test-Path -LiteralPath $settings -PathType Leaf) -or ($null -ne $state.PresetPath -and (Test-Path -LiteralPath $state.PresetPath -PathType Leaf))
    $packageDetected = Get-DshPackageDetected
    $cliDetected = [bool]$cliPath
    $detected = $cliDetected -or $packageDetected -or $dshHomeDetected -or $configDetected
    $providerEnabled = [bool]$state.ProviderEnabled
    $consumerRaw = [string]$state.Consumer
    $consumerDetected = ($consumerRaw -eq 'tool-skill' -or $consumerRaw -eq 'skill-search')
    $skillRuntimeReady = $providerEnabled -and $consumerDetected
    $usable = $detected -and $skillRuntimeReady
    if (-not $detected) {
        $usableReason = 'not-detected'
    } elseif (-not $providerEnabled) {
        $usableReason = 'provider-not-enabled'
    } elseif (-not $consumerDetected) {
        $usableReason = if ($consumerRaw -eq 'none') { 'no-catalog-consumer-mounted' } else { 'consumer-unknown' }
    } else {
        $usableReason = 'detected-and-runtime-ready'
    }
    return [pscustomobject]@{
        CliResolved = [bool]$cliPath
        CliDetected = $cliDetected
        CliPath = $cliPath
        ExecutableTest = 'not-run'
        PackageDetected = $packageDetected
        DshHome = $dshHome
        DshHomeDetected = $dshHomeDetected
        ConfigDetected = $configDetected
        Detected = $detected
        AgentsHome = $agentsHome
        AgentsHomeDetected = $agentsHomeDetected
        UserRoot = (Get-DshUserSkillRoot)
        UserRootExists = (Test-Path -LiteralPath (Get-DshUserSkillRoot) -PathType Container)
        SharedRoot = (Get-DshSharedSkillRoot)
        SharedRootExists = (Test-Path -LiteralPath (Get-DshSharedSkillRoot) -PathType Container)
        BundledDir = $bundled
        BundledDirExists = [bool]$bundled -and (Test-Path -LiteralPath $bundled -PathType Container)
        ProviderEnabled = $providerEnabled
        Consumer = $consumerRaw
        ConsumerDetected = $consumerDetected
        SkillRuntimeReady = $skillRuntimeReady
        Usable = $usable
        UsableReason = $usableReason
    }
}

function Test-DshInstalled { return (Get-DshStatus).Usable }
