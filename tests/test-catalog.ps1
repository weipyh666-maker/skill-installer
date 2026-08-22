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
try {
    New-Item -ItemType Directory -Path $linkRoot,$sourceRoot -Force | Out-Null
    New-TestSkill (Join-Path $linkRoot 'image-skill') 'image-skill' 'Use when identifying images, reading screenshots, or performing image understanding.'
    New-TestSkill (Join-Path $linkRoot 'slides-skill') 'slides-skill' 'Use when creating presentations, slide decks, or PPTX files.'
    New-TestSkill (Join-Path $linkRoot 'document-skill') 'document-skill' 'Use when converting documents and embedding image assets.'
    New-Item -ItemType Directory -Path (Join-Path $linkRoot 'broken-skill') -Force | Out-Null
    $env:CLAUDE_SKILLS_DIR = $sourceRoot
    $env:CLAUDE_SKILLS_LINK_DIR = $linkRoot

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

    $doctor = Invoke-Catalog @('-Command', 'doctor')
    Assert-True ($doctor.ExitCode -ne 0 -and $doctor.Output -match 'broken:.*broken-skill') "doctor should identify the broken skill: $($doctor.Output)"

    Write-Output 'PASS: catalog regression tests'
}
finally {
    $env:CLAUDE_SKILLS_DIR = $oldSkillsDir
    $env:CLAUDE_SKILLS_LINK_DIR = $oldLinkDir
    if (Test-Path -LiteralPath $sandbox) { Remove-Item -LiteralPath $sandbox -Recurse -Force }
}
