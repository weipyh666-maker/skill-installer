[CmdletBinding()]
param(
    [ValidateSet('list', 'find', 'show', 'doctor', 'refresh', 'capabilities')]
    [string]$Command = 'list',
    [string]$Query,
    [string]$Name,
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

function Get-AliasTerms([string]$Text) {
    $map = [ordered]@{
        '图片' = @('image', 'vision', 'photo', 'screenshot', 'ocr')
        '识别' = @('recognition', 'ocr', 'understanding', 'detect', 'identify')
        'ppt' = @('presentation', 'slides', 'deck', 'pptx')
        '演示' = @('presentation', 'slides', 'deck', 'pptx')
        '幻灯片' = @('presentation', 'slides', 'deck', 'pptx')
        '文档' = @('document', 'docs', 'docx', 'pdf')
        '表格' = @('spreadsheet', 'xlsx', 'excel', 'csv')
        '网页' = @('web', 'website', 'browser', 'frontend')
        '代码' = @('code', 'coding', 'development', 'programming')
        '调试' = @('debug', 'debugging', 'diagnosis', 'bug')
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
        $marker = [regex]::Match($lineList[$i].Trim(), "^$($Field):\s*([>|])$")
        if ($marker.Success) { $descIndex = $i; $style = $marker.Groups[1].Value; break }
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
        if ($line[0] -eq ' ' -or $line[0] -eq "`t") { $collected.Add($line.Trim()) }
        else { break }
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
    # Derive capabilities from keywords / category
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
            # Migrate v1/old data without losing metadata
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

    # Handle missing entries (were in index but no longer on disk)
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
    $nameText = $Entry.name.ToLowerInvariant()
    $searchText = "$($Entry.name) $($Entry.install_name) $($Entry.description) $($Entry.keywords -join ' ') $($Entry.capabilities -join ' ')".ToLowerInvariant()
    $isChineseCompound = $SearchQuery -match '[\u3400-\u9fff]' -and $SearchQuery -match '(图片|图像|照片|截图)' -and $SearchQuery -match '(识别|理解|OCR)'
    $imageWords = @('image', 'vision', 'photo', 'screenshot', 'picture')
    $recogWords = @('recogni', 'ocr', 'detect', 'identif', 'understand', 'classif')
    $queryLower = $SearchQuery.ToLowerInvariant()
    $hasImage = ($imageWords | Where-Object { $queryLower.Contains($_) }).Count -gt 0
    $hasRecog = ($recogWords | Where-Object { $queryLower.Contains($_) }).Count -gt 0
    if ($isChineseCompound -or ($hasImage -and $hasRecog)) {
        $imageHit = $false
        $recognitionHit = $false
        foreach ($term in @('image', 'vision', 'photo', 'screenshot', 'picture')) { if ($searchText.Contains($term)) { $imageHit = $true } }
        foreach ($term in @('recogni', 'ocr', 'detect', 'identif', 'understand', 'classif')) { if ($searchText.Contains($term)) { $recognitionHit = $true } }
        if (-not ($imageHit -and $recognitionHit)) { return 0 }
    }
    $score = 0
    foreach ($term in $terms) {
        if ($nameText -eq $term) { $score += 12 }
        elseif ($nameText.Contains($term)) { $score += 8 }
        elseif ($searchText.Contains($term)) { $score += 3 }
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
        $matches = @($index.skills | ForEach-Object {
            $score = Get-SearchScore $_ $Query
            if ($score -gt 0) { [pscustomobject]@{ Score = $score; Entry = $_ } }
        } | Sort-Object Score -Descending | ForEach-Object { $_.Entry })
        if ($matches.Count -eq 0) { Write-Host "No matching skills for '$Query'."; exit 1 }
        Write-Entries $matches
    }
    'show' {
        if ([string]::IsNullOrWhiteSpace($Name)) { throw 'show needs -Name.' }
        $entry = @($index.skills | Where-Object { $_.name -eq $Name -or $_.install_name -eq $Name } | Select-Object -First 1)[0]
        if ($null -eq $entry) { throw "Skill not found: $Name" }
        Write-Show $entry
    }
    'doctor' {
        $fresh = Build-Index
        $broken = @($fresh.skills | Where-Object { $_.status -ne 'ok' -or $_.health -in @('broken', 'missing') })
        $duplicates = @($fresh.skills | Group-Object name | Where-Object Count -gt 1)
        if ($broken.Count -gt 0 -or $duplicates.Count -gt 0) {
            if ($broken.Count -gt 0) { Write-Host "broken: $((@($broken | ForEach-Object name)) -join ', ')" }
            if ($duplicates.Count -gt 0) { Write-Host "duplicates: $((@($duplicates | ForEach-Object Name)) -join ', ')" }
            Write-Host "doctor: issues found; $($fresh.skills.Count) skills scanned"
            exit 1
        }
        Write-Host "doctor: OK; $($fresh.skills.Count) skills indexed; usage status is unknown unless the host provides invocation events."
    }
}

