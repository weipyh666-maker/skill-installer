[CmdletBinding()]
param(
    [ValidateSet('list', 'find', 'show', 'doctor', 'refresh', 'capabilities', 'fix')]
    [string]$Command = 'list',
    [string]$Query,
    [string]$Name,
    [int]$Limit = 10,
    [string]$Agent,
    [switch]$AllAgents,
    [switch]$DryRun,
    [switch]$Yes,
    [switch]$Json,
    [string]$RegisterName,
    [string]$RegisterSource,
    [string]$RegisterInstalledAt,
    [string]$RegisterCommit,
    [string]$RegisterSha256
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\..\adapters\_base.ps1"
. "$PSScriptRoot\..\adapters\claude\paths.ps1"
. "$PSScriptRoot\..\adapters\claude\detect.ps1"
. "$PSScriptRoot\..\adapters\antigravity\paths.ps1"
. "$PSScriptRoot\..\adapters\antigravity\detect.ps1"
. "$PSScriptRoot\..\adapters\codex\paths.ps1"
. "$PSScriptRoot\..\adapters\codex\detect.ps1"
. "$PSScriptRoot\..\core\search.ps1"
. "$PSScriptRoot\..\core\doctor.ps1"

$resolvedAgent = Resolve-AgentName $Agent
if (-not (Test-ValidAgentName $resolvedAgent)) {
    throw "Unknown agent '$resolvedAgent'. Supported agents: $($global:SupportedAgents -join ', ')"
}

function Get-FullPath([string]$Path) {
    if ($Path -eq '~') {
        return $env:USERPROFILE
    }
    if ($Path.StartsWith('~\') -or $Path.StartsWith('~/')) {
        return [IO.Path]::GetFullPath((Join-Path $env:USERPROFILE $Path.Substring(2)))
    }
    return [IO.Path]::GetFullPath($Path)
}

# Multi-agent path resolution
$ClaudeSkillsDir = Get-ClaudeSourceDir
$ClaudeLinkDir = Get-ClaudeLinkDir
$ClaudeIndexPath = Get-ClaudeIndexPath

$AntigravitySkillsDir = Get-AntigravitySourceDir
$AntigravityLinkDir = Get-AntigravityLinkDir
$AntigravityBuiltinDir = Get-AntigravityBuiltinDir
$AntigravityIndexPath = Get-AntigravityIndexPath

if ($resolvedAgent -eq 'codex') {
    $SkillsDir = Get-FullPath (Get-CodexUserSkillRoot)
    $LinkDir = Get-FullPath (Get-CodexCompatibilitySkillRoot)
    $IndexPath = Get-FullPath (Get-CodexIndexPath)
} elseif ($resolvedAgent -eq 'antigravity') {
    $SkillsDir = Get-FullPath $AntigravitySkillsDir
    $LinkDir = Get-FullPath $AntigravityLinkDir
    $IndexPath = Get-FullPath $AntigravityIndexPath
} else {
    $SkillsDir = Get-FullPath $ClaudeSkillsDir
    $LinkDir = Get-FullPath $ClaudeLinkDir
    $IndexPath = Get-FullPath $ClaudeIndexPath
}

$ActionVerbsMap = [ordered]@{
    'creating' = 'create'; 'building' = 'build'; 'generating' = 'generate'; 'analyzing' = 'analyze';
    'inspecting' = 'inspect'; 'running' = 'run'; 'finding' = 'find'; 'checking' = 'check';
    'converting' = 'convert'; 'translating' = 'translate'; 'developing' = 'develop'; 'managing' = 'manage';
    'formatting' = 'format'; 'testing' = 'test'; 'searching' = 'search'; 'querying' = 'query';
    'deploying' = 'deploy'; 'fixing' = 'fix'; 'scaffolding' = 'scaffold'; 'designing' = 'design';
    'writing' = 'write'; 'editing' = 'edit'; 'reviewing' = 'review'; 'extracting' = 'extract';
    'summarizing' = 'summarize'; 'tracking' = 'track'; 'transforming' = 'transform'; 'diagnosing' = 'diagnose';
    'operating' = 'operate'; 'providing' = 'provide'; 'handling' = 'handle'; 'applying' = 'apply';
    'modifying' = 'modify'; 'debugging' = 'debug'; 'evaluating' = 'evaluate'; 'optimizing' = 'optimize';
    'refactoring' = 'refactor'; 'auditing' = 'audit'; 'drafting' = 'draft'; 'publishing' = 'publish';
    'driving' = 'drive'; 'automating' = 'automate'; 'learning' = 'learn'; 'scanning' = 'scan';
    'creates' = 'create'; 'builds' = 'build'; 'generates' = 'generate'; 'analyzes' = 'analyze';
    'inspects' = 'inspect'; 'runs' = 'run'; 'finds' = 'find'; 'checks' = 'check';
    'converts' = 'convert'; 'translates' = 'translate'; 'develops' = 'develop'; 'manages' = 'manage';
    'formats' = 'format'; 'tests' = 'test'; 'searches' = 'search'; 'queries' = 'query';
    'deploys' = 'deploy'; 'fixes' = 'fix'; 'scaffolds' = 'scaffold'; 'designs' = 'design';
    'writes' = 'write'; 'edits' = 'edit'; 'reviews' = 'review'; 'extracts' = 'extract';
    'summarizes' = 'summarize'; 'tracks' = 'track'; 'transforms' = 'transform'; 'diagnoses' = 'diagnose';
    'operates' = 'operate'; 'provides' = 'provide'; 'handles' = 'handle'; 'applies' = 'apply';
    'modifies' = 'modify'; 'debugs' = 'debug'; 'evaluates' = 'evaluate'; 'optimizes' = 'optimize';
    'refactors' = 'refactor'; 'audits' = 'audit'; 'drafts' = 'draft'; 'publishes' = 'publish';
    'drives' = 'drive'; 'automates' = 'automate'; 'learns' = 'learn'; 'scans' = 'scan';
    'create' = 'create'; 'build' = 'build'; 'generate' = 'generate'; 'analyze' = 'analyze';
    'inspect' = 'inspect'; 'run' = 'run'; 'find' = 'find'; 'check' = 'check';
    'convert' = 'convert'; 'translate' = 'translate'; 'develop' = 'develop'; 'manage' = 'manage';
    'format' = 'format'; 'test' = 'test'; 'search' = 'search'; 'query' = 'query';
    'deploy' = 'deploy'; 'fix' = 'fix'; 'scaffold' = 'scaffold'; 'design' = 'design';
    'write' = 'write'; 'edit' = 'edit'; 'review' = 'review'; 'extract' = 'extract';
    'summarize' = 'summarize'; 'track' = 'track'; 'transform' = 'transform'; 'diagnose' = 'diagnose';
    'operate' = 'operate'; 'provide' = 'provide'; 'handle' = 'handle'; 'apply' = 'apply';
    'modify' = 'modify'; 'debug' = 'debug'; 'evaluate' = 'evaluate'; 'optimize' = 'optimize';
    'refactor' = 'refactor'; 'audit' = 'audit'; 'draft' = 'draft'; 'publish' = 'publish';
    'drive' = 'drive'; 'automate' = 'automate'; 'learn' = 'learn'; 'scan' = 'scan'
}

function Get-AliasTerms([string]$Text) {
    $map = [ordered]@{
        '图片' = @('image', 'vision', 'photo', 'screenshot', 'ocr')
        '图像' = @('image', 'vision', 'photo', 'screenshot', 'ocr')
        '照片' = @('image', 'vision', 'photo', 'screenshot')
        '截图' = @('screenshot', 'image', 'vision')
        '识别' = @('recognition', 'recognize', 'ocr', 'understanding', 'detect', 'identify')
        '理解' = @('understanding', 'recognition', 'recognize', 'vision')
        'ppt' = @('presentation', 'slides', 'deck', 'pptx')
        '演示' = @('presentation', 'slides', 'deck', 'pptx')
        '幻灯片' = @('presentation', 'slides', 'deck', 'pptx')
        '文档' = @('document', 'docs', 'docx', 'pdf')
        'pdf' = @('pdf', 'document', 'docs')
        'word' = @('docx', 'document', 'word')
        '表格' = @('spreadsheet', 'xlsx', 'excel', 'csv')
        'excel' = @('xlsx', 'spreadsheet', 'excel', 'csv')
        '网页' = @('web', 'website', 'browser', 'frontend', 'ui', 'page')
        '前端' = @('frontend', 'ui', 'web', 'interface', 'design')
        '界面' = @('ui', 'interface', 'frontend', 'gui')
        'ui' = @('ui', 'interface', 'frontend', 'gui', 'design')
        '设计' = @('design', 'create', 'craft', 'build')
        '做' = @('design', 'create', 'build', 'make', 'develop')
        '制作' = @('create', 'build', 'design', 'make')
        '代码' = @('code', 'coding', 'development', 'programming')
        '开发' = @('develop', 'development', 'code', 'coding', 'build')
        '编程' = @('programming', 'code', 'coding', 'develop')
        '调试' = @('debug', 'debugging', 'diagnosis', 'bug')
        '测试' = @('test', 'testing', 'qa', 'e2e')
        '诊断' = @('diagnose', 'diagnosis', 'debug', 'health')
        '搜索' = @('search', 'research', 'query', 'find')
        '调研' = @('research', 'survey', 'search', 'investigate')
    }
    $expanded = [System.Collections.Generic.List[string]]::new()
    foreach ($key in $map.Keys) {
        if ($Text.Contains($key)) {
            foreach ($val in $map[$key]) {
                if (-not $expanded.Contains($val)) {
                    $expanded.Add($val)
                }
            }
        }
    }
    return @($expanded)
}

function Get-SearchTerms([string]$Query) {
    $text = $Query.ToLowerInvariant()
    $matches = [regex]::Matches($text, '[a-z0-9][a-z0-9_-]{1,}|[\u3400-\u9fff]{2,}')
    $terms = [System.Collections.Generic.List[string]]::new()
    foreach ($m in $matches) {
        $v = $m.Value
        if (-not $terms.Contains($v)) { $terms.Add($v) }
    }
    foreach ($al in (Get-AliasTerms $text)) {
        if (-not $terms.Contains($al)) { $terms.Add($al) }
    }
    return @($terms)
}

function Get-Keywords([string]$Name, [string]$Description) {
    $text = "$Name $Description".ToLowerInvariant()
    $matches = [regex]::Matches($text, '[a-z0-9][a-z0-9_-]{1,}|[\u3400-\u9fff]{2,}')
    $words = [System.Collections.Generic.List[string]]::new()
    foreach ($m in $matches) {
        $val = $m.Value
        if (-not $words.Contains($val)) { $words.Add($val) }
    }
    foreach ($term in (Get-SearchTerms $text)) {
        if (-not $words.Contains($term)) { $words.Add($term) }
    }
    return @($words)
}

function Get-Category([string]$Explicit, [string]$Name, [string]$Description, [string[]]$Keywords) {
    if ($Explicit) {
        $cat = $Explicit.Trim().ToLowerInvariant()
        if ($cat -in @('documents', 'development', 'browser', 'research', 'data', 'media', 'other')) { return $cat }
        if ($cat -in @('doc', 'document', 'office')) { return 'documents' }
        if ($cat -in @('dev', 'coding', 'code')) { return 'development' }
        if ($cat -in @('web', 'browsing')) { return 'browser' }
        if ($cat -in @('analysis', 'analytics')) { return 'data' }
        if ($cat -in @('audio', 'video', 'image')) { return 'media' }
    }
    $text = "$Name $Description $($Keywords -join ' ')".ToLowerInvariant()
    $docWords = @('document', 'docs', 'docx', 'pdf', 'ppt', 'pptx', 'presentation', 'slides', 'excel', 'xlsx', 'csv', 'spreadsheet', 'markdown', '文档', '幻灯片', '表格', '演示', 'office')
    $devWords = @('code', 'coding', 'develop', 'dev', 'git', 'github', 'api', 'test', 'testing', 'debug', 'diagnose', 'lint', 'compile', 'build', 'refactor', 'backend', 'frontend', 'react', 'vue', 'node', 'python', 'rust', 'go', 'flutter', 'typescript', 'javascript', 'hook', 'architecture', '代码', '开发', '调试', '编译', '重构')
    $browserWords = @('browser', 'browsing', 'scrape', 'scraping', 'crawl', 'crawler', 'puppeteer', 'playwright', 'stagehand', 'selenium', 'navigate', '网页', '浏览器', '抓取')
    $researchWords = @('research', 'search', 'exa', 'query', 'lookup', 'paper', 'papers', 'survey', 'arxiv', 'huggingface', 'intel', '调研', '搜索', '论文', '检索')
    $dataWords = @('data', 'analysis', 'analytics', 'database', 'sql', 'parquet', 'dataset', 'datasets', 'metrics', 'chart', '数据', '数据库', '分析', '统计')
    $mediaWords = @('image', 'vision', 'photo', 'screenshot', 'audio', 'video', 'transcribe', 'transcript', 'tts', 'speech', 'ocr', 'art', 'music', 'fal.ai', '图像', '图片', '音频', '视频', '语音', '视觉', '艺术')

    foreach ($w in $docWords) { if ($text.Contains($w)) { return 'documents' } }
    foreach ($w in $browserWords) { if ($text.Contains($w)) { return 'browser' } }
    foreach ($w in $mediaWords) { if ($text.Contains($w)) { return 'media' } }
    foreach ($w in $dataWords) { if ($text.Contains($w)) { return 'data' } }
    foreach ($w in $researchWords) { if ($text.Contains($w)) { return 'research' } }
    foreach ($w in $devWords) { if ($text.Contains($w)) { return 'development' } }
    return 'other'
}

function Get-FrontmatterField([string]$Frontmatter, [string]$Field) {
    $lineList = $Frontmatter -split "`r?`n"
    $descIndex = -1
    $style = $null
    for ($i = 0; $i -lt $lineList.Count; $i++) {
        $trimmed = $lineList[$i].Trim()
        $marker = [regex]::Match($trimmed, "^$($Field):\s*([>|][+-]?)$")
        if ($marker.Success) { $descIndex = $i; $style = $marker.Groups[1].Value; break }
        if ($trimmed -eq "$($Field):") { $descIndex = $i; $style = 'list'; break }
        if ([regex]::IsMatch($lineList[$i], "^$($Field):\s*\S")) { $descIndex = $i; break }
    }
    if ($descIndex -lt 0) { return '' }
    if ($null -eq $style) {
        $value = ($lineList[$descIndex] -split ':', 2)[1].Trim().Trim('"').Trim("'")
        if ($value -in @('>', '|', '>-', '|-', '>+', '|+')) { return '' }
        return $value
    }
    $collected = [System.Collections.Generic.List[string]]::new()
    for ($j = $descIndex + 1; $j -lt $lineList.Count; $j++) {
        $line = $lineList[$j]
        if (-not $line.Trim()) { continue }
        if ($line[0] -eq ' ' -or $line[0] -eq "`t") {
            $item = $line.Trim().TrimStart('-').Trim().Trim('"').Trim("'")
            if ($item) { $collected.Add($item) }
        }
        else { break }
    }
    if ($style -eq 'list') {
        return ($collected -join ', ')
    }
    return ($collected -join ' ')
}

function Get-Capabilities([string]$Frontmatter, [string]$Name, [string]$Category, [string[]]$Keywords) {
    $explicit = Get-FrontmatterField $Frontmatter 'capabilities'
    if ($explicit) {
        $trimmed = $explicit.Trim('[').Trim(']')
        $parts = $trimmed -split '[,;]' | ForEach-Object { $_.Trim().Trim('"').Trim("'") } | Where-Object { $_ }
        if ($parts.Count -gt 0) { return @($parts | Select-Object -Unique) }
    }
    $derived = [System.Collections.Generic.List[string]]::new()
    $derived.Add($Name)
    $derived.Add($Category)
    foreach ($kw in $Keywords) {
        if ($kw.Length -ge 3 -and $derived.Count -lt 8 -and -not $derived.Contains($kw)) {
            $derived.Add($kw)
        }
    }
    return @($derived | Select-Object -Unique)
}

function Get-SkillDirectories {
    $selected = [ordered]@{}
    foreach ($root in @($LinkDir, $SkillsDir)) {
        if (-not (Test-Path -LiteralPath $root -PathType Container)) { continue }
        foreach ($directory in Get-ChildItem -LiteralPath $root -Directory -Force) {
            if ($directory.Name.StartsWith('.')) { continue }
            if (-not $selected.Contains($directory.Name)) {
                $selected[$directory.Name] = [pscustomobject]@{ Name = $directory.Name; Path = $directory.FullName; Root = $root }
            }
        }
    }
    return @($selected.Values)
}

function ConvertTo-V3Index($raw) {
    if (-not $raw) {
        return [ordered]@{
            schema_version = 3
            default_agent = 'claude'
            updated_at = $null
            skills = @()
        }
    }
    $skills = @()
    if ($raw.skills) {
        foreach ($entry in $raw.skills) {
            $e = [ordered]@{}
            foreach ($prop in $entry.PSObject.Properties) {
                $e[$prop.Name] = $prop.Value
            }
            if (-not $e['category']) {
                $kws = Get-Keywords $e['name'] $e['description']
                $e['category'] = Get-Category '' $e['name'] $e['description'] $kws
            }
            if (-not $e['capabilities']) {
                $kws = Get-Keywords $e['name'] $e['description']
                $e['capabilities'] = @(Get-Capabilities '' $e['name'] $e['category'] $kws)
            }
            if (-not $e['status']) { $e['status'] = 'ok' }
            if (-not $e['health']) { $e['health'] = 'ok' }

            $agentsObj = [ordered]@{}
            if ($e['agents']) {
                if ($e['agents'] -is [System.Management.Automation.PSCustomObject] -or $e['agents'] -is [System.Collections.IDictionary]) {
                    foreach ($p in $e['agents'].PSObject.Properties) {
                        $agentsObj[$p.Name] = $p.Value
                    }
                }
            }

            $claudeVisible = if ($agentsObj.Contains('claude') -and $agentsObj['claude'].visible -ne $null) {
                [bool]$agentsObj['claude'].visible
            } else {
                ($e['status'] -eq 'ok' -and $e['health'] -eq 'ok')
            }
            $claudePath = if ($e['link_path']) { $e['link_path'] } else { $e['source_path'] }
            $agentsObj['claude'] = [ordered]@{
                visible = $claudeVisible
                path = if ($claudeVisible) { $claudePath } else { $null }
                reason = if ($claudeVisible) { 'link present' } else { 'link missing or broken' }
            }

            if (-not $agentsObj.Contains('codex')) {
                $agentsObj['codex'] = [ordered]@{
                    visible = $false
                    path = $null
                    reason = 'not installed for codex'
                }
            }

            if (-not $agentsObj.Contains('antigravity')) {
                $agentsObj['antigravity'] = [ordered]@{
                    visible = $false
                    path = $null
                    reason = 'not installed for antigravity'
                }
            }

            $e['agents'] = [pscustomobject]$agentsObj
            $skills += [pscustomobject]$e
        }
    }

    $defaultAg = if ($raw.default_agent) { $raw.default_agent } else { 'claude' }
    $updatedAt = if ($raw.updated_at) { $raw.updated_at } else { $raw.generated_at }

    return [ordered]@{
        schema_version = 3
        default_agent = $defaultAg
        updated_at = $updatedAt
        skills = $skills
    }
}

function Get-CodexSkillCandidates {
    $items = [Collections.Generic.List[object]]::new()
    foreach ($root in (Get-CodexDiscoveryRoots)) {
        if (-not (Test-Path -LiteralPath $root.path -PathType Container)) { continue }
        $files = if ($root.class -eq 'plugin-cache') {
            Get-ChildItem -LiteralPath $root.path -Filter 'SKILL.md' -File -Recurse -Force -ErrorAction SilentlyContinue
        } else {
            Get-ChildItem -LiteralPath $root.path -Directory -Force -ErrorAction SilentlyContinue |
                ForEach-Object { Get-Item -LiteralPath (Join-Path $_.FullName 'SKILL.md') -Force -ErrorAction SilentlyContinue } |
                Where-Object { $_ -and $_.PSIsContainer -eq $false }
        }
        foreach ($file in $files) {
            if ($file.Directory.Name -eq '.backups') { continue }
            $items.Add([pscustomobject]@{ Root = $root; SkillPath = $file.FullName; Directory = $file.Directory.FullName })
        }
    }
    return @($items | Sort-Object { $_.SkillPath })
}

function Get-CodexSkillConfig {
    $configPath = Join-Path (Get-CodexHome) 'config.toml'
    $entries = @{}
    if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) { return [pscustomobject]@{ entries=$entries; external=@() } }
    $raw = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
    foreach ($block in [regex]::Matches($raw, '(?ms)^\s*\[\[skills\.config\]\](.*?)(?=^\s*\[\[|\z)')) {
        $pathMatch = [regex]::Match($block.Groups[1].Value, '(?m)^\s*path\s*=\s*["'']([^"'']+)["'']')
        if (-not $pathMatch.Success) { continue }
        $enabledMatch = [regex]::Match($block.Groups[1].Value, '(?mi)^\s*enabled\s*=\s*(true|false)')
        $fullPath = Resolve-CodexPath $pathMatch.Groups[1].Value
        $enabled = $true
        if ($enabledMatch.Success -and $enabledMatch.Groups[1].Value.ToLowerInvariant() -eq 'false') { $enabled = $false }
        $entries[$fullPath.ToLowerInvariant()] = [pscustomobject]@{ path=$fullPath; enabled=$enabled }
    }
    return [pscustomobject]@{ entries=$entries; external=@() }
}

function Build-CodexIndex {
    $byName = @{}
    $config = Get-CodexSkillConfig
    $discoveredSkillPaths = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($candidate in (Get-CodexSkillCandidates)) {
        $null = $discoveredSkillPaths.Add((Resolve-CodexPath $candidate.SkillPath))
        $raw = Get-Content -LiteralPath $candidate.SkillPath -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
        $match = [regex]::Match($raw, '(?ms)^---\s*\r?\n(.*?)\r?\n---')
        $frontmatter = if ($match.Success) { $match.Groups[1].Value } else { '' }
        $name = Get-FrontmatterField $frontmatter 'name'
        if (-not $name) { $name = Split-Path -Leaf $candidate.Directory }
        $description = Get-FrontmatterField $frontmatter 'description'
        $category = Get-Category (Get-FrontmatterField $frontmatter 'category') $name $description (Get-Keywords $name $description)
        $capabilities = @(Get-Capabilities $frontmatter $name $category (Get-Keywords $name $description))
        $configState = $config.entries[(Resolve-CodexPath $candidate.SkillPath).ToLowerInvariant()]
        $variant = [ordered]@{
            path = $candidate.Directory
            skill_path = $candidate.SkillPath
            scope = $candidate.Root.scope
            class = $candidate.Root.class
            protected = ([bool]$candidate.Root.protected -or (Test-CodexProtectedPath $candidate.Directory))
            enabled = if ($configState) { [bool]$configState.enabled } else { $true }
            description = $description
            category = $category
            capabilities = $capabilities
            frontmatter = $frontmatter
            sha256 = (Get-FileHash -LiteralPath $candidate.SkillPath -Algorithm SHA256).Hash
        }
        if (-not $byName.ContainsKey($name)) { $byName[$name] = [Collections.Generic.List[object]]::new() }
        $byName[$name].Add([pscustomobject]$variant)
    }

    $entries = [Collections.Generic.List[object]]::new()
    foreach ($name in ($byName.Keys | Sort-Object)) {
        $variants = @($byName[$name] | Sort-Object path)
        $visibleVariants = @($variants | Where-Object { $_.class -ne 'plugin-cache' -and $_.enabled })
        $descriptions = @($variants.description | Where-Object { $_ } | Select-Object -Unique)
        $frontmatters = @($variants.frontmatter | Select-Object -Unique)
        $categories = @($variants.category | Select-Object -Unique)
        $allCapabilities = @($variants | ForEach-Object { $_.capabilities } | Select-Object -Unique)
        $isDuplicate = $variants.Count -gt 1
        $reason = if ($visibleVariants.Count -eq 0 -and @($variants | Where-Object { -not $_.enabled }).Count -gt 0) { 'disabled-by-codex-config' } elseif ($visibleVariants.Count -eq 0) { 'plugin-enablement-dependent' } elseif ($isDuplicate) { 'multiple-discovery-roots; precedence-unknown' } elseif ($variants[0].class -eq 'system') { 'discovered-in-system-root' } else { "discovered-in-$($variants[0].scope)-root" }
        $paths = @($variants | ForEach-Object { [ordered]@{ path=$_.path; skill_path=$_.skill_path; scope=$_.scope; class=$_.class; protected=$_.protected; enabled=$_.enabled } })
        $agents = [ordered]@{
            claude = [ordered]@{ visible=$false; path=$null; reason='not installed for claude' }
            antigravity = [ordered]@{ visible=$false; path=$null; reason='not installed for antigravity' }
            codex = [ordered]@{
                visible = ($visibleVariants.Count -gt 0)
                reason = $reason
                paths = $paths
                scopes = @($variants.scope | Select-Object -Unique)
                protected = (@($variants | Where-Object protected).Count -gt 0)
                enabled = (@($variants | Where-Object enabled).Count -gt 0)
                duplicate = $isDuplicate
                precedence = if ($isDuplicate) { 'unknown' } else { $null }
                metadata_conflict = ($frontmatters.Count -gt 1)
                variants = $variants
            }
        }
        $entries.Add([pscustomobject][ordered]@{
            name = $name
            install_name = $name
            description = ($descriptions -join ' | ')
            capabilities = $allCapabilities
            category = if ($categories.Count -eq 1) { $categories[0] } else { 'other' }
            source = 'codex-discovery'
            provenance = 'filesystem'
            source_path = $paths[0].path
            link_path = ''
            discovered_at = [DateTime]::UtcNow.ToString('o')
            installed_at = $null
            commit = $null
            sha256 = $null
            status = if ($frontmatters.Count -eq $variants.Count) { 'ok' } else { 'broken' }
            health = if ($frontmatters.Count -eq $variants.Count) { 'ok' } else { 'broken' }
            agents = [pscustomobject]$agents
        })
    }
    $external = @($config.entries.Values | Where-Object { -not $discoveredSkillPaths.Contains($_.path) } | ForEach-Object { [ordered]@{ path=$_.path; enabled=$_.enabled; status='unknown'; reason='config-only-or-external-path' } })
    return [ordered]@{ schema_version=3; default_agent='codex'; updated_at=[DateTime]::UtcNow.ToString('o'); skills=@($entries); codex_config_external=$external }
}

function Build-Index {
    if ($resolvedAgent -eq 'codex') { return (Build-CodexIndex) }
    $oldIndex = if (Test-Path -LiteralPath $IndexPath) {
        try {
            $raw = Get-Content -LiteralPath $IndexPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($raw.schema_version -ge 3) { $raw } else { [pscustomobject](ConvertTo-V3Index $raw) }
        } catch { $null }
    } else { $null }

    $oldMap = @{}
    if ($oldIndex -and $oldIndex.skills) {
        foreach ($item in $oldIndex.skills) {
            if ($item.name) {
                $oldMap[$item.name] = $item
                if ($item.install_name) { $oldMap[$item.install_name] = $item }
            }
        }
    }

    $entries = [System.Collections.Generic.List[object]]::new()
    $scannedNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $scanned = Get-SkillDirectories
    $nowIso = [DateTime]::UtcNow.ToString('o')

    foreach ($candidate in $scanned) {
        $name = $candidate.Name
        $root = $candidate.Root
        $skillPath = Join-Path $candidate.Path 'SKILL.md'

        $hasClaudeLink = Test-Path -LiteralPath (Join-Path $ClaudeLinkDir $name)
        $hasClaudeSource = Test-Path -LiteralPath (Join-Path $ClaudeSkillsDir $name)
        $hasAntigravityLink = Test-Path -LiteralPath (Join-Path $AntigravityLinkDir $name)
        $hasAntigravitySource = Test-Path -LiteralPath (Join-Path $AntigravitySkillsDir $name)

        $claudeVis = ($hasClaudeLink -or ($resolvedAgent -eq 'claude' -and $hasClaudeSource))
        $antigravityVis = ($hasAntigravityLink -or $hasAntigravitySource -or ($resolvedAgent -eq 'antigravity' -and (Test-Path -LiteralPath $candidate.Path)))

        $linkPathStr = if ($hasClaudeLink) { "`$CLAUDE_SKILLS_LINK_DIR/$name" } elseif ($hasAntigravityLink) { "`$ANTIGRAVITY_SKILLS_LINK_DIR/$name" } else { '' }
        $sourcePathStr = if ($resolvedAgent -eq 'antigravity') { "`$ANTIGRAVITY_SKILLS_DIR/$name" } else { "`$CLAUDE_SKILLS_DIR/$name" }

        $agents = [ordered]@{
            claude = [ordered]@{
                visible = [bool]$claudeVis
                path = if ($claudeVis) { (Join-Path $ClaudeLinkDir $name) } else { $null }
                reason = if ($claudeVis) { 'link present' } else { 'not installed for claude' }
            }
            codex = [ordered]@{
                visible = $false
                path = $null
                reason = 'not installed for codex'
            }
            antigravity = [ordered]@{
                visible = [bool]$antigravityVis
                path = if ($antigravityVis) { (Join-Path $AntigravityLinkDir $name) } else { $null }
                reason = if ($antigravityVis) { 'discovered-in-antigravity-global-skill-root' } else { 'not installed for antigravity' }
            }
        }

        if (-not (Test-Path -LiteralPath $skillPath -PathType Leaf)) {
            $brokenEntry = [ordered]@{
                name = $name
                install_name = $name
                description = ''
                capabilities = @($name, 'other')
                keywords = @($name)
                category = 'other'
                discovered_at = $nowIso
                installed_at = $null
                source = 'unknown'
                provenance = 'unknown'
                source_path = $sourcePathStr
                link_path = $linkPathStr
                commit = $null
                sha256 = $null
                status = 'broken'
                health = 'broken'
                usage = [pscustomobject]@{ status = 'unknown'; last_seen = $null; invocation_count = $null }
                agents = [pscustomobject]$agents
            }
            $entries.Add([pscustomobject]$brokenEntry)
            $null = $scannedNames.Add($name)
            continue
        }

        $content = ''
        try { $content = Get-Content -LiteralPath $skillPath -Raw -Encoding UTF8 } catch {}

        $frontmatter = ''
        if ($content -match '(?ms)^---\s*\r?\n(.*?)\r?\n---(?:\s*\r?\n|$)') {
            $frontmatter = $Matches[1]
        } else {
            $frontmatter = $content
        }

        $nameMatch = [regex]::Match($content, '(?m)^name:\s*([a-z0-9][a-z0-9-]{0,63})\s*$')
        $description = Get-FrontmatterField $frontmatter 'description'
        $explicitCat = Get-FrontmatterField $frontmatter 'category'
        $skillName = if ($nameMatch.Success) { $nameMatch.Groups[1].Value } else { $name }

        $status = if ($nameMatch.Success -and $description) { 'ok' } else { 'broken' }
        $health = if ($status -eq 'ok') { 'ok' } else { 'broken' }
        $keywords = Get-Keywords $skillName $description
        $category = Get-Category $explicitCat $skillName $description $keywords
        $capabilities = Get-Capabilities $frontmatter $skillName $category $keywords

        $entry = [ordered]@{
            name = $skillName
            install_name = $name
            description = $description
            capabilities = @($capabilities)
            keywords = @($keywords)
            category = $category
            discovered_at = $nowIso
            installed_at = $null
            source = 'unknown'
            provenance = 'unknown'
            source_path = $sourcePathStr
            link_path = $linkPathStr
            commit = $null
            sha256 = $null
            status = $status
            health = $health
            usage = [pscustomobject]@{ status = 'unknown'; last_seen = $null; invocation_count = $null }
            agents = [pscustomobject]$agents
        }

        $old = if ($oldMap.ContainsKey($entry.name)) { $oldMap[$entry.name] } elseif ($oldMap.ContainsKey($entry.install_name)) { $oldMap[$entry.install_name] } else { $null }
        if ($old) {
            if ($old.discovered_at) { $entry['discovered_at'] = $old.discovered_at }
            elseif ($old.installed_at) { $entry['discovered_at'] = $old.installed_at }
            if ($old.installed_at) { $entry['installed_at'] = $old.installed_at }
            if ($old.source -and $old.source -ne 'local') {
                $entry['source'] = $old.source
                if ($old.source.StartsWith('github:')) { $entry['provenance'] = 'installer' }
            } else {
                $entry['source'] = 'unknown'
                $entry['provenance'] = 'unknown'
            }
            if ($old.provenance) { $entry['provenance'] = $old.provenance }
            if ($old.commit) { $entry['commit'] = $old.commit }
            if ($old.sha256) { $entry['sha256'] = $old.sha256 }
            if ($old.usage) { $entry['usage'] = $old.usage }
        }

        $entries.Add([pscustomobject]$entry)
        $null = $scannedNames.Add($skillName)
        $null = $scannedNames.Add($name)
    }

    if ($oldIndex -and $oldIndex.skills) {
        foreach ($oldSkill in $oldIndex.skills) {
            $oldName = $oldSkill.name
            $oldInst = $oldSkill.install_name
            if ($oldName -and -not $scannedNames.Contains($oldName) -and (-not $oldInst -or -not $scannedNames.Contains($oldInst))) {
                $missingEntry = [ordered]@{
                    name = $oldName
                    install_name = if ($oldInst) { $oldInst } else { $oldName }
                    description = if ($oldSkill.description) { $oldSkill.description } else { '' }
                    capabilities = if ($oldSkill.capabilities) { @($oldSkill.capabilities) } else { @($oldName, 'other') }
                    keywords = if ($oldSkill.keywords) { @($oldSkill.keywords) } else { @($oldName) }
                    category = if ($oldSkill.category) { $oldSkill.category } else { 'other' }
                    discovered_at = if ($oldSkill.discovered_at) { $oldSkill.discovered_at } else { $nowIso }
                    installed_at = $oldSkill.installed_at
                    source = if ($oldSkill.source -and $oldSkill.source -ne 'local') { $oldSkill.source } else { 'unknown' }
                    provenance = if ($oldSkill.provenance) { $oldSkill.provenance } else { 'unknown' }
                    source_path = if ($oldSkill.source_path) { $oldSkill.source_path } else { "`$CLAUDE_SKILLS_DIR/$oldName" }
                    link_path = ''
                    commit = $oldSkill.commit
                    sha256 = $oldSkill.sha256
                    status = 'broken'
                    health = 'missing'
                    usage = if ($oldSkill.usage) { $oldSkill.usage } else { [pscustomobject]@{ status = 'unknown'; last_seen = $null; invocation_count = $null } }
                    agents = [pscustomobject]@{
                        claude = [ordered]@{ visible = $false; path = $null; reason = 'missing' }
                        codex = [ordered]@{ visible = $false; path = $null; reason = 'not installed for codex' }
                        antigravity = [ordered]@{ visible = $false; path = $null; reason = 'missing' }
                    }
                }
                $entries.Add([pscustomobject]$missingEntry)
            }
        }
    }

    $sorted = @($entries | Sort-Object { $_.name.ToLowerInvariant() })
    return [ordered]@{
        schema_version = 3
        default_agent = 'claude'
        updated_at = $nowIso
        skills = $sorted
    }
}

function Write-Index($IndexData) {
    $parent = Split-Path -Parent $IndexPath
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    $temp = Join-Path $parent ("installed-skills-index.json.tmp-" + [guid]::NewGuid().ToString('N'))
    $json = $IndexData | ConvertTo-Json -Depth 10
    $utf8 = [Text.UTF8Encoding]::new($false)
    [IO.File]::WriteAllText($temp, $json + [Environment]::NewLine, $utf8)
    Move-Item -LiteralPath $temp -Destination $IndexPath -Force
}

function Apply-Registration($IndexData) {
    if (-not $RegisterName) { return $IndexData }
    foreach ($entry in $IndexData.skills) {
        if ($entry.name -eq $RegisterName -or $entry.install_name -eq $RegisterName) {
            if ($RegisterSource) {
                $entry.source = $RegisterSource
                $entry.provenance = if ($RegisterSource.StartsWith('github:')) { 'installer' } else { 'local' }
            }
            if ($RegisterInstalledAt) {
                $entry.installed_at = $RegisterInstalledAt
                $entry.discovered_at = $RegisterInstalledAt
            }
            if ($RegisterCommit) { $entry.commit = $RegisterCommit }
            if ($RegisterSha256) { $entry.sha256 = $RegisterSha256 }
            $entry.status = 'ok'
            $entry.health = 'ok'
        }
    }
    return $IndexData
}

function Filter-SkillsByAgent($SkillsList, [string]$AgentName, [bool]$All) {
    if ($All) { return @($SkillsList) }
    $res = @($SkillsList | Where-Object {
        $_.agents.$AgentName.visible -eq $true
    })
    return $res
}

function Get-Score($Entry, [string]$SearchQuery) {
    $terms = Get-SearchTerms $SearchQuery
    $nameLower = $Entry.name.ToLowerInvariant()
    $installLower = if ($Entry.install_name) { $Entry.install_name.ToLowerInvariant() } else { '' }
    $descLower = if ($Entry.description) { $Entry.description.ToLowerInvariant() } else { '' }
    $kwList = if ($Entry.keywords) { @($Entry.keywords | ForEach-Object { $_.ToLowerInvariant() }) } else { @() }
    $capList = if ($Entry.capabilities) { @($Entry.capabilities | ForEach-Object { $_.ToLowerInvariant() }) } else { @() }
    $catLower = if ($Entry.category) { $Entry.category.ToLowerInvariant() } else { '' }
    $searchText = "$nameLower $installLower $descLower $($kwList -join ' ') $($capList -join ' ') $catLower".ToLowerInvariant()

    $imageWords = @('image', 'vision', 'photo', 'screenshot', 'picture', '图片', '图像', '照片', '截图')
    $recogWords = @('recogni', 'ocr', 'detect', 'identif', 'understand', 'classif', '识别', '理解', '分类')
    $queryLower = $SearchQuery.ToLowerInvariant()

    $qHasImage = ($imageWords | Where-Object { $queryLower.Contains($_) }).Count -gt 0
    $qHasRecog = ($recogWords | Where-Object { $queryLower.Contains($_) }).Count -gt 0
    if ($qHasImage -and $qHasRecog) {
        $tHasImage = ($imageWords | Where-Object { $searchText.Contains($_) }).Count -gt 0
        $tHasRecog = ($recogWords | Where-Object { $searchText.Contains($_) }).Count -gt 0
        if (-not ($tHasImage -and $tHasRecog)) { return 0 }
    }

    $uiWords = @('web', 'website', 'frontend', 'ui', 'interface', 'page', '网页', '前端', '界面')
    $designWords = @('design', 'create', 'build', 'craft', 'make', '设计', '做', '制作', '构建')
    $qHasUi = ($uiWords | Where-Object { $queryLower.Contains($_) }).Count -gt 0
    $qHasDesign = ($designWords | Where-Object { $queryLower.Contains($_) }).Count -gt 0
    if ($qHasUi -and $qHasDesign) {
        $tHasUi = ($uiWords | Where-Object { $searchText.Contains($_) }).Count -gt 0
        $tHasDesign = ($designWords | Where-Object { $searchText.Contains($_) }).Count -gt 0
        if (-not ($tHasUi -and $tHasDesign)) { return 0 }
    }

    $total = 0
    if ($nameLower -eq $queryLower) { $total += 20 }
    elseif ($nameLower.Contains($queryLower)) { $total += 15 }

    foreach ($term in $terms) {
        if ($nameLower -eq $term) { $total += 12 }
        elseif ($nameLower.Contains($term)) { $total += 8 }
        if ($installLower -and $installLower.Contains($term)) { $total += 6 }
        if ($catLower.Contains($term)) { $total += 4 }
        if (($capList | Where-Object { $_.Contains($term) }).Count -gt 0) { $total += 3 }
        if ($descLower.Contains($term)) { $total += 2 }
        if (($kwList | Where-Object { $_.Contains($term) }).Count -gt 0) { $total += 1 }
    }
    return $total
}

function Format-SkillsTable($SkillsList) {
    if ($Json) {
        $SkillsList | ConvertTo-Json -Depth 10
        return
    }
    Write-Host "Skills: $($SkillsList.Count)"
    foreach ($entry in $SkillsList) {
        $n = $entry.name
        $s = if ($entry.status) { $entry.status } else { 'unknown' }
        $d = if ($entry.description) { $entry.description } else { '' }
        if ($d.Length -gt 80) { $d = $d.Substring(0, 77) + '...' }
        Write-Host ("{0,-38} [{1,-7}] {2}" -f $n, $s, $d)
    }
}

function Format-Capabilities($IndexData, $TargetSkills) {
    $skills = if ($null -ne $TargetSkills) { $TargetSkills } else { @($IndexData.skills) }
    $categories = @(
        @('documents', 'Documents'),
        @('development', 'Development'),
        @('media', 'Media'),
        @('data', 'Data'),
        @('browser', 'Browser'),
        @('research', 'Research'),
        @('other', 'Other')
    )

    $byCat = [ordered]@{}
    foreach ($c in $categories) { $byCat[$c[0]] = [System.Collections.Generic.List[object]]::new() }
    $broken = [System.Collections.Generic.List[object]]::new()

    foreach ($s in $skills) {
        if ($s.status -ne 'ok' -or $s.health -ne 'ok') {
            $broken.Add($s)
        } else {
            $cat = if ($s.category) { $s.category.ToLowerInvariant() } else { 'other' }
            if (-not $byCat.Contains($cat)) { $cat = 'other' }
            $byCat[$cat].Add($s)
        }
    }

    $totalCount = $skills.Count
    $brokenCount = $broken.Count
    Write-Host "Your Agent currently has $totalCount Skills ($brokenCount broken)`n"

    foreach ($c in $categories) {
        $key = $c[0]
        $label = $c[1]
        $group = $byCat[$key]
        if ($group.Count -gt 0) {
            Write-Host "$label ($($group.Count))"
            $sortedGroup = @($group | Sort-Object { $_.name.ToLowerInvariant() })
            foreach ($item in $sortedGroup) {
                $desc = if ($item.description) { $item.description } else { '(no description)' }
                if ($desc.Length -gt 60) { $desc = $desc.Substring(0, 57) + '...' }
                Write-Host ("  {0,-20} {1}" -f $item.name, $desc)
            }
            Write-Host ''
        }
    }

    if ($broken.Count -gt 0) {
        Write-Host "Broken ($($broken.Count))"
        $sortedBroken = @($broken | Sort-Object { $_.name.ToLowerInvariant() })
        foreach ($item in $sortedBroken) {
            $desc = if ($item.description) { $item.description } else { "($($item.health))" }
            if ($desc.Length -gt 60) { $desc = $desc.Substring(0, 57) + '...' }
            Write-Host ("  {0,-20} {1}" -f $item.name, $desc)
        }
        Write-Host ''
    }
}

function Invoke-DoctorGlobal($IndexData) {
    $skills = @($IndexData.skills)
    $targetSkills = Filter-SkillsByAgent $skills $resolvedAgent $AllAgents
    $scannedCount = $targetSkills.Count
    $brokenList = @($targetSkills | Where-Object { $_.status -ne 'ok' -or $_.health -eq 'broken' })
    $missingList = @($targetSkills | Where-Object { $_.health -eq 'missing' })
    $healthyCount = [Math]::Max(0, ($scannedCount - $brokenList.Count - $missingList.Count))

    if ($resolvedAgent -eq 'codex') {
        $status = Get-CodexStatus
        $duplicates = @($targetSkills | Where-Object { $_.agents.codex.duplicate })
        Write-Host "doctor: scanned $scannedCount skills for agent 'codex'"
        Write-Host "  CLI resolved: $($status.CliResolved)"
        Write-Host "  CLI executable test: $($status.ExecutableTest)"
        Write-Host "  CODEX_HOME: $($status.CodexHome)"
        Write-Host "  user root: $($status.UserRoot)"
        Write-Host "  compatibility root: $($status.CompatibilityRoot)"
        Write-Host "  system root: $($status.SystemRoot) (protected)"
        Write-Host "  healthy: $healthyCount"
        foreach ($entry in $duplicates) {
            Write-Host "  ⚠ Duplicate Codex Skill name: $($entry.name)"
            foreach ($path in $entry.agents.codex.paths) { Write-Host "    - $($path.path) [$($path.scope)/$($path.class)]" }
            Write-Host '    Codex precedence is undocumented; skill-manager will not choose a winner.'
        }
        return
    } elseif ($resolvedAgent -eq 'antigravity') {
        $status = Get-AntigravityStatus
        Write-Host "doctor: scanned $scannedCount skills for agent 'antigravity'"
        Write-Host "  environment: $(if ($status.CliDetected) { 'CLI detected (' + $status.CliPath + ')' } elseif ($status.SkillsDirDetected) { 'skills directory detected' } else { 'not detected' })"
        Write-Host "  discovery root: $($status.GlobalSkillsDir)"
        Write-Host "  healthy: $healthyCount"
    } else {
        Write-Host "doctor: scanned $scannedCount skills"
        Write-Host "  healthy: $healthyCount"
    }
    if ($brokenList.Count -gt 0) {
        $brokenNames = ($brokenList | ForEach-Object { $_.name }) -join ', '
        Write-Host "  broken: $($brokenList.Count) ($brokenNames)"
    } else {
        Write-Host "  broken: 0"
    }

    if ($missingList.Count -gt 0) {
        $missingNames = ($missingList | ForEach-Object { $_.name }) -join ', '
        Write-Host "  missing: $($missingList.Count) ($missingNames)"
    } else {
        Write-Host "  missing: 0"
    }

    $healthyScores = [System.Collections.Generic.List[object]]::new()
    $healthyList = @($targetSkills | Where-Object { $_.status -eq 'ok' -and $_.health -eq 'ok' })
    foreach ($s in $healthyList) {
        $sDir = if ($s.install_name) { $s.install_name } else { $s.name }
        $sFile = Join-Path $SkillsDir (Join-Path $sDir 'SKILL.md')
        $lFile = Join-Path $LinkDir (Join-Path $sDir 'SKILL.md')
        $raw = ''
        if (Test-Path -LiteralPath $sFile -PathType Leaf) {
            try { $raw = Get-Content -LiteralPath $sFile -Raw -Encoding UTF8 } catch {}
        } elseif (Test-Path -LiteralPath $lFile -PathType Leaf) {
            try { $raw = Get-Content -LiteralPath $lFile -Raw -Encoding UTF8 } catch {}
        }
        $fm = ''
        $fmM = [regex]::Match($raw, '(?ms)^---\s*\r?\n(.*?)\r?\n---(?:\s*\r?\n|$)')
        if ($fmM.Success) { $fm = $fmM.Groups[1].Value }
        $dDesc = Get-FrontmatterField $fm 'description'
        $dCaps = Get-FrontmatterField $fm 'capabilities'
        $dCat = Get-FrontmatterField $fm 'category'
        $eval = Test-TriggerQualityRules $fm $dDesc $dCaps $dCat
        $healthyScores.Add([pscustomobject]@{ Name = $s.name; Score = $eval.Score; Warnings = $eval.Warnings })
    }

    $avgScore = if ($healthyScores.Count -gt 0) {
        [math]::Round(($healthyScores | Measure-Object -Property Score -Average).Average, 1)
    } else { 0.0 }

    Write-Host ("trigger quality: avg {0:F1}% across healthy skills" -f $avgScore)

    $lowestTop3 = @($healthyScores | Sort-Object { $_.Score } | Select-Object -First 3)
    if ($lowestTop3.Count -gt 0) {
        Write-Host "Top 3 skills with lowest score:"
        foreach ($low in $lowestTop3) {
            Write-Host ("  - {0} ({1:F1}%)" -f $low.Name, $low.Score)
        }
    }

    if ($brokenList.Count -gt 0 -or $missingList.Count -gt 0) {
        exit 1
    }
}

function Invoke-DoctorSingle([string]$SkillName, $IndexData) {
    $entry = @($IndexData.skills | Where-Object { $_.name -eq $SkillName -or $_.install_name -eq $SkillName } | Select-Object -First 1)[0]
    $dirName = if ($entry -and $entry.install_name) { $entry.install_name } else { $SkillName }

    $sourceDisk = Join-Path $SkillsDir $dirName
    $linkDisk = Join-Path $LinkDir $dirName
    $sourceFile = Join-Path $sourceDisk 'SKILL.md'
    $linkFile = Join-Path $linkDisk 'SKILL.md'

    $sourceExists = Test-Path -LiteralPath $sourceDisk -PathType Container
    $linkExists = Test-Path -LiteralPath $linkDisk
    $sourceFileExists = Test-Path -LiteralPath $sourceFile -PathType Leaf
    $linkFileExists = Test-Path -LiteralPath $linkFile -PathType Leaf

    $rawContent = ''
    if ($sourceFileExists) {
        try { $rawContent = Get-Content -LiteralPath $sourceFile -Raw -Encoding UTF8 } catch {}
    } elseif ($linkFileExists) {
        try { $rawContent = Get-Content -LiteralPath $linkFile -Raw -Encoding UTF8 } catch {}
    }

    $frontmatter = ''
    $frontmatterMatch = [regex]::Match($rawContent, '(?ms)^---\s*\r?\n(.*?)\r?\n---(?:\s*\r?\n|$)')
    if ($frontmatterMatch.Success) {
        $frontmatter = $frontmatterMatch.Groups[1].Value
    }

    $declaredName = Get-FrontmatterField $frontmatter 'name'
    $declaredDesc = Get-FrontmatterField $frontmatter 'description'
    $declaredCat = Get-FrontmatterField $frontmatter 'category'
    $declaredCaps = Get-FrontmatterField $frontmatter 'capabilities'

    $suggestions = [System.Collections.Generic.List[string]]::new()

    Write-Host "$SkillName`n"
    Write-Host "Installation"
    if ($sourceExists) {
        Write-Host "  ✓ Source at `$CLAUDE_SKILLS_DIR/$dirName"
    } else {
        Write-Host "  ✗ Source missing at `$CLAUDE_SKILLS_DIR/$dirName"
    }

    if ($linkExists) {
        Write-Host "  ✓ Link at `$CLAUDE_SKILLS_LINK_DIR/$dirName"
    } else {
        Write-Host "  ✗ Link missing at `$CLAUDE_SKILLS_LINK_DIR/$dirName"
    }

    if ($sourceExists -and $linkExists) {
        if ($sourceFileExists -and $linkFileExists) {
            try {
                $sHash = (Get-FileHash -LiteralPath $sourceFile -Algorithm SHA256).Hash
                $lHash = (Get-FileHash -LiteralPath $linkFile -Algorithm SHA256).Hash
                if ($sHash -eq $lHash) {
                    Write-Host "  ✓ Source and link SKILL.md match"
                } else {
                    Write-Host "  ✗ Source and link SKILL.md differ (out of sync)"
                    $suggestions.Add("Re-link with: pwsh -File lib/install.ps1 -LocalPath `"`$CLAUDE_SKILLS_DIR/$dirName`" -LinkOnly -Force")
                }
            } catch {}
        }
    } else {
        Write-Host "  ⚠ Single copy found (no link hash comparison)"
    }
    Write-Host ''

    Write-Host "Structure"
    if ($sourceFileExists -or $linkFileExists) {
        Write-Host "  ✓ SKILL.md present"
    } else {
        Write-Host "  ✗ SKILL.md missing"
        $suggestions.Add("Create `$CLAUDE_SKILLS_DIR/$dirName/SKILL.md")
    }

    if ($frontmatterMatch.Success) {
        Write-Host "  ✓ YAML frontmatter valid"
    } else {
        Write-Host "  ✗ YAML frontmatter missing or unparseable"
    }

    if ($declaredName) {
        if ($declaredName -eq $SkillName -or ($entry -and $declaredName -eq $entry.name)) {
            Write-Host "  ✓ name = $declaredName"
        } else {
            Write-Host "  ⚠ name ($declaredName) differs from directory name ($SkillName)"
        }
    } else {
        Write-Host "  ✗ name missing in frontmatter"
    }

    if ($declaredDesc) {
        Write-Host "  ✓ description present"
    } else {
        Write-Host "  ✗ description missing in frontmatter"
    }
    Write-Host ''

    Write-Host "Discovery"
    if ($linkExists) {
        Write-Host "  ✓ Claude link path visible"
    } else {
        Write-Host "  ✗ Not visible in Claude link path"
        $suggestions.Add("Create symlink: New-Item -ItemType SymbolicLink -Path `"`$CLAUDE_SKILLS_LINK_DIR/$dirName`" -Target `"`$CLAUDE_SKILLS_DIR/$dirName`"")
    }

    if (($sourceFileExists) -or ($linkFileExists)) {
        Write-Host "  ✓ File readable"
    } else {
        Write-Host "  ✗ File not readable (permission issue)"
    }
    Write-Host ''

    Write-Host "Trigger quality"
    $eval = Test-TriggerQualityRules $frontmatter $declaredDesc $declaredCaps $declaredCat
    foreach ($d in $eval.Details) {
        Write-Host "  $($d.Status) $($d.Text)"
    }
    Write-Host ''
    Write-Host ("  trigger quality: {0} ⚠ / 8 ✓ (score: {1:F1}%)" -f $eval.Warnings, $eval.Score)
    if ($eval.Warnings -eq 0 -or $eval.Score -ge 70.0) {
        Write-Host "  ✓ Trigger description looks Claude-discoverable"
    }
    Write-Host ''

    if ($eval.Recommendations.Count -gt 0) {
        Write-Host "Recommendations:"
        foreach ($r in $eval.Recommendations) {
            Write-Host "  - $r"
        }
        Write-Host ''
    }

    if ($suggestions.Count -gt 0) {
        Write-Host "Suggestions:"
        foreach ($s in $suggestions) {
            Write-Host "  - $s"
        }
    }
}

function Get-TriggerWarningCount([string]$Frontmatter, [string]$Desc, [string]$Caps, [string]$Cat) {
    $count = 0
    if (-not $Desc -or $Desc.Trim().Length -lt 20) {
        $count++
    } elseif (-not ($Desc.Trim() -match '^(?i)use when\b')) {
        $count++
    }

    $actionWords = @('use', 'create', 'analyze', 'build', 'check', 'inspect', 'run', 'extract', 'convert', 'manage', 'format', 'test', 'search', 'query', 'deploy', 'fix', 'scaffold', 'design', 'write', 'edit', 'review', 'translate', 'summarize', 'crawl', 'scrape', 'monitor', '转换', '提取', '创建', '分析', '构建', '检查', '运行', '调试', '搜索', '编写', '审查', '设计', '做')
    $descLower = if ($Desc) { $Desc.ToLowerInvariant() } else { '' }
    $hasAction = ($actionWords | Where-Object { $descLower.Contains($_) }).Count -gt 0
    if (-not $hasAction) { $count++ }

    if (-not $Caps) { $count++ }
    if (-not $Cat) { $count++ }
    return $count
}

function Test-IsSymlinkOrReparse([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    $item = Get-Item -LiteralPath $Path -Force
    if ($item.LinkType) { return $true }
    if ($item.Attributes.HasFlag([System.IO.FileAttributes]::ReparsePoint)) { return $true }
    return $false
}

function Get-RewrittenDescription([string]$Desc) {
    $trimmed = $Desc.Trim()
    if ($trimmed.Length -lt 20) {
        return [pscustomobject]@{ Text = $trimmed; Changed = $false; Skip = $true; Reason = 'description too short to fix automatically; manual edit needed' }
    }
    if ($trimmed -match '^(?i)use when\b') {
        $clean = 'Use when ' + ($trimmed -replace '^(?i)use when\s*', '')
        return [pscustomobject]@{ Text = $clean; Changed = ($clean -ne $trimmed); Skip = $false; Reason = 'already compliant' }
    }

    $patternCWhen = '^(?i)(?:(?:you\s+)?must\s+use\s+(?:this\s+(?:skill|before)\s+)?(?:when|before)\s+|this skill\s+(?:should be used|is used|can be used)\s+when\s+|use this skill\s+(?:when|whenever)\s+|used\s+(?:when|whenever)\s*)'
    if ($trimmed -match $patternCWhen) {
        $stripped = ($trimmed -replace $patternCWhen, '').Trim()
        if ($stripped -match '^(?i)(?:the\s+)?user\b') {
            $cleanUser = $stripped -replace '^(?i)(?:the\s+)?user\b', 'the user'
            return [pscustomobject]@{ Text = "Use when $cleanUser"; Changed = $true; Skip = $false; Reason = 'case c: 3rd person when user' }
        } else {
            $trimmed = $stripped
        }
    }

    $patternC2 = '^(?i)(?:this skill\s+(?:should be used|is used|can be used)\s+(?:to|for)\s*|use this skill\s+(?:to|for)\s*|this skill\s+(?:provides|allows|helps with|helps to)\s*|used\s+(?:to|for)\s*)'
    if ($trimmed -match $patternC2) {
        $trimmed = ($trimmed -replace $patternC2, '').Trim()
    }

    $words = $trimmed -split '\s+' | Where-Object { $_ }
    if ($words.Count -gt 0) {
        $firstWord = $words[0].ToLowerInvariant().TrimEnd(',', '.', ':', ';')
        if ($ActionVerbsMap.Contains($firstWord)) {
            $baseVerb = $ActionVerbsMap[$firstWord]
            $rest = if ($words.Count -gt 1) { ($words[1..($words.Count - 1)] -join ' ') } else { '' }
            $newText = if ($rest) { "Use when the user wants to $baseVerb $rest" } else { "Use when the user wants to $baseVerb" }
            return [pscustomobject]@{ Text = $newText; Changed = $true; Skip = $false; Reason = 'case b: action verb' }
        }
    }

    $firstChar = $trimmed.Substring(0, 1).ToLowerInvariant()
    $restChars = if ($trimmed.Length -gt 1) { $trimmed.Substring(1) } else { '' }
    $defaultText = "Use when the user wants to $firstChar$restChars"
    return [pscustomobject]@{ Text = $defaultText; Changed = $true; Skip = $false; Reason = 'case e: default' }
}

function Get-TopCapabilities([string]$Frontmatter, [string]$Name, [string]$Description, [string]$Category) {
    $explicit = Get-FrontmatterField $Frontmatter 'capabilities'
    if ($explicit) {
        $trimmed = $explicit.Trim('[').Trim(']')
        $parts = $trimmed -split '[,;]' | ForEach-Object { $_.Trim().Trim('"').Trim("'") } | Where-Object { $_ }
        if ($parts.Count -gt 0) { return @($parts | Select-Object -Unique) }
    }

    $stopWords = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $stopList = @('use', 'when', 'the', 'user', 'wants', 'to', 'for', 'and', 'or', 'in', 'on', 'with', 'a', 'an', 'is', 'are', 'this', 'skill', 'should', 'be', 'can', 'needs', 'any', 'from', 'into', 'by', 'that', 'as', 'it', 'of', 'at', 'so', 'more', 'reliably', 'auto', 'discover', 'whenever', 'about', 'also', 'all', 'will', 'then', 'than', 'such', 'not', 'out', 'up', 'down', 'only', 'both', 'each', 'how', 'what', 'which', 'who', 'whom', 'whose', 'why', 'where', 'there', 'their', 'they', 'them', 'these', 'those')
    foreach ($w in $stopList) { $null = $stopWords.Add($w) }

    $counts = @{}
    $nameMatches = [regex]::Matches($Name.ToLowerInvariant(), '[a-z0-9][a-z0-9_-]{1,}|[\u3400-\u9fff]{2,}')
    foreach ($m in $nameMatches) {
        $v = $m.Value
        if (-not $stopWords.Contains($v) -and $v.Length -ge 2) {
            $counts[$v] = if ($counts.ContainsKey($v)) { $counts[$v] + 10 } else { 10 }
        }
    }

    $descMatches = [regex]::Matches($Description.ToLowerInvariant(), '[a-z0-9][a-z0-9_-]{1,}|[\u3400-\u9fff]{2,}')
    foreach ($m in $descMatches) {
        $v = $m.Value
        if (-not $stopWords.Contains($v) -and $v.Length -ge 2) {
            $counts[$v] = if ($counts.ContainsKey($v)) { $counts[$v] + 2 } else { 2 }
        }
    }

    $aliasWords = Get-SearchTerms "$Name $Description"
    foreach ($v in $aliasWords) {
        if (-not $stopWords.Contains($v) -and $v.Length -ge 2) {
            $counts[$v] = if ($counts.ContainsKey($v)) { $counts[$v] + 3 } else { 3 }
        }
    }

    $sortedWords = @($counts.Keys | Sort-Object { $counts[$_] } -Descending)
    $selected = [System.Collections.Generic.List[string]]::new()
    foreach ($k in $sortedWords) {
        if (-not $selected.Contains($k)) {
            $selected.Add($k)
        }
        if ($selected.Count -ge 5) { break }
    }
    if ($selected.Count -eq 0) {
        $selected.Add($Name)
        $selected.Add($Category)
    }
    return @($selected)
}

function Build-FixedFrontmatter([string]$OriginalFrontmatter, [string]$NewDesc, [string[]]$NewCaps, [string]$NewCat) {
    $lines = $OriginalFrontmatter -split "`r?`n"
    $descIndices = [System.Collections.Generic.List[int]]::new()
    $i = 0
    while ($i -lt $lines.Count) {
        $trimmed = $lines[$i].Trim()
        $mScalar = [regex]::Match($trimmed, '^description:\s*([>|][+-]?)$')
        if ($mScalar.Success -or $trimmed -eq 'description:') {
            $descIndices.Add($i)
            $j = $i + 1
            while ($j -lt $lines.Count) {
                $sub = $lines[$j]
                if (-not $sub.Trim()) { $j++; continue }
                if ($sub[0] -eq ' ' -or $sub[0] -eq "`t") {
                    $descIndices.Add($j)
                    $j++
                } else { break }
            }
            $i = $j
            continue
        } elseif ([regex]::IsMatch($lines[$i], '^description:\s*\S')) {
            $descIndices.Add($i)
        }
        $i++
    }

    $capsIndices = [System.Collections.Generic.List[int]]::new()
    $i = 0
    while ($i -lt $lines.Count) {
        $trimmed = $lines[$i].Trim()
        if ($trimmed -eq 'capabilities:' -or [regex]::IsMatch($trimmed, '^capabilities:\s*([>|][+-]?)$')) {
            $capsIndices.Add($i)
            $j = $i + 1
            while ($j -lt $lines.Count) {
                $sub = $lines[$j]
                if (-not $sub.Trim()) { $j++; continue }
                if ($sub[0] -eq ' ' -or $sub[0] -eq "`t") {
                    $capsIndices.Add($j)
                    $j++
                } else { break }
            }
            $i = $j
            continue
        } elseif ([regex]::IsMatch($lines[$i], '^capabilities:\s*\S')) {
            $capsIndices.Add($i)
        }
        $i++
    }

    $catIndices = [System.Collections.Generic.List[int]]::new()
    for ($k = 0; $k -lt $lines.Count; $k++) {
        if ([regex]::IsMatch($lines[$k], '^category:\s*')) { $catIndices.Add($k) }
    }

    $toRemove = [System.Collections.Generic.HashSet[int]]::new()
    foreach ($idx in $descIndices) { $null = $toRemove.Add($idx) }
    foreach ($idx in $capsIndices) { $null = $toRemove.Add($idx) }
    foreach ($idx in $catIndices) { $null = $toRemove.Add($idx) }

    $preserved = [System.Collections.Generic.List[string]]::new()
    for ($k = 0; $k -lt $lines.Count; $k++) {
        if (-not $toRemove.Contains($k)) { $preserved.Add($lines[$k]) }
    }

    $nameIdx = -1
    for ($k = 0; $k -lt $preserved.Count; $k++) {
        if ([regex]::IsMatch($preserved[$k], '^name:\s*')) { $nameIdx = $k; break }
    }

    $insertLines = [System.Collections.Generic.List[string]]::new()
    $insertLines.Add("description: $NewDesc")
    $insertLines.Add("capabilities:")
    foreach ($c in $NewCaps) {
        $insertLines.Add("  - $c")
    }
    $insertLines.Add("category: $NewCat")

    $finalLines = [System.Collections.Generic.List[string]]::new()
    if ($nameIdx -ge 0) {
        for ($k = 0; $k -le $nameIdx; $k++) { $finalLines.Add($preserved[$k]) }
        foreach ($l in $insertLines) { $finalLines.Add($l) }
        for ($k = $nameIdx + 1; $k -lt $preserved.Count; $k++) { $finalLines.Add($preserved[$k]) }
    } else {
        foreach ($l in $insertLines) { $finalLines.Add($l) }
        foreach ($l in $preserved) { $finalLines.Add($l) }
    }

    return ($finalLines -join [Environment]::NewLine)
}

function Invoke-FixSkill($Entry, [bool]$IsDryRun, [bool]$ConfirmYes) {
    $dirName = if ($Entry.install_name) { $Entry.install_name } else { $Entry.name }
    if ($resolvedAgent -eq 'codex') {
        $codexPaths = @($Entry.agents.codex.paths)
        if ($Entry.agents.codex.protected -or @($codexPaths | Where-Object { $_.protected }).Count -gt 0) { throw 'Refusing to modify protected Codex SYSTEM Skill.' }
        $writable = @($codexPaths | Where-Object { $_.scope -eq 'user' -and $_.class -eq 'agents' -and -not $_.protected })
        if ($writable.Count -ne 1) { throw 'Refusing to modify Codex Skill outside the single writable user root.' }
        $sourceDisk = $writable[0].path
        $linkDisk = $sourceDisk
    } else {
        $sourceDisk = Join-Path $SkillsDir $dirName
        $linkDisk = Join-Path $LinkDir $dirName
    }
    $targetFile = $null
    $targetDisk = $null

    $sourceFile = Join-Path $sourceDisk 'SKILL.md'
    $linkFile = Join-Path $linkDisk 'SKILL.md'

    if (Test-Path -LiteralPath $sourceFile -PathType Leaf) {
        $targetFile = $sourceFile
        $targetDisk = $sourceDisk
    } elseif (Test-Path -LiteralPath $linkFile -PathType Leaf) {
        $targetFile = $linkFile
        $targetDisk = $linkDisk
    } else {
        Write-Host "Skipping $($Entry.name): SKILL.md not found"
        return
    }

    # Check for sensitive files before fixing
    $sensitiveFiles = @(Get-ChildItem -LiteralPath $targetDisk -Recurse -File -Force -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -match '^\.env($|\.)' -or $_.Extension -match '^\.(key|pem|p12|pfx)$'
    })
    if ($sensitiveFiles.Count -gt 0) {
        Write-Host "refusing to copy sensitive file: $($sensitiveFiles[0].FullName)"
        return
    }

    $rawContent = ''
    try {
        $rawContent = Get-Content -LiteralPath $targetFile -Raw -Encoding UTF8
    } catch {
        Write-Host "Skipping $($Entry.name): unable to read SKILL.md: $_"
        return
    }

    $checkMatch = [regex]::Match($rawContent, '(?ms)^---\s*\r?\n(.*?)\r?\n---(?:\s*\r?\n(.*))?$')
    if (-not $checkMatch.Success) {
        Write-Host "Skipping $($Entry.name): frontmatter missing or invalid"
        return
    }

    $frontmatter = $checkMatch.Groups[1].Value
    $body = if ($checkMatch.Groups.Count -gt 2) { $checkMatch.Groups[2].Value } else { '' }

    $oldDesc = Get-FrontmatterField $frontmatter 'description'
    $oldCaps = Get-FrontmatterField $frontmatter 'capabilities'
    $oldCat = Get-FrontmatterField $frontmatter 'category'

    $rewritten = Get-RewrittenDescription $oldDesc
    if ($rewritten.Skip) {
        Write-Host "Skipping $($Entry.name): $($rewritten.Reason)"
        return
    }

    $newDesc = $rewritten.Text
    $newCat = Get-Category $oldCat $Entry.name $newDesc (Get-Keywords $Entry.name $newDesc)
    $newCaps = Get-TopCapabilities $frontmatter $Entry.name $newDesc $newCat

    $newFrontmatter = Build-FixedFrontmatter $frontmatter $newDesc $newCaps $newCat
    $isSymlink = (Test-IsSymlinkOrReparse $targetDisk) -or (Test-IsSymlinkOrReparse $targetFile)

    if ($isSymlink) {
        Write-Host "refusing to modify symlink: $targetFile; suggested patch for $($Entry.name):"
        Write-Host "---`n$newFrontmatter`n---"
        return
    }

    if ($IsDryRun) {
        Write-Host "[proposed] $($Entry.name)`n"
        Write-Host "description (before):`n  $oldDesc`n"
        Write-Host "description (after):`n  $newDesc`n"
        Write-Host "capabilities (added):"
        foreach ($c in $newCaps) {
            Write-Host "  - $c"
        }
        Write-Host "`ncategory (added):`n  $newCat`n"
        $ts = Get-Date -Format 'yyyyMMdd-HHmmss'
        $backupPreview = if ($resolvedAgent -eq 'codex') { (Join-Path (Get-CodexHome) 'skill-manager\backups') } else { (Join-Path $SkillsDir '.backups') }
        Write-Host "no symlink. backup would go to: $backupPreview/$($Entry.name)-$ts-SKILL.md`n"
        return
    }

    if (-not $ConfirmYes) {
        Write-Host "[proposed] $($Entry.name)`n"
        Write-Host "description (after):`n  $newDesc`n"
        Write-Host "capabilities (added):`n  $($newCaps -join ', ')`n"
        Write-Host "category (added):`n  $newCat`n"
        $ans = Read-Host "Apply changes to this skill? [y/N]"
        if ($ans -notmatch '^(?i)y(?:es)?$') {
            Write-Host "Skipped $($Entry.name)."
            return
        }
    }

    $backupDir = if ($resolvedAgent -eq 'codex') { Join-Path (Get-CodexHome) 'skill-manager\backups' } else { Join-Path $SkillsDir '.backups' }
    if (-not (Test-Path -LiteralPath $backupDir)) {
        New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
    }
    $ts = Get-Date -Format 'yyyyMMdd-HHmmss'
    $backupFile = Join-Path $backupDir "$($Entry.name)-$ts-SKILL.md"
    try {
        $utf8 = [Text.UTF8Encoding]::new($false)
        [IO.File]::WriteAllText($backupFile, $rawContent, $utf8)
    } catch {
        Write-Host "Failed to create backup for $($Entry.name): $_"
        return
    }

    $newFullContent = "---`n$newFrontmatter`n---`n$body"
    try {
        $utf8 = [Text.UTF8Encoding]::new($false)
        [IO.File]::WriteAllText($targetFile, $newFullContent, $utf8)
    } catch {
        Write-Host "Failed to write changes for $($Entry.name): $_"
        return
    }

    try {
        $verifyContent = Get-Content -LiteralPath $targetFile -Raw -Encoding UTF8
        $verifyMatch = [regex]::Match($verifyContent, '(?ms)^---\s*\r?\n(.*?)\r?\n---(?:\s*\r?\n(.*))?$')
        if (-not $verifyMatch.Success -or -not (Get-FrontmatterField $verifyMatch.Groups[1].Value 'name')) {
            throw "Verification failed: corrupted frontmatter"
        }
    } catch {
        Write-Host "CRITICAL: verification failed after modifying $($Entry.name), restoring from backup: $_"
        $utf8 = [Text.UTF8Encoding]::new($false)
        [IO.File]::WriteAllText($targetFile, $rawContent, $utf8)
        return
    }

    $beforeWarnings = Get-TriggerWarningCount $frontmatter $oldDesc $oldCaps $oldCat
    $afterWarnings = Get-TriggerWarningCount $newFrontmatter $newDesc ($newCaps -join ',') $newCat

    Write-Host "fixed $($Entry.name): description rewritten, capabilities + category added"
    Write-Host "  trigger quality: $afterWarnings ⚠ (was $beforeWarnings ⚠)"
}

$index = if (Test-Path -LiteralPath $IndexPath) {
    try {
        $raw = Get-Content -LiteralPath $IndexPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($raw.schema_version -ge 3) { $raw } else { [pscustomobject](ConvertTo-V3Index $raw) }
    } catch {
        [pscustomobject](Build-Index)
    }
} else {
    $fresh = Build-Index
    Write-Index $fresh
    [pscustomobject]$fresh
}

switch ($Command) {
    'refresh' {
        $fresh = Build-Index
        $fresh = Apply-Registration $fresh
        Write-Index $fresh
        Format-SkillsTable $fresh.skills
    }
    'capabilities' {
        $targetSkills = Filter-SkillsByAgent $index.skills $resolvedAgent $AllAgents
        if ($targetSkills.Count -eq 0 -and -not $AllAgents) {
            Write-Host "No visible skills for agent '$resolvedAgent' (use -AllAgents to inspect all catalog skills)."
            exit 0
        }
        Format-Capabilities $index $targetSkills
    }
    'list' {
        $targetSkills = Filter-SkillsByAgent $index.skills $resolvedAgent $AllAgents
        Format-SkillsTable $targetSkills
    }
    'find' {
        if (-not $Query -or -not $Query.Trim()) {
            throw '-Query is required for find'
        }
        $targetSkills = Filter-SkillsByAgent $index.skills $resolvedAgent $AllAgents
        $terms = Get-ExpandedSearchTerms $Query
        $scored = [System.Collections.Generic.List[object]]::new()
        foreach ($entry in $targetSkills) {
            $res = Get-SkillScoreAndReason $entry $Query $terms
            if ($res.Score -gt 0) {
                $scored.Add([pscustomobject]@{ Score = $res.Score; Reason = $res.Reason; Entry = $entry })
            }
        }
        $sorted = @($scored | Sort-Object { $_.Score } -Descending)

        if ($sorted.Count -eq 0) {
            Write-Host "No matching skills for `"$Query`"."
            exit 0
        }

        if ($Json) {
            $jsonList = @($sorted | ForEach-Object {
                $obj = [ordered]@{}
                foreach ($p in $_.Entry.PSObject.Properties) { $obj[$p.Name] = $p.Value }
                $obj['score'] = $_.Score
                $obj['match_reason'] = $_.Reason
                [pscustomobject]$obj
            })
            $jsonList | ConvertTo-Json -Depth 10
            exit 0
        }

        $topList = @($sorted | Select-Object -First $Limit)
        Write-Host "Matches for `"$Query`":`n"
        for ($i = 0; $i -lt $topList.Count; $i++) {
            $num = $i + 1
            $item = $topList[$i]
            $entry = $item.Entry
            $scVal = $item.Score
            $reason = $item.Reason
            $desc = if ($entry.description) { $entry.description } else { '(no description)' }
            if ($desc.Length -gt 75) { $desc = $desc.Substring(0, 72) + '...' }
            Write-Host ("  {0,2}. {1,-28} (score: {2})" -f $num, $entry.name, $scVal)
            Write-Host "     $desc"
            if ($reason) {
                Write-Host "     $reason`n"
            } else {
                Write-Host ''
            }
        }
        Write-Host "Found $($sorted.Count) matches. Showing top $($topList.Count)."
    }
    'show' {
        if (-not $Name) { throw '-Name is required for show' }
        $entry = @($index.skills | Where-Object { $_.name -eq $Name -or $_.install_name -eq $Name } | Select-Object -First 1)[0]
        if ($null -eq $entry) { throw "Skill not found: $Name" }
        if ($Json) {
            $entry | ConvertTo-Json -Depth 10
        } else {
            foreach ($key in @('name', 'install_name', 'description', 'capabilities', 'category', 'source', 'provenance', 'source_path', 'link_path', 'discovered_at', 'installed_at', 'commit', 'sha256', 'status', 'health')) {
                $val = $entry.$key
                if ($key -eq 'capabilities' -and $val) { $val = ($val -join ', ') }
                Write-Host "$($key): $val"
            }
            foreach ($ag in @('claude', 'codex', 'antigravity')) {
                $vis = if ($entry.agents -and $entry.agents.$ag) { $entry.agents.$ag.visible } else { $false }
                Write-Host "agents.$($ag).visible: $vis"
            }
            $usageStatus = if ($entry.usage -and $entry.usage.status) { $entry.usage.status } else { 'unknown' }
            Write-Host "usage.status: $usageStatus"
            Write-Host "invocation_hint: Ask Claude Code to use the named skill for a matching task. Automatic invocation is not observable by this catalog."
        }
    }
    'doctor' {
        $fresh = Build-Index
        if ($Name) {
            Invoke-DoctorSingle $Name $fresh
        } else {
            Invoke-DoctorGlobal $fresh
        }
    }
    'fix' {
        $fresh = Build-Index
        if ($Name) {
            $entry = @($fresh.skills | Where-Object { $_.name -eq $Name -or $_.install_name -eq $Name } | Select-Object -First 1)[0]
            if ($null -eq $entry) { throw "Skill not found: $Name" }
            Invoke-FixSkill $entry $DryRun $Yes
            if (-not $DryRun) {
                Write-Index (Build-Index)
            }
        } else {
            $okSkills = @($fresh.skills | Where-Object { $_.status -eq 'ok' -and $_.health -eq 'ok' })
            if ($DryRun) {
                foreach ($s in $okSkills) {
                    Invoke-FixSkill $s $true $true
                }
            } else {
                if (-not $Yes) {
                    $resp = Read-Host "This will rewrite $($okSkills.Count) skills. Continue? [y/N]"
                    if ($resp -notmatch '^(?i)y(?:es)?$') {
                        Write-Host "Operation cancelled."
                        exit 0
                    }
                }
                foreach ($s in $okSkills) {
                    Invoke-FixSkill $s $false $true
                }
                Write-Index (Build-Index)
            }
        }
    }
}
