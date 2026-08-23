$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$catalog = Join-Path $root 'lib/catalog.ps1'
$sandbox = Join-Path $env:TEMP "skill-catalog-test-$([guid]::NewGuid().ToString('N'))"
$linkRoot = Join-Path $sandbox 'links'
$sourceRoot = Join-Path $sandbox 'sources'
$indexPath = Join-Path $sourceRoot 'installed-skills-index.json'

function Assert-True([bool]$condition, [string]$message) {
    if (-not $condition) { throw "ASSERTION FAILED: $message" }
}

function Invoke-Catalog([string[]]$arguments) {
    $output = & pwsh -NoProfile -File $catalog @arguments 2>&1 | Out-String
    [PSCustomObject]@{ ExitCode = $LASTEXITCODE; Output = $output }
}

function New-TestSkill([string]$directory, [string]$name, [string]$description) {
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
    @(
        '---'
        "name: $name"
        "description: $description"
        '---'
        ''
        "# $name"
        ''
        'Use this skill when the matching task is requested.'
    ) | Set-Content -LiteralPath (Join-Path $directory 'SKILL.md') -Encoding utf8
}

$oldSkillsDir = $env:CLAUDE_SKILLS_DIR
$oldLinkDir = $env:CLAUDE_SKILLS_LINK_DIR
$oldCodexHome = $env:SKILL_MANAGER_CODEX_HOME
$oldCodexUserHome = $env:SKILL_MANAGER_CODEX_USER_HOME
$oldCodexCwd = $env:SKILL_MANAGER_CODEX_CWD
$oldCodexIndex = $env:SKILL_MANAGER_CODEX_INDEX_PATH
try {
    New-Item -ItemType Directory -Path $linkRoot,$sourceRoot -Force | Out-Null
    New-TestSkill (Join-Path $linkRoot 'image-skill') 'image-skill' 'Use when identifying images, reading screenshots, or performing image understanding.'
    New-TestSkill (Join-Path $linkRoot 'slides-skill') 'slides-skill' 'Use when creating presentations, slide decks, or PPTX files.'
    New-TestSkill (Join-Path $linkRoot 'document-skill') 'document-skill' 'Use when converting documents and embedding image assets.'
    New-Item -ItemType Directory -Path (Join-Path $linkRoot 'broken-skill') -Force | Out-Null
    $env:CLAUDE_SKILLS_DIR = $sourceRoot
    $env:CLAUDE_SKILLS_LINK_DIR = $linkRoot
    $env:ANTIGRAVITY_SKILLS_DIR = (Join-Path $sandbox 'agy_sources')
    $env:ANTIGRAVITY_SKILLS_LINK_DIR = (Join-Path $sandbox 'agy_links')
    $env:SKILL_MANAGER_CODEX_HOME = (Join-Path $sandbox 'codex-home')
    $env:SKILL_MANAGER_CODEX_USER_HOME = (Join-Path $sandbox 'codex-user')
    $env:SKILL_MANAGER_CODEX_CWD = $sandbox
    $env:SKILL_MANAGER_CODEX_INDEX_PATH = (Join-Path $sandbox 'codex-index.json')

    $refresh = Invoke-Catalog @('-Command', 'refresh')
    Assert-True ($refresh.ExitCode -eq 0) "refresh should succeed: $($refresh.Output)"
    Assert-True (Test-Path -LiteralPath $indexPath -PathType Leaf) 'refresh should create the index'
    $index = Get-Content -Raw -LiteralPath $indexPath | ConvertFrom-Json
    Assert-True (@($index.skills).Count -eq 4) 'index should contain all discovered directories'
    Assert-True ($index.skills[0].usage.status -eq 'unknown') 'usage must be explicit when no host event exists'
    Assert-True (@($index.skills | Where-Object source -eq 'unknown').Count -eq 4) 'unregistered skills must not be mislabeled as local'
    Assert-True (@($index.skills | Where-Object { $_.source_path -match '^[A-Za-z]:\\|^/' -or $_.link_path -match '^[A-Za-z]:\\|^/' }).Count -eq 0) 'index paths must use portable display paths'

    $legacyIndex = $index | ConvertTo-Json -Depth 8 | ConvertFrom-Json
    ($legacyIndex.skills | Where-Object name -eq 'image-skill').source = 'local'
    $legacyIndex | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $indexPath -Encoding utf8
    $legacyRefresh = Invoke-Catalog @('-Command', 'refresh')
    Assert-True ($legacyRefresh.ExitCode -eq 0) 'refresh should repair legacy local provenance'
    $repairedIndex = Get-Content -Raw -LiteralPath $indexPath | ConvertFrom-Json
    Assert-True ((@($repairedIndex.skills | Where-Object name -eq 'image-skill')[0]).source -eq 'unknown') 'legacy local provenance must be reset to unknown'

    $multiDir = Join-Path $linkRoot 'multiline-skill'
    New-Item -ItemType Directory -Path $multiDir -Force | Out-Null
    @('---', 'name: multiline-skill', 'description: >', '  Use when handling multi-line descriptions.', '  This text should remain in the description.', '---', '# Body must not enter the description.') | Set-Content -LiteralPath (Join-Path $multiDir 'SKILL.md') -Encoding utf8
    $multiRefresh = Invoke-Catalog @('-Command', 'refresh')
    Assert-True ($multiRefresh.ExitCode -eq 0) 'multi-line description refresh should succeed'
    $multiIndex = Get-Content -Raw -LiteralPath $indexPath | ConvertFrom-Json
    $multiDescription = (@($multiIndex.skills | Where-Object name -eq 'multiline-skill')[0]).description
    Assert-True ($multiDescription -notmatch '---|# Body') 'description must not include frontmatter close or body text'

    $literalDir = Join-Path $linkRoot 'literal-skill'
    New-Item -ItemType Directory -Path $literalDir -Force | Out-Null
    @('---', 'name: literal-skill', 'description: |', '  Literal descriptions remain searchable.', '  Body text must stay outside.', '---', '# Literal body') | Set-Content -LiteralPath (Join-Path $literalDir 'SKILL.md') -Encoding utf8
    $literalRefresh = Invoke-Catalog @('-Command', 'refresh')
    Assert-True ($literalRefresh.ExitCode -eq 0) 'literal description refresh should succeed'
    $literalIndex = Get-Content -Raw -LiteralPath $indexPath | ConvertFrom-Json
    $literalDescription = (@($literalIndex.skills | Where-Object name -eq 'literal-skill')[0]).description
    Assert-True ($literalDescription -notmatch '---|# Literal body') 'literal description must not include frontmatter close or body text'

    $registered = Invoke-Catalog @('-Command', 'refresh', '-RegisterName', 'image-skill', '-RegisterSource', 'github:owner/repo', '-RegisterInstalledAt', '2026-08-22T00:00:00Z', '-RegisterCommit', ('a' * 40), '-RegisterSha256', ('b' * 64))
    Assert-True ($registered.ExitCode -eq 0) 'installation registration should succeed'
    $registeredIndex = Get-Content -Raw -LiteralPath $indexPath | ConvertFrom-Json
    $registeredEntry = @($registeredIndex.skills | Where-Object name -eq 'image-skill')[0]
    Assert-True ($registeredEntry.source -eq 'github:owner/repo') 'registration should preserve the source repository'
    Assert-True ($registeredEntry.commit -eq ('a' * 40)) 'registration should preserve the resolved commit'

    $find = Invoke-Catalog @('-Command', 'find', '-Query', 'image')
    Assert-True ($find.ExitCode -eq 0 -and $find.Output -match 'image-skill') "find should return image-skill: $($find.Output)"
    $findChinese = Invoke-Catalog @('-Command', 'find', '-Query', '图片识别')
    Assert-True ($findChinese.ExitCode -eq 0 -and $findChinese.Output -match 'image-skill') 'Chinese aliases should find image-skill'
    Assert-True ($findChinese.Output -notmatch 'document-skill') 'Chinese image search should not return document-only skills'

    $show = Invoke-Catalog @('-Command', 'show', '-Name', 'slides-skill')
    Assert-True ($show.ExitCode -eq 0 -and $show.Output -match 'presentations') 'show should display the description'
    Assert-True ($show.Output -match 'usage.*unknown') 'show should not pretend to know invocation state'

    # V3.0 Schema & Capabilities & Manual Scan Verification
    Assert-True ($index.schema_version -eq 3) 'schema_version must be 3'
    $imgEntry = @($index.skills | Where-Object name -eq 'image-skill')[0]
    Assert-True ($null -ne $imgEntry.capabilities -and $imgEntry.capabilities.Count -gt 0) 'capabilities array must exist'
    Assert-True ($null -ne $imgEntry.keywords -and $imgEntry.keywords.Count -gt 0) 'keywords array must exist'
    Assert-True ($imgEntry.category -eq 'media') "image-skill category should be media, got $($imgEntry.category)"
    Assert-True ($null -ne $imgEntry.discovered_at) 'discovered_at timestamp must exist'
    Assert-True ($imgEntry.agents.claude.visible -eq $true) 'agents.claude.visible must be true for linked skill'

    # Manual skill discovery test
    New-TestSkill (Join-Path $sourceRoot 'manual-skill') 'manual-skill' 'Use when testing manual skill placement.'
    $manualRefresh = Invoke-Catalog @('-Command', 'refresh')
    Assert-True ($manualRefresh.ExitCode -eq 0) 'manual skill refresh should succeed'
    $manualIndex = Get-Content -Raw -LiteralPath $indexPath | ConvertFrom-Json
    $manualEntry = @($manualIndex.skills | Where-Object name -eq 'manual-skill')[0]
    Assert-True ($null -ne $manualEntry) 'scan should discover manually added skill in sources directory'
    Assert-True ($manualEntry.source -eq 'unknown') 'manually placed skill source must be unknown'
    Assert-True ($manualEntry.provenance -eq 'unknown') 'manually placed skill provenance must be unknown'
    Assert-True ($null -ne $manualEntry.discovered_at) 'manually placed skill must receive discovered_at timestamp'

    # Capabilities command test
    $capOutput = Invoke-Catalog @('-Command', 'capabilities')
    Assert-True ($capOutput.ExitCode -eq 0) "capabilities command should succeed: $($capOutput.Output)"
    Assert-True ($capOutput.Output -match 'Your Agent currently has \d+ Skills \(\d+ broken\)') 'capabilities should report total and broken count'
    Assert-True ($capOutput.Output -match 'Documents \(\d+\)' -or $capOutput.Output -match 'Media \(\d+\)') 'capabilities should group by categories'
    Assert-True ($capOutput.Output -match 'Broken \(\d+\)') 'capabilities should include Broken category section'
    Assert-True ($capOutput.Output -match 'broken-skill') 'capabilities Broken section should contain broken-skill'

    # Missing skill retention test
    Remove-Item -LiteralPath (Join-Path $linkRoot 'slides-skill') -Recurse -Force
    $missingRefresh = Invoke-Catalog @('-Command', 'refresh')
    Assert-True ($missingRefresh.ExitCode -eq 0) 'refresh after removing skill folder should succeed'
    $missingIndex = Get-Content -Raw -LiteralPath $indexPath | ConvertFrom-Json
    $missingEntry = @($missingIndex.skills | Where-Object name -eq 'slides-skill')[0]
    # V2.1 Enhancements
    New-TestSkill (Join-Path $linkRoot 'frontend-design') 'frontend-design' 'Create high-quality frontend interfaces with web UI layouts and styles.'
    New-TestSkill (Join-Path $linkRoot 'short-skill') 'short-skill' 'Short desc'
    $v21Refresh = Invoke-Catalog @('-Command', 'refresh')
    Assert-True ($v21Refresh.ExitCode -eq 0) 'V2.1 refresh should succeed'

    # 1. Chinese find query
    $findUI = Invoke-Catalog @('-Command', 'find', '-Query', '做网页 UI')
    Assert-True ($findUI.ExitCode -eq 0) "find should succeed: $($findUI.Output)"
    Assert-True ($findUI.Output -match 'frontend-design') 'find for "做网页 UI" should match frontend-design'
    Assert-True ($findUI.Output -match 'score:\s*\d+') 'find output should include score'

    # 2. English image recognition compound AND filtering
    $findImgRecog = Invoke-Catalog @('-Command', 'find', '-Query', 'image recognition')
    Assert-True ($findImgRecog.ExitCode -eq 0) 'find for "image recognition" should succeed'
    Assert-True ($findImgRecog.Output -match 'image-skill') 'find for "image recognition" should match image-skill'
    Assert-True ($findImgRecog.Output -notmatch 'document-skill') 'find for "image recognition" must NOT match document-skill'

    # 3. Empty find query
    $findEmpty = Invoke-Catalog @('-Command', 'find', '-Query', 'nonexistent-skill-query-xyz')
    Assert-True ($findEmpty.ExitCode -eq 0) 'empty find should return code 0'
    Assert-True ($findEmpty.Output -match 'No matching skills for "nonexistent-skill-query-xyz"') 'empty find output must mention the search query'

    # 4. Doctor single skill
    $doctorSingle = Invoke-Catalog @('-Command', 'doctor', '-Name', 'frontend-design')
    Assert-True ($doctorSingle.Output -match 'Installation') 'single doctor output should have Installation block'
    Assert-True ($doctorSingle.Output -match 'Structure') 'single doctor output should have Structure block'
    Assert-True ($doctorSingle.Output -match 'Discovery') 'single doctor output should have Discovery block'
    Assert-True ($doctorSingle.Output -match 'Trigger quality') 'single doctor output should have Trigger quality block'

    # 5. Doctor trigger quality check on short description
    $doctorShort = Invoke-Catalog @('-Command', 'doctor', '-Name', 'short-skill')
    Assert-True ($doctorShort.Output -match 'Description too short') 'doctor on short-skill must flag short description warning'

    # 6. Doctor global output format
    $doctorGlobal = Invoke-Catalog @('-Command', 'doctor')
    Assert-True ($doctorGlobal.Output -match 'doctor: scanned \d+ skills') 'global doctor should report scanned count'
    Assert-True ($doctorGlobal.Output -match 'healthy: \d+') 'global doctor should report healthy count'
    Assert-True ($doctorGlobal.Output -match 'broken: \d+') 'global doctor should report broken count'
    Assert-True ($doctorGlobal.Output -match 'missing: \d+') 'global doctor should report missing count'

    # V2.2 Enhancements
    # 1. fix --dry-run --name frontend-design
    $fixDry = Invoke-Catalog @('-Command', 'fix', '-DryRun', '-Name', 'frontend-design')
    Assert-True ($fixDry.ExitCode -eq 0) 'fix dry-run should succeed'
    Assert-True ($fixDry.Output -match '\[proposed\] frontend-design') 'fix dry-run must contain [proposed] title'
    Assert-True ($fixDry.Output -match 'description \(before\):') 'fix dry-run must contain description (before)'
    Assert-True ($fixDry.Output -match 'description \(after\):') 'fix dry-run must contain description (after)'
    Assert-True ($fixDry.Output -match 'capabilities \(added\):') 'fix dry-run must contain capabilities (added)'
    Assert-True ($fixDry.Output -match 'category \(added\):') 'fix dry-run must contain category (added)'
    Assert-True ($fixDry.Output -match 'backup would go to:') 'fix dry-run must contain backup destination'

    # 2. fix --name frontend-design -Yes
    $fixApply = Invoke-Catalog @('-Command', 'fix', '-Name', 'frontend-design', '-Yes')
    Assert-True ($fixApply.ExitCode -eq 0) 'fix with -Yes should succeed'
    Assert-True ($fixApply.Output -match 'fixed frontend-design:') 'fix apply output should confirm fixed'
    Assert-True ($fixApply.Output -match 'trigger quality:\s*\d+.*\(was \d+') 'fix apply output should show trigger quality improvement'

    $backupItems = @(Get-ChildItem (Join-Path $sourceRoot '.backups') -Filter 'frontend-design-*-SKILL.md')
    Assert-True ($backupItems.Count -ge 1) 'backup file must exist in .backups'

    $fixedFrontendContent = Get-Content -Raw (Join-Path $linkRoot 'frontend-design\SKILL.md')
    Assert-True ($fixedFrontendContent -match 'Use when the user wants to create') 'fixed content must have rewritten description'
    Assert-True ($fixedFrontendContent -match 'capabilities:') 'fixed content must have capabilities'
    Assert-True ($fixedFrontendContent -match 'category:') 'fixed content must have category'

    # 3. fix on short-skill (Case D)
    $fixShort = Invoke-Catalog @('-Command', 'fix', '-Name', 'short-skill', '-Yes')
    Assert-True ($fixShort.Output -match 'description too short') 'fix on short skill should skip and report too short'

    # 4. Description rewrite cases A, B, C, E
    New-TestSkill (Join-Path $linkRoot 'case-a-skill') 'case-a-skill' 'Use when testing case a description already compliant.'
    New-TestSkill (Join-Path $linkRoot 'case-b-skill') 'case-b-skill' 'Build and deploy full-stack web applications with modern architecture, automated CI/CD pipelines, and high-quality frontend styling.'
    New-TestSkill (Join-Path $linkRoot 'case-c-skill') 'case-c-skill' 'This skill should be used when the user needs to transcribe audio recordings.'
    New-TestSkill (Join-Path $linkRoot 'case-e-skill') 'case-e-skill' 'General purpose helper that performs specialized tasks for workflows.'

    $v22Refresh = Invoke-Catalog @('-Command', 'refresh')
    Assert-True ($v22Refresh.ExitCode -eq 0) 'refresh after adding case skills should succeed'

    $fixBatch = Invoke-Catalog @('-Command', 'fix', '-Yes')
    Assert-True ($fixBatch.ExitCode -eq 0) 'batch fix with -Yes should succeed'
    Assert-True ($fixBatch.Output -match 'fixed case-b-skill:') 'batch fix should process case-b-skill'
    Assert-True ($fixBatch.Output -match 'fixed case-c-skill:') 'batch fix should process case-c-skill'

    $fixedCaseC = Get-Content -Raw (Join-Path $linkRoot 'case-c-skill\SKILL.md')
    Assert-True ($fixedCaseC -match 'Use when the user needs to transcribe audio recordings') 'case c should be rewritten cleanly'

    $fixedCaseB = Get-Content -Raw (Join-Path $linkRoot 'case-b-skill\SKILL.md')
    Assert-True ($fixedCaseB -match 'Use when the user wants to build and deploy') 'case b should be rewritten with base verb'

    # 5. Doctor verification after fix
    $doctorAfter = Invoke-Catalog @('-Command', 'doctor', '-Name', 'case-b-skill')
    Assert-True ($doctorAfter.Output -match 'Trigger description looks Claude-discoverable') 'fixed skill should be Claude-discoverable'

    # 6. V3.0 Multi-Agent Tests
    # A. Default agent claude
    $capsClaude = Invoke-Catalog @('-Command', 'capabilities', '-Agent', 'claude')
    Assert-True ($capsClaude.Output -match 'Development') 'agent claude should see development category'

    # B. Stub agent codex in capabilities
    $capsCodex = Invoke-Catalog @('-Command', 'capabilities', '-Agent', 'codex')
    Assert-True ($capsCodex.Output -match "No visible skills for agent 'codex'") 'agent codex should report 0 visible skills'

    # C. Isolated Codex roots remain empty even with all-agents requested.
    $capsAll = Invoke-Catalog @('-Command', 'capabilities', '-Agent', 'codex', '-AllAgents')
    Assert-True ($capsAll.Output -notmatch 'Development') 'isolated Codex catalog must not borrow Claude entries'

    # D. CLAUDE_SKILLS_AGENT=codex environment variable
    $oldAgentVar = $env:CLAUDE_SKILLS_AGENT
    try {
        $env:CLAUDE_SKILLS_AGENT = 'codex'
        $capsCodexEnv = Invoke-Catalog @('-Command', 'capabilities')
        Assert-True ($capsCodexEnv.Output -match "No visible skills for agent 'codex'") 'env CLAUDE_SKILLS_AGENT=codex should report 0 visible skills'
    } finally {
        $env:CLAUDE_SKILLS_AGENT = $oldAgentVar
    }

    # E. Show command displays per-agent visibility
    $showOut = Invoke-Catalog @('-Command', 'show', '-Name', 'case-b-skill')
    Assert-True ($showOut.Output -match 'agents\.claude\.visible:\s*True') 'show should output claude visible'
    Assert-True ($showOut.Output -match 'agents\.codex\.visible:\s*False') 'show should output codex visible false'
    Assert-True ($showOut.Output -match 'agents\.antigravity\.visible:\s*False') 'show should output antigravity visible false'

    # F. Schema v3 migration from legacy v2 JSON
    $legacyJson = @'
{
  "schema_version": 2,
  "generated_at": "2026-08-23T00:00:00Z",
  "skills": [
    {
      "name": "legacy-skill",
      "install_name": "legacy-skill",
      "description": "Legacy test skill",
      "status": "ok",
      "health": "ok"
    }
  ]
}
'@
    Set-Content -LiteralPath (Join-Path $sourceRoot 'installed-skills-index.json') -Value $legacyJson -Encoding UTF8
    $migratedShow = Invoke-Catalog @('-Command', 'show', '-Name', 'legacy-skill')
    Assert-True ($migratedShow.Output -match 'agents\.claude\.visible:\s*True') 'migrated v2 index should have claude visible'
    Assert-True ($migratedShow.Output -match 'agents\.codex\.visible:\s*False') 'migrated v2 index should have codex visible'

    # 7. V3.1 Find & Match Reason Tests
    New-TestSkill (Join-Path $linkRoot 'slides-skill') 'slides-skill' 'Use when creating presentations and slide decks.'
    $v31Refresh = Invoke-Catalog @('-Command', 'refresh')
    Assert-True ($v31Refresh.ExitCode -eq 0) 'refresh before find tests should succeed'

    # A. Match reason line presence
    $findReason = Invoke-Catalog @('-Command', 'find', '-Query', 'image', '-Limit', '2')
    Assert-True ($findReason.Output -match 'matched:') 'find output should contain matched: line'

    # B. Chinese query synonym expansion (PPT -> slides-skill)
    $findPpt = Invoke-Catalog @('-Command', 'find', '-Query', 'PPT', '-Limit', '2')
    Assert-True ($findPpt.Output -match 'slides-skill') 'Chinese query PPT should find slides-skill'

    # C. Compound AND filtering (image recognition does not match document)
    $findCompound = Invoke-Catalog @('-Command', 'find', '-Query', 'image recognition')
    Assert-True ($findCompound.Output -match 'image-skill') 'compound query image recognition should find image-skill'
    Assert-True ($findCompound.Output -notmatch 'document-skill') 'compound query image recognition must not match document-skill'

    Write-Output 'PASS: catalog regression tests'
}
finally {
    $env:CLAUDE_SKILLS_DIR = $oldSkillsDir
    $env:CLAUDE_SKILLS_LINK_DIR = $oldLinkDir
    $env:SKILL_MANAGER_CODEX_HOME = $oldCodexHome
    $env:SKILL_MANAGER_CODEX_USER_HOME = $oldCodexUserHome
    $env:SKILL_MANAGER_CODEX_CWD = $oldCodexCwd
    $env:SKILL_MANAGER_CODEX_INDEX_PATH = $oldCodexIndex
    if (Test-Path -LiteralPath $sandbox) { Remove-Item -LiteralPath $sandbox -Recurse -Force }
}
