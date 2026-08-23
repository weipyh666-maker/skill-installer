$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$installer = Join-Path $root 'lib/install.ps1'
$fixture = Join-Path $PSScriptRoot 'fixtures/minimal-skill'
$sandbox = Join-Path $env:TEMP "skill-installer-test-$([guid]::NewGuid().ToString('N'))"
$sourceRoot = Join-Path $sandbox 'sources'
$linkRoot = Join-Path $sandbox 'links'

function Assert-True([bool]$condition, [string]$message) {
    if (-not $condition) { throw "ASSERTION FAILED: $message" }
}

function Invoke-Installer([string[]]$arguments) {
    $output = & pwsh -NoProfile -File $installer @arguments 2>&1 | Out-String
    [PSCustomObject]@{
        ExitCode = $LASTEXITCODE
        Output   = $output
    }
}

New-Item -ItemType Directory -Path $sandbox -Force | Out-Null
$oldSkillsDir = $env:CLAUDE_SKILLS_DIR
$oldLinkDir = $env:CLAUDE_SKILLS_LINK_DIR
$oldSkipSmoke = $env:SKIP_SMOKE_TEST
$oldSkipMemory = $env:SKIP_MEMORY_UPDATE

try {
    $env:CLAUDE_SKILLS_DIR = $sourceRoot
    $env:CLAUDE_SKILLS_LINK_DIR = $linkRoot
    $env:SKIP_SMOKE_TEST = '1'
    $env:SKIP_MEMORY_UPDATE = '1'

    $dryRun = Invoke-Installer @('-LocalPath', $fixture, '-Name', 'minimal-skill', '-DryRun')
    Assert-True ($dryRun.ExitCode -eq 0) "local dry-run should succeed without gh authentication. Output: $($dryRun.Output)"
    Assert-True ($dryRun.Output -match 'DRY RUN') 'dry-run should be explicit in output'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $sourceRoot 'minimal-skill'))) 'dry-run must not create source files'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $linkRoot 'minimal-skill'))) 'dry-run must not create links'

    $invalid = Invoke-Installer @('-LocalPath', $fixture, '-Name', '..\escape', '-DryRun')
    Assert-True ($invalid.ExitCode -ne 0) 'path traversal name must be rejected'
    Assert-True ($invalid.Output -match 'skill name|invalid|path') 'invalid name should explain the validation failure'

    New-Item -ItemType Directory -Path (Join-Path $sourceRoot 'minimal-skill') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $sourceRoot 'minimal-skill\sentinel.txt') -Value 'keep me' -Encoding utf8
    $withoutForce = Invoke-Installer @('-LocalPath', $fixture, '-Name', 'minimal-skill')
    Assert-True ($withoutForce.ExitCode -ne 0) 'existing install must require explicit force'
    Assert-True ((Get-Content -Raw -LiteralPath (Join-Path $sourceRoot 'minimal-skill\sentinel.txt')) -match 'keep me') 'existing source must not be removed on refusal'

    $secretFixture = Join-Path $sandbox 'secret-skill'
    Copy-Item -LiteralPath $fixture -Destination $secretFixture -Recurse -Force
    Set-Content -LiteralPath (Join-Path $secretFixture '.env') -Value 'DO_NOT_COPY=1' -Encoding utf8
    $secret = Invoke-Installer @('-LocalPath', $secretFixture, '-Name', 'secret-skill', '-DryRun')
    Assert-True ($secret.ExitCode -ne 0) 'sensitive local files must be rejected'
    Assert-True ($secret.Output -match 'sensitive') 'sensitive-file failure should be explicit'

    $symlinkFixture = Join-Path $sandbox 'symlink-skill'
    Copy-Item -LiteralPath $fixture -Destination $symlinkFixture -Recurse -Force
    $symlinkCreated = $false
    try {
        $linkPath = Join-Path $symlinkFixture 'leaked.md'
        New-Item -ItemType SymbolicLink -Path $linkPath -Target (Join-Path $fixture 'SKILL.md') -ErrorAction Stop | Out-Null
        $linkItem = Get-Item -LiteralPath $linkPath -Force -ErrorAction Stop
        if ($linkItem.Attributes -band [IO.FileAttributes]::ReparsePoint) { $symlinkCreated = $true }
    } catch {
        $symlinkCreated = $false
    }
    if ($symlinkCreated) {
        $symlink = Invoke-Installer @('-LocalPath', $symlinkFixture, '-Name', 'symlink-skill', '-DryRun')
        Assert-True ($symlink.ExitCode -ne 0) 'internal symlink must be rejected'
        Assert-True ($symlink.Output -match 'reparse-point|Refusing') 'symlink rejection should mention reparse-point'
    } else {
        Write-Output 'note: this environment cannot create reparse points; skipping symlink regression'
    }

    $fresh = Invoke-Installer @('-LocalPath', $fixture, '-Name', 'fresh-skill')
    Assert-True ($fresh.ExitCode -eq 0) "fresh local install should succeed. Output: $($fresh.Output)"
    Assert-True (Test-Path -LiteralPath (Join-Path $sourceRoot 'fresh-skill\SKILL.md')) 'fresh source should exist'
    Assert-True (Test-Path -LiteralPath (Join-Path $linkRoot 'fresh-skill\SKILL.md')) 'fresh link should exist'
    Assert-True (Test-Path -LiteralPath (Join-Path $sourceRoot 'installed-skills-index.json')) 'successful install should refresh the catalog index'
    $freshIndex = Get-Content -Raw -LiteralPath (Join-Path $sourceRoot 'installed-skills-index.json') | ConvertFrom-Json
    Assert-True (@($freshIndex.skills | Where-Object install_name -eq 'fresh-skill').Count -eq 1) 'catalog should include the newly installed skill directory'

    $forced = Invoke-Installer @('-LocalPath', $fixture, '-Name', 'fresh-skill', '-Force')
    Assert-True ($forced.ExitCode -eq 0) "forced replacement should succeed. Output: $($forced.Output)"
    Assert-True ($forced.Output -match 'backed up') 'forced replacement should report a backup'
    Assert-True ((Get-ChildItem -LiteralPath (Join-Path $sourceRoot '.backups') -Directory -ErrorAction SilentlyContinue | Where-Object Name -like 'fresh-skill-*').Count -gt 0) 'forced replacement should create a backup directory'

    Remove-Item Env:SKIP_MEMORY_UPDATE -ErrorAction SilentlyContinue
    Set-Content -LiteralPath (Join-Path $sourceRoot 'installed-tools-summary.md') -Value '| Skill | Repo | Source | Link | Smoke | Date |' -Encoding utf8
    $memoryFirst = Invoke-Installer @('-LocalPath', $fixture, '-Name', 'memory-skill', '-UpdateMemory')
    $memorySecond = Invoke-Installer @('-LocalPath', $fixture, '-Name', 'memory-skill', '-Force', '-UpdateMemory')
    Assert-True ($memoryFirst.ExitCode -eq 0 -and $memorySecond.ExitCode -eq 0) 'memory update installs should succeed'
    $memoryRows = @(Select-String -LiteralPath (Join-Path $sourceRoot 'installed-tools-summary.md') -Pattern '\| memory-skill \|')
    Assert-True ($memoryRows.Count -eq 1) 'memory update should be idempotent'

    # Option flags validation tests
    $mutexAuth = Invoke-Installer @('-Repo', 'owner/repo', '-RequireAuth', '-AllowAnonymousFallback', '-DryRun')
    Assert-True ($mutexAuth.ExitCode -ne 0) '-RequireAuth and -AllowAnonymousFallback should be mutually exclusive'
    Assert-True ($mutexAuth.Output -match 'Use either -RequireAuth or -AllowAnonymousFallback') 'mutex error should explain the conflict'

    $localAuthErr = Invoke-Installer @('-LocalPath', $fixture, '-RequireAuth', '-DryRun')
    Assert-True ($localAuthErr.ExitCode -ne 0) '-RequireAuth with local path should fail'

    # Mock unauthenticated gh environment
    $mockBin = Join-Path $sandbox 'mock-bin'
    New-Item -ItemType Directory -Path $mockBin -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $mockBin 'gh.cmd') -Value "@exit /b 1`r`n" -Encoding ascii
    $oldPath = $env:PATH
    try {
        $env:PATH = "$mockBin;$oldPath"

        # Anonymous fallback dry-run
        $anonDry = Invoke-Installer @('-Repo', 'weipyh666-maker/skill-installer', '-DryRun')
        Assert-True ($anonDry.ExitCode -eq 0) "anonymous fallback dry-run should succeed. Output: $($anonDry.Output)"
        Assert-True ($anonDry.Output -match 'anonymous public repository fallback') 'pre-flight should report anonymous fallback'

        # RequireAuth with unauthenticated gh must fail
        $reqAuthFail = Invoke-Installer @('-Repo', 'weipyh666-maker/skill-installer', '-RequireAuth', '-DryRun')
        Assert-True ($reqAuthFail.ExitCode -ne 0) 'RequireAuth must fail when gh is unauthenticated'
        Assert-True ($reqAuthFail.Output -match 'gh is not authenticated|gh CLI not found') 'RequireAuth failure should mention gh'
    } finally {
        $env:PATH = $oldPath
    }

    # V3.0 Multi-Agent Tests
    $agentClaude = Invoke-Installer @('-LocalPath', $fixture, '-Name', 'minimal-skill', '-Agent', 'claude', '-DryRun')
    Assert-True ($agentClaude.ExitCode -eq 0) "Agent claude should succeed. Output: $($agentClaude.Output)"

    $agentAntigravity = Invoke-Installer @('-LocalPath', $fixture, '-Name', 'minimal-skill', '-Agent', 'antigravity', '-DryRun')
    Assert-True ($agentAntigravity.ExitCode -eq 0) "Agent antigravity should succeed. Output: $($agentAntigravity.Output)"

    $agentCodex = Invoke-Installer @('-LocalPath', $fixture, '-Name', 'minimal-skill', '-Agent', 'codex', '-DryRun')
    Assert-True ($agentCodex.ExitCode -ne 0) 'Agent codex should fail with stub error'
    Assert-True ($agentCodex.Output -match 'not-yet-implemented: see adapters/codex/stub-note.md') 'Agent codex should mention stub note'

    $oldSkillsAgent = $env:CLAUDE_SKILLS_AGENT
    try {
        $env:CLAUDE_SKILLS_AGENT = 'codex'
        $agentCodexEnv = Invoke-Installer @('-LocalPath', $fixture, '-Name', 'minimal-skill', '-DryRun')
        Assert-True ($agentCodexEnv.ExitCode -ne 0) 'CLAUDE_SKILLS_AGENT=codex should fail with stub error'
        Assert-True ($agentCodexEnv.Output -match 'not-yet-implemented: see adapters/codex/stub-note.md') 'Agent codex should mention stub note'
    } finally {
        $env:CLAUDE_SKILLS_AGENT = $oldSkillsAgent
    }

    Write-Output 'PASS: installer regression tests'
}
finally {
    $env:CLAUDE_SKILLS_DIR = $oldSkillsDir
    $env:CLAUDE_SKILLS_LINK_DIR = $oldLinkDir
    $env:SKIP_SMOKE_TEST = $oldSkipSmoke
    $env:SKIP_MEMORY_UPDATE = $oldSkipMemory
    if (Test-Path -LiteralPath $sandbox) { Remove-Item -LiteralPath $sandbox -Recurse -Force }
}
