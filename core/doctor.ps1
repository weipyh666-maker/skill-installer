# core/doctor.ps1 - Diagnostic checks and trigger quality engine

function Get-TriggerQualityScore([string]$Description, [string[]]$Capabilities, [string]$Category) {
    $warnings = 0
    if (-not $Description -or $Description.Trim().Length -lt 20) { $warnings++ }
    elseif (-not ($Description.Trim() -match '^(?i)use when')) { $warnings++ }
    if (-not $Capabilities -or $Capabilities.Count -eq 0) { $warnings++ }
    if (-not $Category) { $warnings++ }
    return $warnings
}
