# core/search.ps1 - Intent matching and score-ranked skill search

function Get-SearchQueryTerms([string]$Query) {
    $terms = [System.Collections.Generic.List[string]]::new()
    $cleaned = $Query -replace '[^\p{L}\p{N}\s_-]', ' '
    foreach ($part in ($cleaned -split '\s+')) {
        if ($part.Trim().Length -ge 2) { $terms.Add($part.Trim().ToLowerInvariant()) }
    }
    return @($terms | Select-Object -Unique)
}
