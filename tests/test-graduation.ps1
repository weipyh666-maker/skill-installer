[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = (Get-Item (Join-Path $PSScriptRoot '..')).FullName
$catalog = Join-Path $root 'lib\catalog.ps1'
$fixture = Join-Path $root 'tests\fixtures\find-benchmark\skills_fixture.json'

$sandbox = Join-Path ([System.IO.Path]::GetTempPath()) ("grad_test_" + [System.Guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $sandbox -Force

try {
    $sourcesDir = Join-Path $sandbox 'sources'
    $linksDir = Join-Path $sandbox 'links'
    $null = New-Item -ItemType Directory -Path $sourcesDir -Force
    $null = New-Item -ItemType Directory -Path $linksDir -Force

    $env:CLAUDE_SKILLS_DIR = $sourcesDir
    $env:CLAUDE_SKILLS_LINK_DIR = $linksDir
    $env:CLAUDE_SKILLS_INDEX_PATH = Join-Path $sourcesDir 'installed-skills-index.json'

    # Populate fixture skills with proper newlines
    $fixtureData = Get-Content -Raw -LiteralPath $fixture -Encoding UTF8 | ConvertFrom-Json
    foreach ($s in $fixtureData) {
        $sDir = Join-Path $linksDir $s.name
        $null = New-Item -ItemType Directory -Path $sDir -Force
        $skillContent = "---`r`n" + $s.frontmatter + "`r`n---`r`n# " + $s.name
        [System.IO.File]::WriteAllText((Join-Path $sDir 'SKILL.md'), $skillContent, [System.Text.Encoding]::UTF8)
    }

    $smDir = Join-Path $linksDir 'skill-manager'
    $null = New-Item -ItemType Directory -Path $smDir -Force
    Copy-Item -Path (Join-Path $root 'SKILL.md') -Destination (Join-Path $smDir 'SKILL.md') -Force

    $passCount = 0
    $failCount = 0

    Write-Host "================================="
    Write-Host "Claude 1.0 Graduation Test"
    Write-Host "================================="

    # [A] scan finds manually-installed skills
    $manualDir = Join-Path $linksDir 'manual-test-skill'
    $null = New-Item -ItemType Directory -Path $manualDir -Force
    $manualContent = "---`r`nname: manual-test-skill`r`ndescription: Use when testing manual installation detection.`r`ncapabilities: [manual, test]`r`ncategory: other`r`n---`r`n# manual"
    [System.IO.File]::WriteAllText((Join-Path $manualDir 'SKILL.md'), $manualContent, [System.Text.Encoding]::UTF8)

    & pwsh -NoProfile -File $catalog -Command refresh | Out-Null
    $idxRaw = Get-Content -Raw -LiteralPath $env:CLAUDE_SKILLS_INDEX_PATH -Encoding UTF8
    if ($idxRaw -match 'manual-test-skill') {
        Write-Host "[A] scan finds manually-installed skills        ✓ PASS"
        $passCount++
    } else {
        Write-Host "[A] scan finds manually-installed skills        ✗ FAIL"
        $failCount++
    }

    # [B] catalog is complete
    $outList = & pwsh -NoProfile -File $catalog -Command list | Out-String
    $outShow = & pwsh -NoProfile -File $catalog -Command show -Name manual-test-skill | Out-String
    if ($outList.Trim().Length -gt 0 -and $outShow -match 'name:' -and $outShow -match 'description:' -and $outShow -match 'capabilities:' -and $outShow -match 'category:') {
        Write-Host "[B] catalog is complete                        ✓ PASS"
        $passCount++
    } else {
        Write-Host "[B] catalog is complete                        ✗ FAIL"
        $failCount++
    }

    # [C] capabilities categorized reasonably
    $outCaps = & pwsh -NoProfile -File $catalog -Command capabilities | Out-String
    $catMatches = [regex]::Matches($outCaps, '(?m)^[A-Z][a-z]+\s+\(\d+\)')
    if ($catMatches.Count -ge 4) {
        Write-Host "[C] capabilities categorized reasonably        ✓ PASS"
        $passCount++
    } else {
        Write-Host "[C] capabilities categorized reasonably        ✗ FAIL"
        $failCount++
    }

    # [D] refresh is stable (deterministic)
    & pwsh -NoProfile -File $catalog -Command refresh | Out-Null
    $skillsJson1 = ((Get-Content -Raw -LiteralPath $env:CLAUDE_SKILLS_INDEX_PATH -Encoding UTF8 | ConvertFrom-Json).skills | ConvertTo-Json -Depth 10)
    $hash1 = [System.BitConverter]::ToString([System.Security.Cryptography.SHA256]::Create().ComputeHash([System.Text.Encoding]::UTF8.GetBytes($skillsJson1)))

    & pwsh -NoProfile -File $catalog -Command refresh | Out-Null
    $skillsJson2 = ((Get-Content -Raw -LiteralPath $env:CLAUDE_SKILLS_INDEX_PATH -Encoding UTF8 | ConvertFrom-Json).skills | ConvertTo-Json -Depth 10)
    $hash2 = [System.BitConverter]::ToString([System.Security.Cryptography.SHA256]::Create().ComputeHash([System.Text.Encoding]::UTF8.GetBytes($skillsJson2)))

    if ($hash1 -eq $hash2) {
        Write-Host "[D] refresh is stable (deterministic)          ✓ PASS"
        $passCount++
    } else {
        Write-Host "[D] refresh is stable (deterministic)          ✗ FAIL"
        $failCount++
    }

    # [E] find supports natural language queries
    $outFind1 = & pwsh -NoProfile -File $catalog -Command find -Query "我装了哪些 Skill" | Out-String
    $outFind2 = & pwsh -NoProfile -File $catalog -Command find -Query "find a skill that handles PDFs" | Out-String
    if ($outFind1 -match '1\.' -and $outFind2 -match '1\.') {
        Write-Host "[E] find supports natural language queries     ✓ PASS"
        $passCount++
    } else {
        Write-Host "[E] find supports natural language queries     ✗ FAIL"
        $failCount++
    }

    # [F] Top-1 >= 85% / Top-3 >= 95%
    $outBm = & pwsh -NoProfile -File (Join-Path $root 'tests\test-find-benchmark.ps1') | Out-String
    $top1Match = [regex]::Match($outBm, 'Top-1 Hits: \d+ / \d+ \((\d+)%\)')
    $top3Match = [regex]::Match($outBm, 'Top-3 Hits: \d+ / \d+ \((\d+)%\)')
    $top1Val = if ($top1Match.Success) { [int]$top1Match.Groups[1].Value } else { 0 }
    $top3Val = if ($top3Match.Success) { [int]$top3Match.Groups[1].Value } else { 0 }
    if ($top1Val -ge 85 -and $top3Val -ge 95) {
        Write-Host "[F] Top-1 ≥ 85% / Top-3 ≥ 95%                  ✓ PASS ($($top1Val)% / $($top3Val)%)"
        $passCount++
    } else {
        Write-Host "[F] Top-1 ≥ 85% / Top-3 ≥ 95%                  ✗ FAIL"
        $failCount++
    }

    # [G] find returns match reason
    $outReason = & pwsh -NoProfile -File $catalog -Command find -Query "PPT" | Out-String
    if ($outReason -match 'matched:') {
        Write-Host "[G] find returns match reason                  ✓ PASS"
        $passCount++
    } else {
        Write-Host "[G] find returns match reason                  ✗ FAIL"
        $failCount++
    }

    # [H] doctor diagnoses common issues
    $outDoc = & pwsh -NoProfile -File $catalog -Command doctor -Name manual-test-skill | Out-String
    if ($outDoc -match 'Installation' -and $outDoc -match 'Structure' -and $outDoc -match 'Discovery' -and $outDoc -match 'Trigger quality') {
        Write-Host "[H] doctor diagnoses common issues             ✓ PASS"
        $passCount++
    } else {
        Write-Host "[H] doctor diagnoses common issues             ✗ FAIL"
        $failCount++
    }

    # [I] fix handles security issues
    $sensDir = Join-Path $linksDir 'sensitive-test-skill'
    $null = New-Item -ItemType Directory -Path $sensDir -Force
    $sensContent = "---`r`nname: sensitive-test-skill`r`ndescription: Use when testing sensitive rejection.`r`n---`r`n# sensitive"
    [System.IO.File]::WriteAllText((Join-Path $sensDir 'SKILL.md'), $sensContent, [System.Text.Encoding]::UTF8)
    [System.IO.File]::WriteAllText((Join-Path $sensDir '.env'), "SECRET=123", [System.Text.Encoding]::UTF8)
    & pwsh -NoProfile -File $catalog -Command refresh | Out-Null
    $outSec = & pwsh -NoProfile -File $catalog -Command fix -Name sensitive-test-skill -Yes 2>&1 | Out-String
    if ($outSec -match 'refusing to copy sensitive file' -or $outSec -match 'Refusing to copy sensitive') {
        Write-Host "[I] fix handles security issues                ✓ PASS"
        $passCount++
    } else {
        Write-Host "[I] fix handles security issues                ✗ FAIL"
        $failCount++
    }

    # [J] skill-manager triggers on intent
    $outAt = & pwsh -NoProfile -File (Join-Path $root 'tests\test-auto-trigger.ps1') | Out-String
    $posMatch = [regex]::Match($outAt, 'Positive Cases: \d+ / \d+ \((\d+)%\)')
    $posVal = if ($posMatch.Success) { [int]$posMatch.Groups[1].Value } else { 0 }
    if ($posVal -ge 83) {
        Write-Host "[J] skill-manager triggers on intent           ✓ PASS ($($posVal)%)"
        $passCount++
    } else {
        Write-Host "[J] skill-manager triggers on intent           ✗ FAIL"
        $failCount++
    }

    # [K] skill-manager avoids false triggers
    $negMatch = [regex]::Match($outAt, 'Negative Cases: \d+ / \d+ \((\d+)%\)')
    $negVal = if ($negMatch.Success) { [int]$negMatch.Groups[1].Value } else { 0 }
    if ($negVal -ge 90) {
        Write-Host "[K] skill-manager avoids false triggers        ✓ PASS ($($negVal)%)"
        $passCount++
    } else {
        Write-Host "[K] skill-manager avoids false triggers        ✗ FAIL"
        $failCount++
    }

    Write-Host "================================="
    if ($failCount -eq 0 -and $passCount -eq 11) {
        Write-Host "Result: 11 / 11 PASS — Claude 1.0 GRADUATED"
        exit 0
    } else {
        Write-Host "Result: $passCount / 11 PASS ($failCount FAILED) — NOT GRADUATED"
        exit 1
    }
}
finally {
    Remove-Item -LiteralPath $sandbox -Recurse -Force -ErrorAction SilentlyContinue
}
