[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Resolve-Path (Join-Path $PSScriptRoot '..')
$queriesPath = Join-Path $root 'tests\fixtures\find-benchmark\queries.json'

if (-not (Test-Path -LiteralPath $queriesPath)) {
    throw "Queries fixture not found: $queriesPath"
}

$queries = Get-Content -LiteralPath $queriesPath -Raw -Encoding UTF8 | ConvertFrom-Json
$total = $queries.Count
$top1Hit = 0
$top3Hit = 0
$failed = [System.Collections.Generic.List[string]]::new()

foreach ($q in $queries) {
    $qid = $q.id
    $query = $q.query
    $gold1 = $q.gold_top1
    $gold3 = if ($q.gold_top3) { @($q.gold_top3) } else { @() }

    $catalogScript = Join-Path $root 'lib\catalog.ps1'
    $output = & pwsh -NoProfile -File $catalogScript -Command find -Query $query -Limit 3 2>&1 | Out-String

    $top1 = $null
    $top2 = $null
    $top3 = $null

    if ($output -match '(?m)^\s*1\.\s+([^\s]+)') { $top1 = $Matches[1] }
    if ($output -match '(?m)^\s*2\.\s+([^\s]+)') { $top2 = $Matches[1] }
    if ($output -match '(?m)^\s*3\.\s+([^\s]+)') { $top3 = $Matches[1] }

    $isTop1 = $false
    $isTop3 = $false

    if ($null -eq $gold1) {
        if ($output -match 'No matching skills' -or [string]::IsNullOrEmpty($top1)) {
            $isTop1 = $true
            $isTop3 = $true
        }
    } else {
        if ($top1 -eq $gold1) {
            $isTop1 = $true
        }
        if ($top1 -eq $gold1 -or $top2 -eq $gold1 -or $top3 -eq $gold1 -or ($gold3 -contains $top1)) {
            $isTop3 = $true
        }
    }

    if ($isTop1) { $top1Hit++ }
    if ($isTop3) { $top3Hit++ }
    else {
        $failed.Add("[$qid] '$query' (expected: $gold1, got top1: '$top1', top2: '$top2', top3: '$top3')")
    }
}

$top1Pct = [math]::Round(($top1Hit * 100.0) / $total)
$top3Pct = [math]::Round(($top3Hit * 100.0) / $total)

Write-Host "=========================================="
Write-Host "Find Benchmark Results (PowerShell)"
Write-Host "=========================================="
Write-Host "Total Queries: $total"
Write-Host "Top-1 Hits: $top1Hit / $total ($top1Pct%) [target >= 85%]"
Write-Host "Top-3 Hits: $top3Hit / $total ($top3Pct%) [target >= 95%]"
Write-Host "=========================================="

if ($failed.Count -gt 0) {
    Write-Host "--- Failed queries ($($failed.Count)) ---"
    foreach ($f in $failed) {
        Write-Host " - $f"
    }
    Write-Host ""
}

if ($top1Pct -lt 85) {
    throw "FAIL: Top-1 accuracy $top1Pct% is below 85% target"
}

if ($top3Pct -lt 95) {
    throw "FAIL: Top-3 accuracy $top3Pct% is below 95% target"
}

Write-Host "PASS: Find benchmark passed all criteria"
