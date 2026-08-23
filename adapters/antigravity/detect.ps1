# adapters/antigravity/detect.ps1 - Antigravity CLI environment detection

function Get-AntigravityStatus {
    $cliFound = $false
    $cliPath = $null

    # 1. Check commands in PATH / alias
    $cmd = Get-Command antigravity, agy -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd) {
        $cliFound = $true
        $cliPath = $cmd.Source
    } elseif ($env:ANTIGRAVITY_CLI_PATH -and (Test-Path -LiteralPath $env:ANTIGRAVITY_CLI_PATH -PathType Leaf)) {
        # 2. ANTIGRAVITY_CLI_PATH environment variable
        $cliFound = $true
        $cliPath = $env:ANTIGRAVITY_CLI_PATH
    } else {
        # 3. Standard user installation locations
        $candidates = @(
            (Join-Path $env:LOCALAPPDATA 'agy\bin\agy.exe'),
            (Join-Path $env:LOCALAPPDATA 'antigravity\bin\antigravity.exe'),
            (Join-Path $HOME 'bin\agy.exe'),
            (Join-Path $HOME 'bin\antigravity.exe'),
            (Join-Path $HOME '.local\bin\agy.exe'),
            (Join-Path $HOME '.local\bin\antigravity.exe')
        )
        foreach ($cand in $candidates) {
            if ($cand -and (Test-Path -LiteralPath $cand -PathType Leaf)) {
                $cliFound = $true
                $cliPath = $cand
                break
            }
        }
    }

    # 4. Check app data directory
    $appData = Join-Path (Join-Path $HOME '.gemini') 'antigravity-cli'
    $appDataFound = (Test-Path -LiteralPath $appData -PathType Container) -or (Test-Path (Join-Path $HOME '.antigravity') -PathType Container)

    # 5. Check skills directory
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
