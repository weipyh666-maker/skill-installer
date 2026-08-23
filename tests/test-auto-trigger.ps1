[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = (Get-Item (Join-Path $PSScriptRoot '..')).FullName
$posFile = Join-Path $root 'tests\fixtures\auto-trigger\queries-pos.json'
$negFile = Join-Path $root 'tests\fixtures\auto-trigger\queries-neg.json'
$skillMdFile = Join-Path $root 'SKILL.md'

$posQueries = Get-Content -Raw -LiteralPath $posFile -Encoding UTF8 | ConvertFrom-Json
$negQueries = Get-Content -Raw -LiteralPath $negFile -Encoding UTF8 | ConvertFrom-Json
$skillMd = Get-Content -Raw -LiteralPath $skillMdFile -Encoding UTF8

$desc = ''
if ($skillMd -match '(?ms)^---\s*\r?\n(.*?)\r?\n---(?:\s*\r?\n|$)') {
    $fm = $Matches[1]
    foreach ($line in ($fm -split "`r?`n")) {
        if ($line -match '^description:\s*(.*)$') {
            $desc = $Matches[1].Trim()
            break
        }
    }
}

$stopWords = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
@(
    'a', 'an', 'the', 'in', 'on', 'at', 'to', 'for', 'of', 'and', 'or', 'is', 'are', 'with',
    'by', 'that', 'this', 'from', 'as', 'it', 'its', 'be', 'can', 'do', 'does', 'did', 'have',
    'has', 'had', 'will', 'would', 'shall', 'should', 'may', 'might', 'must', 'what', 'which',
    'how', 'who', 'whom', 'where', 'when', 'why', 'there', 'their', 'them', 'they', 'i', 'me',
    'my', 'we', 'us', 'our', 'you', 'your', 'he', 'him', 'his', 'she', 'her',
    '我', '你', '他', '她', '它', '我们', '你们', '他们', '的', '了', '在', '是', '有', '和', '就',
    '不', '人', '都', '一', '一个', '上', '也', '很', '到', '说', '要', '去', '会', '着',
    '没有', '看', '好', '自己', '这', '个', '帮我', '一下', '那个', '叫什么', '是不是', '哪些',
    '怎么', '这个', '为什么', '所有', '出来', '句', '成', '一封', '今天', '怎么样', '想', '听个'
) | ForEach-Object { $null = $stopWords.Add($_) }

$aliases = [ordered]@{
    '装了' = @('installed', 'install', '装了')
    '装过' = @('installed', 'previously-installed', 'install', '装过')
    '能力' = @('capabilities', 'capability', 'can do', '能力')
    '列出' = @('list', 'catalog', 'summary', '列出')
    '列出来' = @('list', 'catalog', 'summary', '列出来')
    '找' = @('find', 'searches', 'search', '找')
    '找一下' = @('find', 'searches', 'search', '找一下')
    '忘记' = @('cannot recall', 'forgot', '忘记')
    '自动调用' = @('triggered automatically', 'auto-discover', '自动调用')
    '没自动调用' = @('not being triggered automatically', 'triggered automatically', '没自动调用')
    '哪个' = @('which', '哪个')
    '网页设计' = @('网页 ui', 'frontend', '网页设计')
    'pdf' = @('pdf', 'pdfs')
    'ppt' = @('ppt', 'pptx', 'slide')
    'summarizes' = @('summarize', 'summarizes', 'summary')
    'find' = @('find', 'searches', 'search')
    'list' = @('list', 'catalog', 'summary')
    'handles' = @('handles', 'handle', 'manage')
}

function Get-AutoTriggerKeywords([string]$Query) {
    $text = $Query.ToLowerInvariant()
    $matches = [regex]::Matches($text, '[a-z0-9_-]+|[\u3400-\u9fff]+')
    $kws = [System.Collections.Generic.List[string]]::new()

    foreach ($m in $matches) {
        $t = $m.Value
        if ($stopWords.Contains($t)) { continue }

        if ($t -match '[\u3400-\u9fff]+') {
            $matched = $false
            foreach ($k in $aliases.Keys) {
                if ($t.Contains($k)) {
                    $matched = $true
                    if (-not $kws.Contains($k)) { $kws.Add($k) }
                    break
                }
            }
            if (-not $matched -and $t.Length -ge 1) {
                if (-not $kws.Contains($t)) { $kws.Add($t) }
            }
        } else {
            if (-not $stopWords.Contains($t) -and $t.Length -ge 2) {
                if (-not $kws.Contains($t)) { $kws.Add($t) }
            }
        }
    }
    return @($kws | Select-Object -Unique)
}

function Get-TriggerLikelihood([string]$Query, [string]$TargetDesc) {
    $kws = Get-AutoTriggerKeywords $Query
    if ($kws.Count -eq 0) { return 0.0 }
    $descLower = $TargetDesc.ToLowerInvariant()
    $hits = 0
    foreach ($kw in $kws) {
        $kwList = @($kw)
        if ($aliases.Contains($kw)) { $kwList += $aliases[$kw] }
        $hit = $false
        foreach ($al in $kwList) {
            if ($descLower.Contains($al.ToLowerInvariant())) {
                $hit = $true
                break
            }
        }
        if ($hit) { $hits++ }
    }
    return [math]::Round($hits / $kws.Count, 2)
}

$posPassed = 0
$posFailed = [System.Collections.Generic.List[string]]::new()
foreach ($q in $posQueries) {
    $lh = Get-TriggerLikelihood $q.query $desc
    if ($lh -ge 0.3) {
        $posPassed++
    } else {
        $posFailed.Add("[$($q.id)] FAIL (likelihood: $lh < 0.3) query: `"$($q.query)`"")
    }
}

$negPassed = 0
$negFailed = [System.Collections.Generic.List[string]]::new()
foreach ($q in $negQueries) {
    $lh = Get-TriggerLikelihood $q.query $desc
    if ($lh -le 0.2) {
        $negPassed++
    } else {
        $negFailed.Add("[$($q.id)] FAIL (likelihood: $lh > 0.2) query: `"$($q.query)`"")
    }
}

$totalPos = $posQueries.Count
$totalNeg = $negQueries.Count
$posPct = [math]::Round(($posPassed / $totalPos) * 100)
$negPct = [math]::Round(($negPassed / $totalNeg) * 100)

Write-Host "=========================================="
Write-Host "Auto-Trigger Heuristic Evaluation (PowerShell)"
Write-Host "=========================================="
Write-Host "Positive Cases: $posPassed / $totalPos ($posPct%) [target >= 83% (10/12)]"
Write-Host "Negative Cases: $negPassed / $totalNeg ($negPct%) [target >= 90% (9/10)]"
Write-Host "=========================================="

if ($posFailed.Count -gt 0) {
    Write-Host "Failed Positive Cases:"
    foreach ($pf in $posFailed) { Write-Host " - $pf" }
    Write-Host ""
}

if ($negFailed.Count -gt 0) {
    Write-Host "Failed Negative Cases:"
    foreach ($nf in $negFailed) { Write-Host " - $nf" }
    Write-Host ""
}

if ($posPassed -lt 10) {
    Write-Error "FAIL: Positive trigger rate $posPassed/$totalPos is below minimum 10/12"
    exit 1
}

if ($negPassed -lt 9) {
    Write-Error "FAIL: Negative rejection rate $negPassed/$totalNeg is below minimum 9/10"
    exit 1
}

Write-Host "PASS: Auto-trigger evaluation passed all criteria"
