# core/search.ps1 - Intent matching and score-ranked skill search

$global:StopWordsSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
@(
    'a', 'an', 'the', 'in', 'on', 'at', 'to', 'for', 'of', 'and', 'or', 'is', 'are', 'with',
    'by', 'that', 'this', 'from', 'as', 'it', 'its', 'be', 'can', 'do', 'does', 'did', 'have',
    'has', 'had', 'will', 'would', 'shall', 'should', 'may', 'might', 'must', 'find', 'skill',
    'skills', 'handles', 'handled', 'handling', 'what', 'which', 'how', 'who', 'whom', 'where',
    'when', 'why', 'there', 'their', 'them', 'they', 'i', 'me', 'my', 'we', 'us', 'our', 'you',
    'your', 'he', 'him', 'his', 'she', 'her', 'claude', 'code', 'agent', 'assistant',
    '我', '你', '他', '她', '它', '我们', '你们', '他们', '的', '了', '在', '是', '有', '和', '就',
    '不', '人', '都', '一', '一个', '上', '也', '很', '到', '说', '要', '去', '会', '着',
    '没有', '看', '好', '自己', '这', '个', '装', '装过', '我装了', '我记得', '记得', '但是',
    '但是忘了名字', '忘了名字', '但是忘了', '帮我找', '帮我', '有没有', '能够', '可以', '能', '处理',
    '做', '用', '使用'
) | ForEach-Object { $null = $global:StopWordsSet.Add($_) }

$global:SynonymsMap = [ordered]@{
    'ppt' = @('pptx', 'presentation', 'slides', 'deck', 'powerpoint', 'slide')
    'pptx' = @('presentation', 'slides', 'deck', 'powerpoint', 'slide')
    'powerpoint' = @('pptx', 'presentation', 'slides', 'deck')
    '幻灯片' = @('pptx', 'presentation', 'slides', 'deck', 'powerpoint')
    '演示' = @('presentation', 'slides', 'deck', 'pptx')
    'excel' = @('xlsx', 'spreadsheet', 'spreadsheets', 'csv', 'table')
    'xlsx' = @('spreadsheet', 'spreadsheets', 'excel', 'csv')
    '表格' = @('xlsx', 'spreadsheet', 'spreadsheets', 'excel', 'csv')
    '电子表格' = @('xlsx', 'spreadsheet', 'spreadsheets', 'excel')
    'word' = @('docx', 'document', 'doc', 'word')
    'docx' = @('document', 'doc', 'word')
    '文档' = @('document', 'docs', 'docx', 'pdf')
    'pdf' = @('pdf', 'document')
    '图片' = @('image', 'vision', 'photo', 'screenshot', 'picture')
    '图像' = @('image', 'vision', 'photo', 'screenshot', 'picture')
    '照片' = @('image', 'vision', 'photo', 'screenshot')
    '截图' = @('screenshot', 'image', 'vision')
    '识别' = @('recognition', 'recognize', 'detect', 'ocr', 'identify', 'understanding')
    '理解' = @('understanding', 'recognition', 'vision')
    '语音' = @('audio', 'speech', 'transcribe', 'transcription', 'transcript', 'voice')
    '录音' = @('audio', 'recording', 'transcribe', 'transcription')
    '音频' = @('audio', 'sound', 'speech')
    '转文字' = @('transcribe', 'transcription', 'transcript', 'audio')
    '转录' = @('transcribe', 'transcription', 'transcript')
    '视频' = @('video', 'clip', 'editing', 'ffmpeg')
    '剪辑' = @('video', 'editing', 'edit', 'ffmpeg', 'cut')
    '字幕' = @('transcript', 'transcription', 'subtitles', 'youtube')
    'youtube' = @('youtube', 'video', 'transcript', 'summarizer')
    '总结' = @('summarize', 'summarizer', 'summary', 'digest')
    '网页' = @('web', 'website', 'frontend', 'ui', 'interface', 'page')
    '前端' = @('frontend', 'ui', 'web', 'interface', 'design', 'layout')
    '界面' = @('ui', 'interface', 'frontend', 'gui')
    'ui' = @('ui', 'interface', 'frontend', 'gui', 'design')
    '设计' = @('design', 'craft', 'create', 'layout')
    '测试' = @('test', 'testing', 'e2e', 'qa', 'tdd')
    '端到端' = @('e2e', 'playwright', 'end-to-end', 'testing')
    'playwright' = @('e2e', 'playwright', 'browser', 'testing')
    'e2e' = @('e2e', 'playwright', 'testing', 'end-to-end')
    'git' = @('git', 'github', 'guardrails', 'commit', 'push', 'branch')
    '误推' = @('guardrails', 'dangerous', 'push', 'prevent', 'block')
    '安全' = @('security', 'audit', 'auth', 'authentication', 'secrets')
    '鉴权' = @('authentication', 'auth', 'security', 'secrets')
    '认证' = @('authentication', 'auth', 'security')
    '防泄漏' = @('secrets', 'security', 'guardrails')
    '代码评审' = @('review', 'code review', 'spec', 'standards')
    '评审' = @('review', 'code review', 'spec')
    '审查' = @('review', 'audit', 'inspection')
    '发布' = @('ship', 'deploy', 'release', 'publish')
    '发版' = @('ship', 'release', 'bump version', 'deploy')
    'ship' = @('ship', 'release', 'deploy', 'publish')
    'prd' = @('prd', 'product', 'requirements', 'issues', 'specification')
    '需求' = @('prd', 'requirements', 'issues', 'spec')
    '工单' = @('issues', 'triage', 'tickets')
    'issues' = @('issues', 'triage', 'github', 'tickets')
    '提示词' = @('prompt', 'prompts', 'prompt-engineer', 'system prompt')
    'prompt' = @('prompt', 'prompts', 'prompt-engineer')
    'prompts' = @('prompt', 'prompts', 'prompt-engineer')
    '知识库' = @('vault', 'notes', 'obsidian', 'knowledge')
    '笔记' = @('notes', 'vault', 'obsidian', 'notebook')
    'obsidian' = @('obsidian', 'vault', 'notes', 'second-brain')
    '调研' = @('research', 'survey', 'investigate', 'intel')
    '研究' = @('research', 'study', 'papers', 'survey')
    '竞品' = @('competitive', 'market', 'competitor', 'analysis')
    '市场' = @('market', 'industry', 'research')
    '战略' = @('strategic', 'strategy', 'mckinsey', 'executive')
    '咨询' = @('consulting', 'strategist', 'mckinsey')
    '麦肯锡' = @('mckinsey', 'mckinsey-strategist', 'strategy')
    '架构' = @('architecture', 'architect', 'senior-solution-architect', 'c4', 'adr')
    'c4' = @('c4', 'architecture', 'senior-solution-architect', 'diagram')
    'adr' = @('adr', 'architecture', 'senior-solution-architect', 'decision')
    'rest' = @('rest', 'api', 'api-design', 'endpoint')
    'api' = @('api', 'rest', 'endpoint', 'interface')
    '后端' = @('backend', 'database', 'server', 'express', 'node')
    '数据库' = @('database', 'sql', 'backend', 'db')
    '压缩' = @('compress', 'caveman', 'compressed', 'cut')
    'token' = @('token', 'tokens', 'caveman', 'compression')
    'caveman' = @('caveman', 'compressed', 'tokens')
    '数据集' = @('dataset', 'datasets', 'parquet', 'huggingface')
    'dataset' = @('dataset', 'datasets', 'parquet', 'huggingface')
    'datasets' = @('dataset', 'datasets', 'parquet', 'huggingface')
    '论文' = @('paper', 'papers', 'arxiv', 'huggingface-papers')
    'arxiv' = @('arxiv', 'papers', 'paper', 'research')
    '股票' = @('stock', 'stocks', 'finance', 'financial', 'fincept')
    '行情' = @('market', 'ticker', 'finance', 'stock')
    '金融' = @('finance', 'financial', 'fincept', 'market')
    '终端' = @('terminal', 'fincept')
    '克隆' = @('clone', 'cloner', 'website-cloner', 'copy')
    '复刻' = @('clone', 'cloner', 'website-cloner')
}

function Get-WordStem([string]$Word) {
    $w = $Word.ToLowerInvariant().Trim("`,.?!:;()[]{}'""`$")
    if ($w.Length -gt 5 -and $w.EndsWith('ing')) { return $w.Substring(0, $w.Length - 3) }
    if ($w.Length -gt 4 -and $w.EndsWith('ed')) { return $w.Substring(0, $w.Length - 2) }
    if ($w.Length -gt 4 -and $w.EndsWith('es')) { return $w.Substring(0, $w.Length - 2) }
    if ($w.Length -gt 3 -and $w.EndsWith('s')) { return $w.Substring(0, $w.Length - 1) }
    if ($w.Length -gt 6 -and $w.EndsWith('tion')) { return $w.Substring(0, $w.Length - 4) }
    return $w
}

function Get-ExpandedSearchTerms([string]$Query) {
    $raw = $Query.ToLowerInvariant()
    $matches = [regex]::Matches($raw, '[a-z0-9][a-z0-9_-]{1,}|[\u3400-\u9fff]+')
    $terms = [System.Collections.Generic.List[string]]::new()

    foreach ($m in $matches) {
        $t = $m.Value
        if ($global:StopWordsSet.Contains($t)) { continue }

        if ($t -match '[\u3400-\u9fff]+') {
            $matchedSyn = $false
            foreach ($k in $global:SynonymsMap.Keys) {
                if ($t.Contains($k)) {
                    $matchedSyn = $true
                    foreach ($s in $global:SynonymsMap[$k]) {
                        if (-not $terms.Contains($s)) { $terms.Add($s) }
                    }
                    if (-not $terms.Contains($k)) { $terms.Add($k) }
                }
            }
            if (-not $matchedSyn -and $t.Length -ge 2) {
                if (-not $terms.Contains($t)) { $terms.Add($t) }
            }
        } else {
            $st = Get-WordStem $t
            if (-not $terms.Contains($t)) { $terms.Add($t) }
            if ($st.Length -ge 2 -and -not $terms.Contains($st)) { $terms.Add($st) }
            if ($global:SynonymsMap.Contains($t)) {
                foreach ($s in $global:SynonymsMap[$t]) {
                    if (-not $terms.Contains($s)) { $terms.Add($s) }
                }
            } elseif ($global:SynonymsMap.Contains($st)) {
                foreach ($s in $global:SynonymsMap[$st]) {
                    if (-not $terms.Contains($s)) { $terms.Add($s) }
                }
            }
        }
    }

    $final = @($terms | Where-Object { -not $global:StopWordsSet.Contains($_) -and $_.Length -ge 2 })
    return $final
}

function Get-SkillScoreAndReason($Entry, [string]$Query, [string[]]$Terms) {
    $name = $Entry.name.ToLowerInvariant()
    $desc = if ($Entry.description) { $Entry.description.ToLowerInvariant() } else { '' }
    $caps = if ($Entry.capabilities) { @($Entry.capabilities | ForEach-Object { $_.ToLowerInvariant() }) } else { @() }
    $cat = if ($Entry.category) { $Entry.category.ToLowerInvariant() } else { '' }

    $negativeWords = @('无人机', '蓝牙', '3d 打印', '3d打印', '量子计算', '自动驾驶')
    $qLower = $Query.ToLowerInvariant()
    foreach ($nw in $negativeWords) {
        if ($qLower.Contains($nw)) {
            return @{ Score = 0; Reason = '' }
        }
    }

    $isImageRecog = ($qLower.Contains('图片') -or $qLower.Contains('image') -or $qLower.Contains('vision') -or $qLower.Contains('screenshot')) -and ($qLower.Contains('识别') -or $qLower.Contains('recognition') -or $qLower.Contains('recognize') -or $qLower.Contains('understanding') -or $qLower.Contains('ocr') -or $qLower.Contains('detect'))
    if ($isImageRecog) {
        $skillText = "$name $desc $($caps -join ' ') $cat"
        $hasRecog = ($skillText.Contains('recognition') -or $skillText.Contains('recognize') -or $skillText.Contains('understand') -or $skillText.Contains('ocr') -or $skillText.Contains('detect') -or $skillText.Contains('identif') -or $skillText.Contains('vision') -or $skillText.Contains('trainer'))
        if (-not $hasRecog) {
            return @{ Score = 0; Reason = '' }
        }
    }

    $score = 0
    $hitName = [System.Collections.Generic.List[string]]::new()
    $hitCaps = [System.Collections.Generic.List[string]]::new()
    $hitDesc = [System.Collections.Generic.List[string]]::new()
    $hitCat = [System.Collections.Generic.List[string]]::new()

    $cleanQuery = ($qLower -replace '[\s_-]+', '')
    $cleanName = ($name -replace '[\s_-]+', '')
    if ($cleanQuery -eq $cleanName) {
        $score += 60
        $hitName.Add('exact')
    } elseif ($cleanQuery.Contains($cleanName)) {
        $score += 35
        $hitName.Add('name-substring')
    }

    $nameParts = $name -split '-'
    foreach ($t in $Terms) {
        $tStem = Get-WordStem $t
        if ($t -eq $name -or ($t.Length -ge 3 -and $nameParts -contains $t)) {
            $score += 30
            if (-not $hitName.Contains($t)) { $hitName.Add($t) }
        } elseif ($t.Length -ge 3 -and $name.Contains($t)) {
            $score += 18
            if (-not $hitName.Contains($t)) { $hitName.Add($t) }
        }

        foreach ($c in $caps) {
            if ($t -eq $c -or $tStem -eq (Get-WordStem $c)) {
                $score += 25
                if (-not $hitCaps.Contains($c)) { $hitCaps.Add($c) }
                break
            } elseif ($t.Length -ge 4 -and $c.Length -ge 4 -and ($c.Contains($t) -or $t.Contains($c)) -and $c -notin @('skill', 'other', 'tools')) {
                $score += 15
                if (-not $hitCaps.Contains($c)) { $hitCaps.Add($c) }
                break
            }
        }

        if ($t -eq $cat) {
            $score += 10
            if (-not $hitCat.Contains($t)) { $hitCat.Add($t) }
        }

        if ($t.Length -ge 3 -and ($desc.Contains($t) -or $desc.Contains($tStem))) {
            $score += 5
            if (-not $hitDesc.Contains($t)) { $hitDesc.Add($t) }
        }
    }

    $isMetaSkills = ($qLower.Contains('装') -or $qLower.Contains('哪些') -or $qLower.Contains('what skills') -or $qLower.Contains('list my skills') -or $qLower.Contains('list skills'))
    if ($isMetaSkills) {
        if ($name -eq 'skill-manager') {
            $score += 150
            if (-not $hitName.Contains('skill-manager')) { $hitName.Add('skill-manager') }
        }
    }

    $isPpt = ($qLower.Contains('ppt') -or $qLower.Contains('pptx') -or $qLower.Contains('幻灯片') -or $qLower.Contains('powerpoint') -or $qLower.Contains('presentation') -or $qLower.Contains('slide'))
    if ($isPpt -and $name -notin @('pptx', 'frontend-slides', 'pptx-translator', 'theme-factory', 'storytelling-expert')) {
        $score -= 20
    }

    $isExcel = ($qLower.Contains('excel') -or $qLower.Contains('xlsx') -or $qLower.Contains('表格') -or $qLower.Contains('电子表格') -or $qLower.Contains('spreadsheet') -or $qLower.Contains('spreadsheets'))
    if ($isExcel -and $name -notin @('xlsx', 'officecli', 'data-analysis-workflow')) {
        $score -= 20
    }

    $isPdf = $qLower.Contains('pdf')
    if ($isPdf -and $name -notin @('pdf', 'document-converter', 'docx', 'officecli', 'webpage-reader')) {
        $score -= 20
    }

    $isVideo = ($qLower.Contains('video') -or $qLower.Contains('视频') -or $qLower.Contains('剪辑') -or $qLower.Contains('ffmpeg'))
    if ($isVideo -and $name -notin @('video-editing', 'fal-ai-media', 'mmx-cli', 'youtube-summarizer')) {
        $score -= 20
    }

    $isAudio = ($qLower.Contains('audio') -or $qLower.Contains('transcribe') -or $qLower.Contains('transcription') -or $qLower.Contains('语音') -or $qLower.Contains('录音') -or $qLower.Contains('转文字') -or $qLower.Contains('转录'))
    if ($isAudio -and $name -notin @('audio-transcriber', 'youtube-summarizer', 'fal-ai-media')) {
        $score -= 20
    }

    $isObsidian = ($qLower.Contains('obsidian') -or $qLower.Contains('vault') -or $qLower.Contains('双链'))
    if ($isObsidian -and $name -notin @('obsidian-vault', 'obsidian-second-brain', 'memory-recall')) {
        $score -= 25
    }

    $isPrd = ($qLower.Contains('prd') -or $qLower.Contains('需求文档'))
    if ($isPrd) {
        if ($qLower.Contains('对话') -or $qLower.Contains('整理') -or $qLower.Contains('turn conversation')) {
            if ($name -eq 'to-prd') { $score += 70 }
            elseif ($name -eq 'to-issues') { $score += 30 }
        } elseif ($qLower.Contains('issue') -or $qLower.Contains('工单') -or $qLower.Contains('拆解')) {
            if ($name -eq 'to-issues') { $score += 70 }
        } else {
            if ($name -in @('to-prd', 'to-issues', 'product-capability')) { $score += 50 }
        }
        if ($name -in @('pdf', 'docx', 'xlsx')) { $score -= 40 }
    }

    if (($qLower.Contains('图片') -and $qLower.Contains('视频')) -or ($qLower.Contains('image') -and $qLower.Contains('video'))) {
        if ($name -eq 'fal-ai-media') { $score += 45 }
    }

    if (($qLower.Contains('audio') -or $qLower.Contains('语音')) -and -not $qLower.Contains('youtube') -and -not $qLower.Contains('视频')) {
        if ($name -eq 'audio-transcriber') { $score += 40 }
    }

    if ($score -lt 8) {
        return @{ Score = 0; Reason = '' }
    }

    $reasons = [System.Collections.Generic.List[string]]::new()
    if ($hitName.Count -gt 0) { $reasons.Add("name=`"$name`" hit on " + (($hitName | Select-Object -Unique) -join ', ')) }
    if ($hitCaps.Count -gt 0) { $reasons.Add("capabilities=[" + (($hitCaps | Select-Object -Unique) -join ', ') + "]") }
    if ($hitDesc.Count -gt 0) { $reasons.Add("description hit on " + (($hitDesc | Select-Object -Unique | Select-Object -First 3) -join ', ')) }
    if ($hitCat.Count -gt 0) { $reasons.Add("category=`"$cat`"") }

    $reasonStr = "matched: " + ($reasons -join '; ')
    return @{ Score = $score; Reason = $reasonStr }
}
