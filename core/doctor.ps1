# core/doctor.ps1 - Diagnostic checks and 8-rule trigger quality engine

$global:DoctorPrototypeVerbs = [ordered]@{
    'use'       = @('use', 'using', 'used', 'uses')
    'create'    = @('create', 'creating', 'created', 'creates', 'creation')
    'build'     = @('build', 'building', 'built', 'builds')
    'generate'  = @('generate', 'generating', 'generated', 'generates', 'generation')
    'analyze'   = @('analyze', 'analyzing', 'analyzed', 'analyzes', 'analysis', 'analytics')
    'find'      = @('find', 'finding', 'found', 'finds')
    'check'     = @('check', 'checking', 'checked', 'checks')
    'inspect'   = @('inspect', 'inspecting', 'inspected', 'inspects', 'inspection')
    'run'       = @('run', 'running', 'ran', 'runs')
    'convert'   = @('convert', 'converting', 'converted', 'converts', 'conversion')
    'translate' = @('translate', 'translating', 'translated', 'translates', 'translation')
    'design'    = @('design', 'designing', 'designed', 'designs')
    'write'     = @('write', 'writing', 'written', 'writes', 'wrote')
    'read'      = @('read', 'reading', 'reads')
    'manage'    = @('manage', 'managing', 'managed', 'manages', 'management')
    'deploy'    = @('deploy', 'deploying', 'deployed', 'deploys', 'deployment')
    'test'      = @('test', 'testing', 'tested', 'tests')
    'validate'  = @('validate', 'validating', 'validated', 'validates', 'validation')
    'summarize' = @('summarize', 'summarizing', 'summarized', 'summarizes', 'summary')
    'search'    = @('search', 'searching', 'searched', 'searches')
}

function Test-TriggerQualityRules([string]$Frontmatter, [string]$Description, [string]$Capabilities, [string]$Category) {
    $passed = 0
    $warnings = 0
    $details = [System.Collections.Generic.List[object]]::new()
    $recommendations = [System.Collections.Generic.List[string]]::new()
    $descTrim = if ($Description) { $Description.Trim() } else { '' }
    $descLower = $descTrim.ToLowerInvariant()

    # Rule 1: Trigger prefix
    if ($descTrim -and ($descLower -match '^(?i)(?:use when|this skill should be used when|trigger when|you must use this when)')) {
        $passed++
        $details.Add([pscustomobject]@{ Status = '✓'; Text = 'Description starts with explicit trigger phrase ("Use when...")' })
    } elseif ($descTrim -and ($descLower.Contains('when') -or $descLower.Contains('whenever'))) {
        $passed++
        $details.Add([pscustomobject]@{ Status = '✓'; Text = 'Description contains trigger phrase ("when")' })
    } else {
        $warnings++
        $details.Add([pscustomobject]@{ Status = '⚠'; Text = 'Description lacks explicit trigger phrase ("Use when...")' })
        $recommendations.Add('Start description with "Use when the user wants to..."')
    }

    # Rule 2: Contains action verbs
    $actionWords = @('use', 'create', 'analyze', 'build', 'check', 'inspect', 'run', 'extract', 'convert', 'manage', 'format', 'test', 'search', 'query', 'deploy', 'fix', 'scaffold', 'design', 'write', 'edit', 'review', 'translate', 'summarize', 'crawl', 'scrape', 'monitor', '转换', '提取', '创建', '分析', '构建', '检查', '运行', '调试', '搜索', '编写', '审查', '设计', '做')
    $hasAction = ($actionWords | Where-Object { $descLower.Contains($_) }).Count -gt 0
    if ($hasAction) {
        $passed++
        $details.Add([pscustomobject]@{ Status = '✓'; Text = 'Description contains action verbs' })
    } else {
        $warnings++
        $details.Add([pscustomobject]@{ Status = '⚠'; Text = 'Description lacks clear action verbs' })
        $recommendations.Add('Add action verbs (e.g. create, analyze, convert, manage) to description')
    }

    # Rule 3: Verb diversity (>= 3 prototype verbs)
    $foundVerbs = [System.Collections.Generic.List[string]]::new()
    foreach ($pv in $global:DoctorPrototypeVerbs.Keys) {
        foreach ($form in $global:DoctorPrototypeVerbs[$pv]) {
            if ($descLower -match ('\b' + [regex]::Escape($form) + '\b')) {
                $foundVerbs.Add($pv)
                break
            }
        }
    }
    if ($foundVerbs.Count -ge 3) {
        $passed++
        $vStr = ($foundVerbs | Select-Object -First 5) -join ', '
        $details.Add([pscustomobject]@{ Status = '✓'; Text = "Rich verb diversity ($($foundVerbs.Count) action verbs: $vStr)" })
    } elseif ($foundVerbs.Count -gt 0) {
        $warnings++
        $vStr = $foundVerbs -join ', '
        $details.Add([pscustomobject]@{ Status = '⚠'; Text = "Consider more action verbs (found $($foundVerbs.Count): $vStr)" })
        $recommendations.Add('Include at least 3 distinct action verbs to broaden trigger recognition')
    } else {
        $warnings++
        $details.Add([pscustomobject]@{ Status = '⚠'; Text = 'No action verbs detected' })
        $recommendations.Add('Include at least 3 distinct action verbs (e.g. use, create, manage)')
    }

    # Rule 4: Concrete examples
    $exampleMarkers = @('e.g.', '例如', '比如', 'such as', 'examples include', 'for example')
    $hasExample = ($exampleMarkers | Where-Object { $descLower.Contains($_) }).Count -gt 0
    if ($hasExample) {
        $passed++
        $details.Add([pscustomobject]@{ Status = '✓'; Text = 'Concrete examples present' })
    } else {
        $warnings++
        $details.Add([pscustomobject]@{ Status = '⚠'; Text = 'No concrete examples; consider adding (e.g., "for example, ...")' })
        $recommendations.Add('Consider adding concrete examples (e.g., "for example, ...")')
    }

    # Rule 5: Appropriate length (30-200 chars)
    $charLen = $descTrim.Length
    if ($charLen -ge 30 -and $charLen -le 200) {
        $passed++
        $details.Add([pscustomobject]@{ Status = '✓'; Text = "Appropriate length ($charLen chars)" })
    } elseif ($charLen -lt 30) {
        $warnings++
        $details.Add([pscustomobject]@{ Status = '⚠'; Text = "Description too short ($charLen chars, recommend 30-200)" })
        $recommendations.Add('Expand description to between 30 and 200 characters')
    } else {
        $warnings++
        $details.Add([pscustomobject]@{ Status = '⚠'; Text = "Description too long ($charLen chars, recommend 30-200; risk of dilution)" })
        $recommendations.Add('Trim description to between 30 and 200 characters to avoid trigger dilution')
    }

    # Rule 6: Well-formed first sentence (no list marker at beginning)
    $isListStart = ($descTrim -match '^\s*(?:[-*•]|\d+[\.\)])\s+')
    if (-not $isListStart -and $charLen -gt 0) {
        $passed++
        $details.Add([pscustomobject]@{ Status = '✓'; Text = 'Well-formed first sentence' })
    } else {
        $warnings++
        $details.Add([pscustomobject]@{ Status = '⚠'; Text = 'First sentence looks like a list; rewrite as prose' })
        $recommendations.Add('Rewrite initial bullet list as a continuous prose sentence')
    }

    # Rule 7: Explicit capabilities
    if ($Capabilities) {
        $passed++
        $details.Add([pscustomobject]@{ Status = '✓'; Text = "Capabilities declared: [$Capabilities]" })
    } else {
        $warnings++
        $details.Add([pscustomobject]@{ Status = '⚠'; Text = 'No explicit capabilities tags in frontmatter — auto-derived only' })
        $recommendations.Add('Add "capabilities: [...]" to SKILL.md frontmatter')
    }

    # Rule 8: Explicit category
    if ($Category) {
        $passed++
        $details.Add([pscustomobject]@{ Status = '✓'; Text = "Category declared: $Category" })
    } else {
        $warnings++
        $details.Add([pscustomobject]@{ Status = '⚠'; Text = 'No explicit category in frontmatter — auto-bucketed' })
        $recommendations.Add('Add "category: <cat>" to SKILL.md frontmatter')
    }

    $scorePct = [math]::Round(($passed / 8.0) * 100, 1)
    return [pscustomobject]@{
        Passed = $passed
        Warnings = $warnings
        Score = $scorePct
        Details = $details
        Recommendations = $recommendations
    }
}

function Get-TriggerWarningCount([string]$Frontmatter, [string]$Desc, [string]$Caps, [string]$Cat) {
    $res = Test-TriggerQualityRules $Frontmatter $Desc $Caps $Cat
    return $res.Warnings
}
