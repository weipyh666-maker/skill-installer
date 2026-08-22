[CmdletBinding()]
param(
    [ValidateSet('list', 'find', 'show', 'doctor', 'refresh')]
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

function Get-Description([string]$Text) {
    $frontmatterMatch = [regex]::Match($Text, '(?ms)^---\s*\r?\n(.*?)\r?\n---(?:\s*\r?\n|$)')
    $frontmatter = if ($frontmatterMatch.Success) { $frontmatterMatch.Groups[1].Value } else { $Text }
    $lineList = $frontmatter -split "`r?`n"
    $descIndex = -1
    $style = $null
    for ($i = 0; $i -lt $lineList.Count; $i++) {
        $marker = [regex]::Match($lineList[$i].Trim(), '^description:\s*([>|])$')
        if ($marker.Success) { $descIndex = $i; $style = $marker.Groups[1].Value; break }
        if ([regex]::IsMatch($lineList[$i], '^description:\s*\S')) { $descIndex = $i; break }
    }
    if ($descIndex -lt 0) { return '' }
    if ($null -eq $style) {
        $value = ($lineList[$descIndex] -split ':', 2)[1].Trim().Trim('"')
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

function Get-PreviousEntry([object]$OldIndex, [string]$SkillName) {
    if ($null -eq $OldIndex) { return $null }
    return @($OldIndex.skills | Where-Object { $_.name -eq $SkillName } | Select-Object -First 1)[0]
}

function Read-SkillEntry([object]$Directory) {
    $skillFile = Join-Path $Directory.Path 'SKILL.md'
    $linkPath = if ($Directory.Root -eq $LinkDir) { $Directory.Path } else {
        $candidate = Join-Path $LinkDir $Directory.Name
        if (Test-Path -LiteralPath $candidate) { $candidate } else { $null }
    }
    $sourcePath = '$CLAUDE_SKILLS_DIR/' + $Directory.Name
    $linkPath = '$CLAUDE_SKILLS_LINK_DIR/' + $Directory.Name
    if (-not (Test-Path -LiteralPath $skillFile -PathType Leaf)) {
        return [ordered]@{
            name = $Directory.Name
            install_name = $Directory.Name
            description = ''
            keywords = @()
            source = 'unknown'
            source_path = $sourcePath
            link_path = $linkPath
            installed_at = $null
            commit = $null
            sha256 = $null
            status = 'broken'
            usage = [ordered]@{ status = 'unknown'; last_seen = $null; invocation_count = $null }
        }
    }
    $content = Get-Content -Raw -LiteralPath $skillFile
    $nameMatch = [regex]::Match($content, '(?m)^name:\s*([a-z0-9][a-z0-9-]{0,63})\s*$')
    $description = Get-Description $content
    $status = if ($nameMatch.Success -and $description) { 'ok' } else { 'broken' }
    $skillName = if ($nameMatch.Success) { $nameMatch.Groups[1].Value } else { $Directory.Name }
    [ordered]@{
        name = $skillName
        install_name = $Directory.Name
        description = $description
        keywords = @(Get-Keywords $skillName $description)
        source = 'unknown'
        source_path = $sourcePath
        link_path = $linkPath
        installed_at = $null
        commit = $null
        sha256 = $null
        status = $status
        usage = [ordered]@{ status = 'unknown'; last_seen = $null; invocation_count = $null }
    }
}

function Read-OldIndex {
    if (-not (Test-Path -LiteralPath $IndexPath -PathType Leaf)) { return $null }
    try { return Get-Content -Raw -LiteralPath $IndexPath | ConvertFrom-Json } catch { return $null }
}

function Build-Index {
    $oldIndex = Read-OldIndex
    $entries = foreach ($directory in Get-SkillDirectories) {
        $entry = Read-SkillEntry $directory
        $old = Get-PreviousEntry $oldIndex $entry.name
        if ($old) {
            if ($old.installed_at) { $entry.installed_at = $old.installed_at }
            if ($old.source -and $old.source -ne 'local') { $entry.source = $old.source }
            if ($old.commit) { $entry.commit = $old.commit }
            if ($old.sha256) { $entry.sha256 = $old.sha256 }
            if ($old.usage) { $entry.usage = $old.usage }
        }
        [pscustomobject]$entry
    }
    [ordered]@{
        schema_version = 1
        generated_at = [DateTime]::UtcNow.ToString('o')
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
    if ($RegisterSource) { $entry.source = $RegisterSource }
    if ($RegisterInstalledAt) { $entry.installed_at = $RegisterInstalledAt }
    if ($RegisterCommit) { $entry.commit = $RegisterCommit }
    if ($RegisterSha256) { $entry.sha256 = $RegisterSha256 }
    return $Index
}

function Get-Index {
    $index = Read-OldIndex
    if ($null -eq $index) {
        $index = Build-Index
        Write-Index $index
    }
    return $index
}

function Get-SearchScore([object]$Entry, [string]$SearchQuery) {
    $terms = Get-AliasTerms $SearchQuery
    $nameText = $Entry.name.ToLowerInvariant()
    $searchText = "$($Entry.name) $($Entry.install_name) $($Entry.description) $($Entry.keywords -join ' ')".ToLowerInvariant()
    $isChineseCompound = $SearchQuery -match '[\u3400-\u9fff]' -and $SearchQuery -match '(图片|图像|照片|截图)' -and $SearchQuery -match '(识别|理解|OCR)'
    # Compound query (bilingual): image-class AND recognition-class words.
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

function Write-Show([object]$Entry) {
    if ($Json) { $Entry | ConvertTo-Json -Depth 8; return }
    Write-Host "name: $($Entry.name)"
    Write-Host "install_name: $($Entry.install_name)"
    Write-Host "description: $($Entry.description)"
    Write-Host "source: $($Entry.source)"
    Write-Host "source_path: $($Entry.source_path)"
    Write-Host "link_path: $($Entry.link_path)"
    Write-Host "installed_at: $($Entry.installed_at)"
    Write-Host "commit: $($Entry.commit)"
    Write-Host "sha256: $($Entry.sha256)"
    Write-Host "status: $($Entry.status)"
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
        $broken = @($fresh.skills | Where-Object { $_.status -ne 'ok' })
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
