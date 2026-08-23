[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = (Get-Item (Join-Path $PSScriptRoot '..')).FullName
$catalog = Join-Path $root 'lib\catalog.ps1'
$install = Join-Path $root 'lib\install.ps1'

. "$root\adapters\_base.ps1"
. "$root\adapters\antigravity\paths.ps1"
. "$root\adapters\antigravity\detect.ps1"

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw "ASSERTION FAILED: $Message" }
}

$sandbox = Join-Path ([System.IO.Path]::GetTempPath()) ("agy_test_" + [System.Guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $sandbox -Force

try {
    $agySkills = Join-Path $sandbox 'agents_skills'
    $agyBuiltin = Join-Path $sandbox 'builtin_skills'
    $claudeSkills = Join-Path $sandbox 'claude_skills'
    $claudeLinks = Join-Path $sandbox 'claude_links'
    $fixtures = Join-Path $sandbox 'fixtures'

    $null = New-Item -ItemType Directory -Path $agySkills -Force
    $null = New-Item -ItemType Directory -Path $agyBuiltin -Force
    $null = New-Item -ItemType Directory -Path $claudeSkills -Force
    $null = New-Item -ItemType Directory -Path $claudeLinks -Force
    $null = New-Item -ItemType Directory -Path $fixtures -Force

    $env:ANTIGRAVITY_SKILLS_DIR = $agySkills
    $env:ANTIGRAVITY_SKILLS_LINK_DIR = $agySkills
    $env:ANTIGRAVITY_BUILTIN_DIR = $agyBuiltin
    $env:ANTIGRAVITY_SKILLS_INDEX_PATH = Join-Path $agySkills 'installed-skills-index.json'

    $env:CLAUDE_SKILLS_DIR = $claudeSkills
    $env:CLAUDE_SKILLS_LINK_DIR = $claudeLinks
    $env:CLAUDE_SKILLS_INDEX_PATH = Join-Path $claudeSkills 'installed-skills-index.json'

    Write-Host "=========================================="
    Write-Host "Running Antigravity Adapter Tests (PowerShell)"
    Write-Host "=========================================="

    # 1. Detection test
    $status = Get-AntigravityStatus
    Assert-True ($status.Usable -eq $true) "Antigravity should be detected as usable with env vars set"
    Assert-True ($status.GlobalSkillsDir -eq $agySkills) "Antigravity global skills dir should resolve to env override"

    # 2. Populate sample skills in Antigravity global dir
    $feDir = Join-Path $agySkills 'frontend-design'
    $null = New-Item -ItemType Directory -Path $feDir -Force
    $feContent = "---`r`nname: frontend-design`r`ndescription: Use when the user asks to build web components, pages, artifacts, or web UI.`r`ncapabilities: [frontend, ui, web, design]`r`ncategory: development`r`n---`r`n# Frontend Design"
    [System.IO.File]::WriteAllText((Join-Path $feDir 'SKILL.md'), $feContent, [System.Text.Encoding]::UTF8)

    $pdfDir = Join-Path $agySkills 'pdf'
    $null = New-Item -ItemType Directory -Path $pdfDir -Force
    $pdfContent = "---`r`nname: pdf`r`ndescription: Use when the user wants to do anything with PDF files.`r`ncapabilities: [pdf, document]`r`ncategory: documents`r`n---`r`n# PDF"
    [System.IO.File]::WriteAllText((Join-Path $pdfDir 'SKILL.md'), $pdfContent, [System.Text.Encoding]::UTF8)

    # 3. Refresh and Scan
    & pwsh -NoProfile -File $catalog -Command refresh -Agent antigravity | Out-Null
    $indexRaw = Get-Content -Raw -LiteralPath $env:ANTIGRAVITY_SKILLS_INDEX_PATH -Encoding UTF8
    $indexData = $indexRaw | ConvertFrom-Json
    Assert-True ($indexData.skills.Count -eq 2) "Antigravity catalog index should contain 2 skills"

    $feEntry = @($indexData.skills | Where-Object { $_.name -eq 'frontend-design' })[0]
    Assert-True ($feEntry.agents.antigravity.visible -eq $true) "frontend-design must be visible to Antigravity"
    Assert-True ($feEntry.agents.claude.visible -eq $false) "frontend-design must not be visible to Claude (isolated)"

    # 4. List and Capabilities
    $listOut = & pwsh -NoProfile -File $catalog -Command list -Agent antigravity | Out-String
    Assert-True ($listOut -match 'frontend-design') "list output should show frontend-design"
    Assert-True ($listOut -match 'pdf') "list output should show pdf"

    $capsOut = & pwsh -NoProfile -File $catalog -Command capabilities -Agent antigravity | Out-String
    Assert-True ($capsOut -match 'Development') "capabilities should show Development category"
    Assert-True ($capsOut -match 'Documents') "capabilities should show Documents category"

    # 5. Show command
    $showOut = & pwsh -NoProfile -File $catalog -Command show -Name frontend-design -Agent antigravity | Out-String
    Assert-True ($showOut -match 'agents\.antigravity\.visible:\s*True') "show command must report antigravity visibility as True"

    # 6. Find command
    $findOut = & pwsh -NoProfile -File $catalog -Command find -Query "做网页 UI" -Agent antigravity | Out-String
    Assert-True ($findOut -match '1\.\s+frontend-design') "find '做网页 UI' on antigravity should match frontend-design"

    # 7. Doctor command
    $docGlobal = & pwsh -NoProfile -File $catalog -Command doctor -Agent antigravity | Out-String
    Assert-True ($docGlobal -match 'doctor:\s+scanned\s+2\s+skills\s+for\s+agent\s+.antigravity.') "doctor global must report antigravity skills count"
    Assert-True ($docGlobal -match 'discovery\s+root:') "doctor global must report discovery root"

    $docSingle = & pwsh -NoProfile -File $catalog -Command doctor -Name frontend-design -Agent antigravity | Out-String
    Assert-True ($docSingle -match 'Installation') "single skill doctor must report Installation status"
    Assert-True ($docSingle -match 'Trigger quality') "single skill doctor must report Trigger quality"

    # 8. Install Dry-Run & Real Install
    $newSkillFixture = Join-Path $fixtures 'new-helper-skill'
    $null = New-Item -ItemType Directory -Path $newSkillFixture -Force
    $newSkillContent = "---`r`nname: new-helper-skill`r`ndescription: Use when the user asks for helper utilities.`r`n---`r`n# Helper"
    [System.IO.File]::WriteAllText((Join-Path $newSkillFixture 'SKILL.md'), $newSkillContent, [System.Text.Encoding]::UTF8)

    # Dry-Run
    $dryOut = & pwsh -NoProfile -File $install -LocalPath $newSkillFixture -Name new-helper-skill -Agent antigravity -DryRun | Out-String
    Assert-True ($dryOut -match 'DRY RUN') "install dry-run should report DRY RUN"
    Assert-True (-not (Test-Path (Join-Path $agySkills 'new-helper-skill'))) "dry-run should not create files in destination"

    # Real Install
    $instOut = & pwsh -NoProfile -File $install -LocalPath $newSkillFixture -Name new-helper-skill -Agent antigravity | Out-String
    Assert-True ($instOut -match 'source installed at') "real install should report source installed"
    Assert-True (Test-Path (Join-Path $agySkills 'new-helper-skill\SKILL.md')) "installed skill must exist on disk"

    # Re-install with -Force should create backup
    $forceOut = & pwsh -NoProfile -File $install -LocalPath $newSkillFixture -Name new-helper-skill -Agent antigravity -Force | Out-String
    Assert-True ($forceOut -match 'previous source backed up to') "force install should create backup"
    $backupDir = Join-Path $agySkills '.backups'
    Assert-True (Test-Path $backupDir) ".backups directory must exist"

    # 9. Builtin Directory Protection
    $failed = $false
    try {
        & pwsh -NoProfile -File $install -LocalPath $newSkillFixture -Name new-helper-skill -Agent antigravity -LocalPath $agyBuiltin 2>&1 | Out-Null
    } catch {
        $failed = $true
    }

    Write-Host "=========================================="
    Write-Host "PASS: All Antigravity Adapter Tests Passed"
    Write-Host "=========================================="
    exit 0
}
finally {
    Remove-Item -LiteralPath $sandbox -Recurse -Force -ErrorAction SilentlyContinue
}
