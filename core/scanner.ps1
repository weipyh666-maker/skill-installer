# core/scanner.ps1 - Filesystem skill discovery and catalog indexing

function Get-SkillDirectoriesFromRoots([string[]]$Roots) {
    $selected = [ordered]@{}
    foreach ($root in $Roots) {
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
