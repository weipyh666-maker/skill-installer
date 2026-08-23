# adapters/antigravity/detect.ps1 - Antigravity CLI environment detection

function Get-AntigravityStatus {
    $cliFound = $false
    $cliPath = $null

    # 1. Check commands in PATH / alias
    $cmd = Get-Command antigravity, agy -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd) {
        $cliFound = $true
        $cliPath = $cmd.Source
    } elseif (Test-Path 'D:\Antigravity\cli\bin\agy.exe' -PathType Leaf) {
        $cliFound = $true
        $cliPath = 'D:\Antigravity\cli\bin\agy.exe'
    }

    # 2. Check app data directory
    $appData = Join-Path (Join-Path $HOME '.gemini') 'antigravity-cli'
    $appDataFound = (Test-Path -LiteralPath $appData -PathType Container) -or (Test-Path (Join-Path $HOME '.antigravity') -PathType Container)

    # 3. Check skills directory
    $globalSkills = Get-AntigravityGlobalSkillDir
    $skillsFound = (Test-Path -LiteralPath $globalSkills -PathType Container)

    $isUsable = $cliFound -or $skillsFound -or ($env:ANTIGRAVITY_SKILLS_DIR -ne $null) -or ($env:ANTIGRAVITY_SKILLS_LINK_DIR -ne $null)

    return [pscustomobject]@{
        CliDetected = $cliFound
        CliPath = $cliPath
        AppDataDetected = $appDataFound
        SkillsDirDetected = $skillsFound
        GlobalSkillsDir = $globalSkills
        Usable = $isUsable
    }
}

function Test-AntigravityInstalled {
    $status = Get-AntigravityStatus
    return $status.Usable
}
