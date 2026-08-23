[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = (Get-Item (Join-Path $PSScriptRoot '..')).FullName
$queriesPath = Join-Path $root 'tests\fixtures\find-benchmark\queries.json'
$fixturePath = Join-Path $root 'tests\fixtures\find-benchmark\skills_fixture.json'

$sandbox = Join-Path ([System.IO.Path]::GetTempPath()) ("find-bench-" + [System.Guid]::NewGuid().ToString('N'))
$linkRoot = Join-Path $sandbox 'links'
$sourceRoot = Join-Path $sandbox 'sources'

try {
    New-Item -ItemType Directory -Path $linkRoot, $sourceRoot -Force | Out-Null
    $oldSkillsDir = $env:CLAUDE_SKILLS_DIR
    $oldLinkDir = $env:CLAUDE_SKILLS_LINK_DIR
    $env:CLAUDE_SKILLS_DIR = $sourceRoot
    $env:CLAUDE_SKILLS_LINK_DIR = $linkRoot

    $fixtureJson = Get-Content -Raw -LiteralPath $fixturePath -Encoding UTF8 | ConvertFrom-Json
    foreach ($s in $fixtureJson) {
        $sdir = Join-Path $linkRoot $s.name
        New-Item -ItemType Directory -Path $sdir -Force | Out-Null
        $content = "---`n" + $s.frontmatter + "`n---`n# " + $s.name
        Set-Content -LiteralPath (Join-Path $sdir 'SKILL.md') -Value $content -Encoding UTF8
    }

    & pwsh -NoProfile -File (Join-Path $root 'lib\catalog.ps1') -Command refresh | Out-Null

    $queries = Get-Content -Raw -LiteralPath $queriesPath -Encoding UTF8 | ConvertFrom-Json

    $totalQueries = $queries.Count
    $top1Hits = 0
    $top3Hits = 0
    $failedQueries = [System.Collections.Generic.List[string]]::new()

    foreach ($q in $queries) {
        $qid = $q.id
        $queryText = $q.query
        $gold1 = $q.gold_top1
        $gold3 = if ($q.gold_top3) { @($q.gold_top3) } else { @() }

        $res = & pwsh -NoProfile -File (Join-Path $root 'lib\catalog.ps1') -Command find -Query $queryText -Limit 3 2>&1
        $resText = ($res -join "`n")

        $top1 = ''
        $top2 = ''
        $top3 = ''

        $lines = $resText -split "`r?`n"
        foreach ($line in $lines) {
            $m1 = [regex]::Match($line, '^\s*1\.\s+([^\s]+)')
            if ($m1.Success -and -not $top1) { $top1 = $m1.Groups[1].Value; continue }
            $m2 = [regex]::Match($line, '^\s*2\.\s+([^\s]+)')
            if ($m2.Success -and -not $top2) { $top2 = $m2.Groups[1].Value; continue }
            $m3 = [regex]::Match($line, '^\s*3\.\s+([^\s]+)')
            if ($m3.Success -and -not $top3) { $top3 = $m3.Groups[1].Value; continue }
        }

        $isTop1 = $false
        $isTop3 = $false

        if ($null -eq $gold1 -or $gold1 -eq '' -or $gold1 -eq 'none') {
            if (-not $top1 -or $resText -match 'No matching skills') {
                $isTop1 = $true
                $isTop3 = $true
            }
        } else {
            if ($top1 -eq $gold1) {
                $isTop1 = $true
            }
            $candidates = @($top1, $top2, $top3) | Where-Object { $_ }
            foreach ($cand in $candidates) {
                if ($cand -eq $gold1 -or $gold3 -contains $cand) {
                    $isTop3 = $true
                    break
                }
            }
        }

        if ($isTop1) { $top1Hits++ }
        if ($isTop3) { $top3Hits++ }
        else {
            $failedQueries.Add("[$qid] '$queryText' (expected: $gold1, got top1: '$top1', top2: '$top2', top3: '$top3')")
        }
    }

    $top1Pct = [math]::Round(($top1Hits / $totalQueries) * 100)
    $top3Pct = [math]::Round(($top3Hits / $totalQueries) * 100)

    Write-Host "=========================================="
    Write-Host "Find Benchmark Results (PowerShell)"
    Write-Host "=========================================="
    Write-Host "Total Queries: $totalQueries"
    Write-Host "Top-1 Hits: $top1Hits / $totalQueries ($top1Pct%) [target >= 85%]"
    Write-Host "Top-3 Hits: $top3Hits / $totalQueries ($top3Pct%) [target >= 95%]"
    Write-Host "=========================================="

    if ($failedQueries.Count -gt 0) {
        Write-Host "--- Failed queries ($($failedQueries.Count)) ---"
        foreach ($f in $failedQueries) {
            Write-Host " - $f"
        }
        Write-Host ""
    }

    if ($top1Pct -lt 85) {
        Write-Error "FAIL: Top-1 accuracy $top1Pct% is below 85% target"
        exit 1
    }

    if ($top3Pct -lt 95) {
        Write-Error "FAIL: Top-3 accuracy $top3Pct% is below 95% target"
        exit 1
    }

    Write-Host "PASS: Find benchmark passed all criteria"
} finally {
    $env:CLAUDE_SKILLS_DIR = $oldSkillsDir
    $env:CLAUDE_SKILLS_LINK_DIR = $oldLinkDir
    if (Test-Path -LiteralPath $sandbox) { Remove-Item -LiteralPath $sandbox -Recurse -Force }
}
