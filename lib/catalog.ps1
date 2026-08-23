[CmdletBinding()]
param(
    [ValidateSet('list', 'find', 'show', 'doctor', 'refresh', 'capabilities', 'fix')]
    [string]$Command = 'list',
    [string]$Query,
    [string]$Name,
    [int]$Limit = 10,
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

function Get-FullPath([string]$Path) {
    if ($Path -eq '~') {
        return $env:USERPROFILE
    }
    if ($Path.StartsWith('~\') -or $Path.StartsWith('~/')) {
        return [IO.Path]::GetFullPath((Join-Path $env:USERPROFILE $Path.Substring(2)))
    }
    return [IO.Path]::GetFullPath($Path)
}

$SkillsDir = if ($env:CLAUDE_SKILLS_DIR) { Get-FullPath $env:CLAUDE_SKILLS_DIR } else { Get-FullPath (Join-Path $env:USERPROFILE 'Claude-Code') }
$LinkDir = if ($env:CLAUDE_SKILLS_LINK_DIR) { Get-FullPath $env:CLAUDE_SKILLS_LINK_DIR } else { Get-FullPath (Join-Path $env:USERPROFILE '.claude\skills') }
$IndexPath = if ($env:CLAUDE_SKILLS_INDEX_PATH) { Get-FullPath $env:CLAUDE_SKILLS_INDEX_PATH } else { Join-Path $SkillsDir 'installed-skills-index.json' }

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
        '技能' = @('skill', 'agent', 'workflow')
    }
    $terms = [System.Collections.Generic.List[string]]::new()
    foreach ($term in ($Text.ToLowerInvariant() -split '\s+' | Where-Object { $_ })) { $terms.Add($term) }
    foreach ($key in $map.Keys) {
        if ($Text.Contains($key)) {
            foreach ($alias in $map[$key]) { $terms.Add($alias) }
        }
    }
    return @($terms | Select-Object -Unique)
}

function Get-Keywords([string]$NameValue, [string]$Description) {
    $text = "$NameValue $Description".ToLowerInvariant()
    $matches = [regex]::Matches($text, '[a-z0-9][a-z0-9_-]{1,}|[\u3400-\u9fff]{2,}')
    $words = foreach ($match in $matches) { $match.Value }
    return @($words + (Get-AliasTerms $text) | Select-Object -Unique)
}

function Get-Category([string]$ExplicitCategory, [string]$Name, [string]$Description, [string[]]$Keywords) {
    if ($ExplicitCategory) {
        $cat = $ExplicitCategory.Trim().ToLowerInvariant()
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

function Get-PreviousEntry([object]$OldIndex, [string]$SkillName, [string]$InstallName) {
    if ($null -eq $OldIndex) { return $null }
    $entry = @($OldIndex.skills | Where-Object { $_.name -eq $SkillName -or ($InstallName -and $_.install_name -eq $InstallName) } | Select-Object -First 1)[0]
    return $entry
}

function Read-SkillEntry([object]$Directory) {
    $skillFile = Join-Path $Directory.Path 'SKILL.md'
    $hasLink = Test-Path -LiteralPath (Join-Path $LinkDir $Directory.Name)
    $linkPath = if ($hasLink) { "`$CLAUDE_SKILLS_LINK_DIR/$($Directory.Name)" } else { '' }
    $sourcePath = "`$CLAUDE_SKILLS_DIR/$($Directory.Name)"
    $nowIso = [DateTime]::UtcNow.ToString('o')

    if (-not (Test-Path -LiteralPath $skillFile -PathType Leaf)) {
        return [ordered]@{
            name = $Directory.Name
            install_name = $Directory.Name
            description = ''
            capabilities = @($Directory.Name, 'other')
            keywords = @($Directory.Name)
            category = 'other'
            discovered_at = $nowIso
            installed_at = $null
            source = 'unknown'
            provenance = 'unknown'
            source_path = $sourcePath
            link_path = $linkPath
            commit = $null
            sha256 = $null
            status = 'broken'
            health = 'broken'
            usage = [ordered]@{ status = 'unknown'; last_seen = $null; invocation_count = $null }
            agents = [ordered]@{ claude = [ordered]@{ visible = $hasLink; link_path = $linkPath } }
        }
    }

    $content = Get-Content -Raw -LiteralPath $skillFile
    $frontmatterMatch = [regex]::Match($content, '(?ms)^---\s*\r?\n(.*?)\r?\n---(?:\s*\r?\n|$)')
    $frontmatter = if ($frontmatterMatch.Success) { $frontmatterMatch.Groups[1].Value } else { $content }

    $nameMatch = [regex]::Match($content, '(?m)^name:\s*([a-z0-9][a-z0-9-]{0,63})\s*$')
    $description = Get-FrontmatterField $frontmatter 'description'
    $explicitCategory = Get-FrontmatterField $frontmatter 'category'
    $skillName = if ($nameMatch.Success) { $nameMatch.Groups[1].Value } else { $Directory.Name }

    $status = if ($nameMatch.Success -and $description) { 'ok' } else { 'broken' }
    $health = if ($status -eq 'ok') { 'ok' } else { 'broken' }
    $keywords = @(Get-Keywords $skillName $description)
    $category = Get-Category $explicitCategory $skillName $description $keywords
    $capabilities = @(Get-Capabilities $frontmatter $skillName $category $keywords)

    [ordered]@{
        name = $skillName
        install_name = $Directory.Name
        description = $description
        capabilities = $capabilities
        keywords = $keywords
        category = $category
        discovered_at = $nowIso
        installed_at = $null
        source = 'unknown'
        provenance = 'unknown'
        source_path = $sourcePath
        link_path = $linkPath
        commit = $null
        sha256 = $null
        status = $status
        health = $health
        usage = [ordered]@{ status = 'unknown'; last_seen = $null; invocation_count = $null }
        agents = [ordered]@{ claude = [ordered]@{ visible = $hasLink; link_path = $linkPath } }
    }
}

function Read-OldIndex {
    if (-not (Test-Path -LiteralPath $IndexPath -PathType Leaf)) { return $null }
    try { return Get-Content -Raw -LiteralPath $IndexPath | ConvertFrom-Json } catch { return $null }
}

function Build-Index {
    $oldIndex = Read-OldIndex
    $nowIso = [DateTime]::UtcNow.ToString('o')
    $scannedDirectories = Get-SkillDirectories
    $scannedNames = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)

    $entries = [System.Collections.Generic.List[object]]::new()
    foreach ($directory in $scannedDirectories) {
        $entry = Read-SkillEntry $directory
        $scannedNames.Add($entry.name) | Out-Null
        $scannedNames.Add($entry.install_name) | Out-Null

        $old = Get-PreviousEntry $oldIndex $entry.name $entry.install_name
        if ($old) {
            if ($old.discovered_at) { $entry.discovered_at = $old.discovered_at }
            elseif ($old.installed_at) { $entry.discovered_at = $old.installed_at }

            if ($old.installed_at) { $entry.installed_at = $old.installed_at }
            if ($old.source -and $old.source -ne 'local') {
                $entry.source = $old.source
                if ($old.source.StartsWith('github:')) { $entry.provenance = 'installer' }
            } else {
                $entry.source = 'unknown'
                $entry.provenance = 'unknown'
            }
            if ($old.provenance) { $entry.provenance = $old.provenance }
            if ($old.commit) { $entry.commit = $old.commit }
            if ($old.sha256) { $entry.sha256 = $old.sha256 }
            if ($old.usage) { $entry.usage = $old.usage }
        }
        $entries.Add([pscustomobject]$entry)
    }

    if ($oldIndex -and $oldIndex.skills) {
        foreach ($oldSkill in $oldIndex.skills) {
            if (-not $scannedNames.Contains($oldSkill.name) -and -not ($oldSkill.install_name -and $scannedNames.Contains($oldSkill.install_name))) {
                $missingEntry = [ordered]@{
                    name = $oldSkill.name
                    install_name = if ($oldSkill.install_name) { $oldSkill.install_name } else { $oldSkill.name }
                    description = if ($oldSkill.description) { $oldSkill.description } else { '' }
                    capabilities = if ($oldSkill.capabilities) { @($oldSkill.capabilities) } else { @($oldSkill.name, 'other') }
                    keywords = if ($oldSkill.keywords) { @($oldSkill.keywords) } else { @($oldSkill.name) }
                    category = if ($oldSkill.category) { $oldSkill.category } else { 'other' }
                    discovered_at = if ($oldSkill.discovered_at) { $oldSkill.discovered_at } else { $nowIso }
                    installed_at = $oldSkill.installed_at
                    source = if ($oldSkill.source -and $oldSkill.source -ne 'local') { $oldSkill.source } else { 'unknown' }
                    provenance = if ($oldSkill.provenance) { $oldSkill.provenance } else { 'unknown' }
                    source_path = if ($oldSkill.source_path) { $oldSkill.source_path } else { "`$CLAUDE_SKILLS_DIR/$($oldSkill.name)" }
                    link_path = ''
                    commit = $oldSkill.commit
                    sha256 = $oldSkill.sha256
                    status = 'broken'
                    health = 'missing'
                    usage = if ($oldSkill.usage) { $oldSkill.usage } else { [ordered]@{ status = 'unknown'; last_seen = $null; invocation_count = $null } }
                    agents = [ordered]@{ claude = [ordered]@{ visible = $false; link_path = '' } }
                }
                $entries.Add([pscustomobject]$missingEntry)
            }
        }
    }

    [ordered]@{
        schema_version = 2
        generated_at = $nowIso
        skills = @($entries | Sort-Object name)
    }
}

function Write-Index([object]$Index) {
    $parent = Split-Path -Parent $IndexPath
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
    $temporary = "$IndexPath.tmp-$([guid]::NewGuid().ToString('N'))"
    $Index | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $temporary -Encoding utf8
    Move-Item -LiteralPath $temporary -Destination $IndexPath -Force
}

function Apply-Registration([object]$Index) {
    if ([string]::IsNullOrWhiteSpace($RegisterName)) { return $Index }
    $entry = @($Index.skills | Where-Object { $_.name -eq $RegisterName -or $_.install_name -eq $RegisterName } | Select-Object -First 1)[0]
    if ($null -eq $entry) { return $Index }
    if ($RegisterSource) {
        $entry.source = $RegisterSource
        if ($RegisterSource.StartsWith('github:')) { $entry.provenance = 'installer' }
    }
    if ($RegisterInstalledAt) {
        $entry.installed_at = $RegisterInstalledAt
        if (-not $entry.discovered_at) { $entry.discovered_at = $RegisterInstalledAt }
    }
    if ($RegisterCommit) { $entry.commit = $RegisterCommit }
    if ($RegisterSha256) { $entry.sha256 = $RegisterSha256 }
    return $Index
}

function Get-Index {
    $index = Read-OldIndex
    if ($null -eq $index -or $index.schema_version -lt 2) {
        $index = Build-Index
        Write-Index $index
    }
    return $index
}

function Get-SearchScore([object]$Entry, [string]$SearchQuery) {
    $terms = Get-AliasTerms $SearchQuery
    $nameLower = $Entry.name.ToLowerInvariant()
    $installLower = if ($Entry.install_name) { $Entry.install_name.ToLowerInvariant() } else { '' }
    $descLower = if ($Entry.description) { $Entry.description.ToLowerInvariant() } else { '' }
    $kwList = @($Entry.keywords | ForEach-Object { $_.ToLowerInvariant() })
    $capList = @($Entry.capabilities | ForEach-Object { $_.ToLowerInvariant() })
    $catLower = if ($Entry.category) { $Entry.category.ToLowerInvariant() } else { '' }
    $searchText = "$nameLower $installLower $descLower $($kwList -join ' ') $($capList -join ' ') $catLower".ToLowerInvariant()

    # Compound AND filters
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
    $qHasUI = ($uiWords | Where-Object { $queryLower.Contains($_) }).Count -gt 0
    $qHasDesign = ($designWords | Where-Object { $queryLower.Contains($_) }).Count -gt 0
    if ($qHasUI -and $qHasDesign) {
        $tHasUI = ($uiWords | Where-Object { $searchText.Contains($_) }).Count -gt 0
        $tHasDesign = ($designWords | Where-Object { $searchText.Contains($_) }).Count -gt 0
        if (-not ($tHasUI -and $tHasDesign)) { return 0 }
    }

    $score = 0
    if ($nameLower -eq $queryLower) { $score += 20 }
    elseif ($nameLower.Contains($queryLower)) { $score += 15 }

    foreach ($term in $terms) {
        if ($nameLower -eq $term) { $score += 12 }
        elseif ($nameLower.Contains($term)) { $score += 8 }
        if ($descLower.Contains($term)) { $score += 3 }
        if ($kwList -contains $term -or ($kwList | Where-Object { $_.Contains($term) }).Count -gt 0) { $score += 3 }
        if ($capList -contains $term -or ($capList | Where-Object { $_.Contains($term) }).Count -gt 0) { $score += 3 }
        if ($catLower -eq $term -or $catLower.Contains($term)) { $score += 5 }
    }
    return $score
}

function Write-Entries([object[]]$Entries) {
    if ($Json) { $Entries | ConvertTo-Json -Depth 8; return }
    Write-Host "Skills: $($Entries.Count)"
    foreach ($entry in $Entries | Sort-Object name) {
        $description = if ($entry.description.Length -gt 78) { $entry.description.Substring(0, 75) + '...' } else { $entry.description }
        $displayName = if ($entry.install_name -and $entry.install_name -ne $entry.name) { "$($entry.name) (install: $($entry.install_name))" } else { $entry.name }
        Write-Host ("{0,-38} [{1,-7}] {2}" -f $displayName, $entry.status, $description)
    }
}

function Write-Capabilities([object]$Index) {
    if ($Json) { $Index | ConvertTo-Json -Depth 8; return }
    $skills = @($Index.skills)
    $broken = @($skills | Where-Object { $_.status -ne 'ok' -or $_.health -in @('broken', 'missing') })
    $okSkills = @($skills | Where-Object { $broken -notcontains $_ })

    $total = $skills.Count
    $brokenCount = $broken.Count
    if ($brokenCount -gt 0) {
        Write-Host "Your Agent currently has $total Skills ($brokenCount broken)`n"
    } else {
        Write-Host "Your Agent currently has $total Skills`n"
    }

    $categories = @(
        @('Documents', 'documents'),
        @('Development', 'development'),
        @('Browser', 'browser'),
        @('Research', 'research'),
        @('Data', 'data'),
        @('Media', 'media'),
        @('Other', 'other')
    )

    foreach ($catPair in $categories) {
        $displayCat = $catPair[0]
        $catKey = $catPair[1]
        $group = @($okSkills | Where-Object { $_.category -eq $catKey })
        if ($group.Count -gt 0) {
            Write-Host "$displayCat ($($group.Count))"
            foreach ($s in ($group | Sort-Object name)) {
                $desc = $s.description
                if ($desc.Length -gt 60) { $desc = $desc.Substring(0, 57) + '...' }
                if (-not $desc) { $desc = '(no description)' }
                Write-Host ("  {0,-20} {1}" -f $s.name, $desc)
            }
            Write-Host ""
        }
    }

    if ($broken.Count -gt 0) {
        Write-Host "Broken ($($broken.Count))"
        foreach ($s in ($broken | Sort-Object name)) {
            $desc = $s.description
            $health = if ($s.health) { $s.health } else { $s.status }
            if (-not $desc) { $desc = "($health)" }
            elseif ($desc.Length -gt 60) { $desc = $desc.Substring(0, 57) + '...' }
            Write-Host ("  {0,-20} {1}" -f $s.name, $desc)
        }
        Write-Host ""
    }
}

function Write-Show([object]$Entry) {
    if ($Json) { $Entry | ConvertTo-Json -Depth 8; return }
    Write-Host "name: $($Entry.name)"
    Write-Host "install_name: $($Entry.install_name)"
    Write-Host "description: $($Entry.description)"
    Write-Host "category: $($Entry.category)"
    Write-Host "capabilities: $((@($Entry.capabilities)) -join ', ')"
    Write-Host "source: $($Entry.source)"
    Write-Host "provenance: $($Entry.provenance)"
    Write-Host "source_path: $($Entry.source_path)"
    Write-Host "link_path: $($Entry.link_path)"
    Write-Host "discovered_at: $($Entry.discovered_at)"
    Write-Host "installed_at: $($Entry.installed_at)"
    Write-Host "commit: $($Entry.commit)"
    Write-Host "sha256: $($Entry.sha256)"
    Write-Host "status: $($Entry.status)"
    Write-Host "health: $($Entry.health)"
    Write-Host "agents.claude.visible: $($Entry.agents.claude.visible)"
    Write-Host "usage.status: $($Entry.usage.status)"
    Write-Host "invocation_hint: Ask Claude Code to use the '$($Entry.name)' skill for a matching task. Automatic invocation is not observable by this catalog."
}

function Invoke-DoctorGlobal([object]$Index) {
    $skills = @($Index.skills)
    $scannedCount = $skills.Count
    $brokenList = @($skills | Where-Object { $_.status -ne 'ok' -or $_.health -eq 'broken' })
    $missingList = @($skills | Where-Object { $_.health -eq 'missing' })
    $healthyCount = $scannedCount - $brokenList.Count - $missingList.Count
    if ($healthyCount -lt 0) { $healthyCount = 0 }

    Write-Host "doctor: scanned $scannedCount skills"
    Write-Host "  healthy: $healthyCount"
    if ($brokenList.Count -gt 0) {
        $brokenNames = (@($brokenList | ForEach-Object name)) -join ', '
        Write-Host "  broken: $($brokenList.Count) ($brokenNames)"
    } else {
        Write-Host "  broken: 0"
    }
    if ($missingList.Count -gt 0) {
        $missingNames = (@($missingList | ForEach-Object name)) -join ', '
        Write-Host "  missing: $($missingList.Count) ($missingNames)"
    } else {
        Write-Host "  missing: 0"
    }

    if ($brokenList.Count -gt 0 -or $missingList.Count -gt 0) {
        exit 1
    }
}

function Invoke-DoctorSingle([string]$SkillName, [object]$Index) {
    $entry = @($Index.skills | Where-Object { $_.name -eq $SkillName -or $_.install_name -eq $SkillName } | Select-Object -First 1)[0]
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
        $rawContent = Get-Content -Raw -LiteralPath $sourceFile
    } elseif ($linkFileExists) {
        $rawContent = Get-Content -Raw -LiteralPath $linkFile
    }

    $frontmatterMatch = [regex]::Match($rawContent, '(?ms)^---\s*\r?\n(.*?)\r?\n---(?:\s*\r?\n|$)')
    $frontmatter = if ($frontmatterMatch.Success) { $frontmatterMatch.Groups[1].Value } else { '' }

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
    if ($sourceFileExists -and $linkFileExists) {
        $srcHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $sourceFile).Hash
        $lnkHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $linkFile).Hash
        if ($srcHash -eq $lnkHash) {
            Write-Host "  ✓ SKILL.md hashes match"
        } else {
            Write-Host "  ✗ SKILL.md hashes differ between source and link"
        }
    } elseif ($sourceFileExists -or $linkFileExists) {
        Write-Host "  ⚠ Single copy found (no link hash comparison)"
    } else {
        Write-Host "  ✗ SKILL.md missing"
    }
    Write-Host ""

    Write-Host "Structure"
    if ($sourceFileExists -or $linkFileExists) {
        Write-Host "  ✓ SKILL.md present"
    } else {
        Write-Host "  ✗ SKILL.md missing"
    }
    if ($frontmatterMatch.Success) {
        Write-Host "  ✓ YAML frontmatter valid"
    } else {
        Write-Host "  ✗ YAML frontmatter missing or invalid"
    }
    if ($declaredName) {
        Write-Host "  ✓ name = $declaredName"
    } else {
        Write-Host "  ✗ name field missing in frontmatter"
    }
    if ($declaredDesc) {
        Write-Host "  ✓ description present"
    } else {
        Write-Host "  ✗ description missing in frontmatter"
    }
    Write-Host ""

    Write-Host "Discovery"
    if ($linkExists) {
        Write-Host "  ✓ Claude link path visible"
    } else {
        Write-Host "  ✗ Claude link path not visible"
    }
    if ($rawContent) {
        Write-Host "  ✓ File readable"
    } else {
        Write-Host "  ✗ File unreadable or empty"
    }
    Write-Host ""

    Write-Host "Trigger quality"
    $triggerWarnings = 0
    if ($declaredDesc) {
        $words = @($declaredDesc -split '\s+' | Where-Object { $_ })
        if ($declaredDesc.Length -lt 20) {
            Write-Host "  ⚠ Description too short (< 20 characters)"
            $suggestions.Add('Expand description to at least 20 characters explaining what the skill does and when to use it')
            $triggerWarnings++
        } else {
            Write-Host "  ✓ Description has $($words.Count) words"
        }

        if ($declaredDesc -match '^(?i)use when') {
            Write-Host "  ✓ Description starts with explicit trigger phrase (`"Use when...`")"
        } elseif ($declaredDesc -match '(?i)when|当用户|当|用于') {
            Write-Host "  ✓ Description contains trigger phrase (`"when`")"
        } else {
            Write-Host "  ⚠ Description doesn't start with `"Use when...`" — Claude's auto-discovery benefits from explicit trigger phrases"
            $suggestions.Add('Start description with "Use when the user wants to..." for better auto-discovery')
            $triggerWarnings++
        }

        $actionWords = @('use', 'create', 'analyze', 'build', 'check', 'inspect', 'run', 'extract', 'convert', 'manage', 'format', 'test', 'search', 'query', 'deploy', 'fix', 'scaffold', 'design', 'write', 'edit', 'review', 'translate', 'summarize', 'crawl', 'scrape', 'monitor', '转换', '提取', '创建', '分析', '构建', '检查', '运行', '调试', '搜索', '编写', '审查', '设计', '做')
        $descLower = $declaredDesc.ToLowerInvariant()
        $hasAction = $false
        foreach ($act in $actionWords) {
            if ($descLower.Contains($act)) { $hasAction = $true; break }
        }
        if (-not $hasAction) {
            Write-Host "  ⚠ Description lacks clear action verbs (use, create, analyze, build, inspect, convert...)"
            $suggestions.Add('Include specific action verbs (e.g. create, convert, analyze) in the description')
            $triggerWarnings++
        }
    } else {
        Write-Host "  ✗ No description found to assess trigger quality"
        $triggerWarnings++
    }

    if ($declaredCaps) {
        Write-Host "  ✓ Capabilities declared: $declaredCaps"
    } else {
        Write-Host "  ⚠ No explicit capabilities tags in frontmatter — auto-derived only"
        $suggestions.Add('Add "capabilities:" to SKILL.md frontmatter for explicit tagging')
        $triggerWarnings++
    }

    $inferredCat = if ($entry -and $entry.category) { $entry.category } else { 'other' }
    if ($declaredCat) {
        Write-Host "  ✓ Category declared: $declaredCat"
    } else {
        Write-Host "  ⚠ No explicit category in frontmatter — auto-bucketed to $inferredCat"
        $suggestions.Add("Add `"category: $inferredCat`" to SKILL.md frontmatter")
        $triggerWarnings++
    }

    if ($triggerWarnings -eq 0) {
        Write-Host "  ✓ Trigger description looks Claude-discoverable"
    }
    Write-Host ""

    if ($suggestions.Count -gt 0) {
        Write-Host "Suggestions:"
        foreach ($s in $suggestions) {
            Write-Host "  - $s"
        }
    }
}

function Get-TriggerWarningCount([string]$Frontmatter, [string]$Desc, [string]$Caps, [string]$Cat) {
    $count = 0
    if (-not $Desc -or $Desc.Length -lt 20) { $count++ }
    elseif (-not ($Desc -match '^(?i)use when')) { $count++ }

    $actionWords = @('use', 'create', 'analyze', 'build', 'check', 'inspect', 'run', 'extract', 'convert', 'manage', 'format', 'test', 'search', 'query', 'deploy', 'fix', 'scaffold', 'design', 'write', 'edit', 'review', 'translate', 'summarize', 'crawl', 'scrape', 'monitor', '转换', '提取', '创建', '分析', '构建', '检查', '运行', '调试', '搜索', '编写', '审查', '设计', '做')
    $descLower = if ($Desc) { $Desc.ToLowerInvariant() } else { '' }
    $hasAction = $false
    foreach ($act in $actionWords) {
        if ($descLower.Contains($act)) { $hasAction = $true; break }
    }
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

    # Case C: 3rd person / introductory phrases with when
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

    # Case B & E: Verb / normal sentence
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

    # Default Case E
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

    $stopWords = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($w in @('use', 'when', 'the', 'user', 'wants', 'to', 'for', 'and', 'or', 'in', 'on', 'with', 'a', 'an', 'is', 'are', 'this', 'skill', 'should', 'be', 'can', 'needs', 'any', 'from', 'into', 'by', 'that', 'as', 'it', 'of', 'at', 'so', 'more', 'reliably', 'auto', 'discover', 'whenever', 'about', 'also', 'all', 'will', 'then', 'than', 'such', 'not', 'out', 'up', 'down', 'only', 'both', 'each', 'how', 'what', 'which', 'who', 'whom', 'whose', 'why', 'where', 'there', 'their', 'they', 'them', 'these', 'those')) {
        $stopWords.Add($w) | Out-Null
    }

    $nameWords = [regex]::Matches($Name.ToLowerInvariant(), '[a-z0-9][a-z0-9_-]{1,}|[\u3400-\u9fff]{2,}') | ForEach-Object { $_.Value }
    $descWords = [regex]::Matches($Description.ToLowerInvariant(), '[a-z0-9][a-z0-9_-]{1,}|[\u3400-\u9fff]{2,}') | ForEach-Object { $_.Value }
    $aliasWords = Get-AliasTerms "$Name $Description"

    $counts = [ordered]@{}
    foreach ($w in $nameWords) {
        if (-not $stopWords.Contains($w) -and $w.Length -ge 2) {
            $counts[$w] = if ($counts.Contains($w)) { $counts[$w] + 10 } else { 10 }
        }
    }
    foreach ($w in $descWords) {
        if (-not $stopWords.Contains($w) -and $w.Length -ge 2) {
            $counts[$w] = if ($counts.Contains($w)) { $counts[$w] + 2 } else { 2 }
        }
    }
    foreach ($w in $aliasWords) {
        if (-not $stopWords.Contains($w) -and $w.Length -ge 2) {
            $counts[$w] = if ($counts.Contains($w)) { $counts[$w] + 3 } else { 3 }
        }
    }

    $sorted = $counts.Keys | Sort-Object { $counts[$_] } -Descending
    $selected = [System.Collections.Generic.List[string]]::new()
    foreach ($k in $sorted) {
        if ($selected.Count -lt 5) {
            $selected.Add($k)
        }
    }
    if ($selected.Count -eq 0) {
        $selected.Add($Name)
        if ($Category -and $Category -ne 'other') { $selected.Add($Category) }
    }
    return @($selected)
}

function Build-FixedFrontmatter([string]$RawContent, [string]$Name, [string]$NewDesc, [string[]]$NewCaps, [string]$NewCat) {
    $match = [regex]::Match($RawContent, '(?ms)^---\s*\r?\n(.*?)\r?\n---(?:\s*\r?\n|$)')
    $oldFrontmatter = if ($match.Success) { $match.Groups[1].Value } else { '' }
    $body = if ($match.Success) { $RawContent.Substring($match.Length) } else { $RawContent }

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('---')
    $lines.Add("name: $Name")
    $lines.Add("description: $NewDesc")
    $lines.Add('capabilities:')
    foreach ($cap in $NewCaps) {
        $lines.Add("  - $cap")
    }
    $lines.Add("category: $NewCat")

    # Keep any other custom fields from old frontmatter
    $knownFields = @('name', 'description', 'capabilities', 'category')
    $inSkippedBlock = $false
    foreach ($line in ($oldFrontmatter -split "`r?`n")) {
        $trimmed = $line.Trim()
        if (-not $trimmed) { continue }
        if ($line[0] -eq ' ' -or $line[0] -eq "`t") {
            if ($inSkippedBlock) { continue }
            $lines.Add($line)
            continue
        }
        $key = ($line -split ':', 2)[0].Trim()
        if ($key -in $knownFields) {
            $inSkippedBlock = $true
        } else {
            $inSkippedBlock = $false
            $lines.Add($line)
        }
    }

    $lines.Add('---')
    $newFrontmatterText = ($lines -join "`n")
    return "$newFrontmatterText`n$body"
}

function Invoke-FixSkill([object]$Entry, [bool]$IsDryRun, [bool]$AssumeYes) {
    $dirName = if ($Entry.install_name) { $Entry.install_name } else { $Entry.name }
    $sourceDisk = Join-Path $SkillsDir $dirName
    $linkDisk = Join-Path $LinkDir $dirName
    $sourceFile = Join-Path $sourceDisk 'SKILL.md'
    $linkFile = Join-Path $linkDisk 'SKILL.md'

    $targetFile = $null
    if (Test-Path -LiteralPath $sourceFile -PathType Leaf) {
        $targetFile = $sourceFile
    } elseif (Test-Path -LiteralPath $linkFile -PathType Leaf) {
        $targetFile = $linkFile
    } else {
        Write-Host "skipping $($Entry.name): SKILL.md not found"
        return
    }

    $isSymlink = Test-IsSymlinkOrReparse $targetFile
    $rawContent = Get-Content -Raw -LiteralPath $targetFile
    $frontmatterMatch = [regex]::Match($rawContent, '(?ms)^---\s*\r?\n(.*?)\r?\n---(?:\s*\r?\n|$)')
    if (-not $frontmatterMatch.Success) {
        Write-Host "skipping $($Entry.name): invalid or missing YAML frontmatter"
        return
    }
    $frontmatter = $frontmatterMatch.Groups[1].Value
    $oldName = Get-FrontmatterField $frontmatter 'name'
    $oldDesc = Get-FrontmatterField $frontmatter 'description'
    $oldCaps = Get-FrontmatterField $frontmatter 'capabilities'
    $oldCat = Get-FrontmatterField $frontmatter 'category'

    if (-not $oldName) { $oldName = $Entry.name }
    if (-not $oldDesc) {
        Write-Host "skipping $($Entry.name): description missing in frontmatter"
        return
    }

    $descFix = Get-RewrittenDescription $oldDesc
    if ($descFix.Skip) {
        Write-Host "skipping $($Entry.name): $($descFix.Reason)"
        return
    }

    $newDesc = $descFix.Text
    $newCaps = Get-TopCapabilities $frontmatter $oldName $newDesc $Entry.category
    $newCat = if ($oldCat) { $oldCat } else { $Entry.category }
    if (-not $newCat) { $newCat = 'other' }

    $backupDir = Join-Path $SkillsDir '.backups'
    $timestamp = [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')
    $backupPath = Join-Path $backupDir "$($Entry.name)-$timestamp-SKILL.md"

    $fixedContent = Build-FixedFrontmatter $rawContent $oldName $newDesc $newCaps $newCat

    if ($isSymlink) {
        Write-Host "refusing to modify symlink: $targetFile; suggested patch for $($Entry.name):"
        Write-Host "---"
        Write-Host "name: $oldName"
        Write-Host "description: $newDesc"
        Write-Host "capabilities:"
        foreach ($c in $newCaps) { Write-Host "  - $c" }
        Write-Host "category: $newCat"
        Write-Host "---"
        return
    }

    if ($IsDryRun) {
        Write-Host "[proposed] $($Entry.name)`n"
        Write-Host "description (before):"
        Write-Host "  $oldDesc`n"
        Write-Host "description (after):"
        Write-Host "  $newDesc`n"
        Write-Host "capabilities (added):"
        foreach ($c in $newCaps) { Write-Host "  - $c" }
        Write-Host "`ncategory (added):"
        Write-Host "  $newCat`n"
        Write-Host "no symlink. backup would go to: `$CLAUDE_SKILLS_DIR/.backups/$($Entry.name)-$timestamp-SKILL.md`n"
        return
    }

    if (-not $AssumeYes) {
        $resp = Read-Host "Apply fix to $($Entry.name)? [y/N]"
        if ($resp -notmatch '^(?i)y(?:es)?$') {
            Write-Host "Skipped $($Entry.name)."
            return
        }
    }

    # Execute Backup
    New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
    Copy-Item -LiteralPath $targetFile -Destination $backupPath -Force

    # Write Fixed File
    Set-Content -LiteralPath $targetFile -Value $fixedContent -Encoding utf8

    # Verify Written File
    $writtenCheck = Get-Content -Raw -LiteralPath $targetFile
    $checkMatch = [regex]::Match($writtenCheck, '(?ms)^---\s*\r?\n(.*?)\r?\n---(?:\s*\r?\n|$)')
    if (-not $checkMatch.Success) {
        Write-Host "ERROR: verification failed after writing $targetFile. Restoring backup..."
        Copy-Item -LiteralPath $backupPath -Destination $targetFile -Force
        return
    }

    $beforeWarnings = Get-TriggerWarningCount $frontmatter $oldDesc $oldCaps $oldCat
    $afterWarnings = Get-TriggerWarningCount $checkMatch.Groups[1].Value $newDesc ($newCaps -join ',') $newCat

    Write-Host "fixed $($Entry.name): description rewritten, capabilities + category added"
    Write-Host "  trigger quality: $afterWarnings ⚠ (was $beforeWarnings ⚠)"
}

$index = Get-Index
switch ($Command) {
    'refresh' {
        $index = Build-Index
        $index = Apply-Registration $index
        Write-Index $index
        Write-Entries @($index.skills)
    }
    'capabilities' {
        Write-Capabilities $index
    }
    'list' {
        Write-Entries @($index.skills)
    }
    'find' {
        if ([string]::IsNullOrWhiteSpace($Query)) { throw 'find needs -Query.' }
        $scored = @($index.skills | ForEach-Object {
            $score = Get-SearchScore $_ $Query
            if ($score -gt 0) { [pscustomobject]@{ Score = $score; Entry = $_ } }
        } | Sort-Object Score -Descending)

        if ($scored.Count -eq 0) {
            Write-Host "No matching skills for `"$Query`"."
            exit 0
        }

        if ($Json) {
            $scored | ForEach-Object { $_.Entry } | ConvertTo-Json -Depth 8
            exit 0
        }

        $topList = @($scored | Select-Object -First $Limit)
        Write-Host "Matches for `"$Query`":`n"
        for ($i = 0; $i -lt $topList.Count; $i++) {
            $item = $topList[$i]
            $entry = $item.Entry
            $scoreVal = $item.Score
            $num = $i + 1
            $desc = if ($entry.description) { $entry.description } else { '(no description)' }
            if ($desc.Length -gt 75) { $desc = $desc.Substring(0, 72) + '...' }
            Write-Host ("  {0,2}. {1,-28} (score: {2})" -f $num, $entry.name, $scoreVal)
            Write-Host "     $desc`n"
        }
        Write-Host "Found $($scored.Count) matches. Showing top $($topList.Count)."
    }
    'show' {
        if ([string]::IsNullOrWhiteSpace($Name)) { throw 'show needs -Name.' }
        $entry = @($index.skills | Where-Object { $_.name -eq $Name -or $_.install_name -eq $Name } | Select-Object -First 1)[0]
        if ($null -eq $entry) { throw "Skill not found: $Name" }
        Write-Show $entry
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


