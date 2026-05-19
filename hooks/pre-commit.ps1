#requires -Version 5.1
<#
    pre-commit hook: AI-output cleanup.

    For every staged text file (added/copied/modified/renamed):
      1. Strip a leading UTF-8 BOM (EF BB BF).
      2. Replace "smart" Unicode punctuation that AI tools, Word and browsers
         love to inject with the ASCII equivalents a developer would have
         typed.
      3. Remove invisible / zero-width characters (incl. inner BOMs).
      4. Re-stage the file if anything changed.

    Binary files are detected via a NUL-byte heuristic and skipped.
    Files outside the working tree (already deleted) are skipped.

    Note: every special character is referenced by code point ([char]0xNNNN)
    so this script can be safely committed without rewriting itself.
#>

$ErrorActionPreference = 'Stop'

# --- Replacement table ----------------------------------------------------
# Each pair: <code point>, <ASCII replacement string>
$replacementPairs = @(
# Dashes / hyphens / minus
    @(0x2010, '-'),  # hyphen
    @(0x2011, '-'),  # non-breaking hyphen
    @(0x2012, '-'),  # figure dash
    @(0x2013, '-'),  # en dash
    @(0x2014, '-'),  # em dash
    @(0x2015, '-'),  # horizontal bar
    @(0x2212, '-'),  # minus sign

    # Single quotes / apostrophes / prime
    @(0x2018, "'"),  # left single
    @(0x2019, "'"),  # right single
    @(0x201A, "'"),  # single low-9
    @(0x201B, "'"),  # single high-reversed-9
    @(0x2032, "'"),  # prime

    # Double quotes / double prime
    @(0x201C, '"'),  # left double
    @(0x201D, '"'),  # right double
    @(0x201E, '"'),  # double low-9
    @(0x201F, '"'),  # double high-reversed-9
    @(0x2033, '"'),  # double prime

    # Ellipsis
    @(0x2026, '...'),

    # Spaces -> regular space
    @(0x00A0, ' '),  # NBSP
    @(0x2002, ' '),  # en space
    @(0x2003, ' '),  # em space
    @(0x2007, ' '),  # figure space
    @(0x2008, ' '),  # punctuation space
    @(0x2009, ' '),  # thin space
    @(0x200A, ' '),  # hair space
    @(0x202F, ' '),  # narrow NBSP
    @(0x205F, ' '),  # medium mathematical space
    @(0x3000, ' '),  # ideographic space

    # Invisible / zero-width / inner BOM -> removed
    @(0x200B, ''),   # zero-width space
    @(0x200C, ''),   # zero-width non-joiner
    @(0x200D, ''),   # zero-width joiner
    @(0x2060, ''),   # word joiner
    @(0xFEFF, '')    # zero-width no-break space (BOM if mid-file)
)

$replacements = [ordered]@{}
foreach ($pair in $replacementPairs) {
    $replacements[[char]$pair[0]] = [string]$pair[1]
}

$utf8NoBom = [System.Text.UTF8Encoding]::new($false)

function Test-IsBinary {
    param([byte[]]$Bytes)

    if ($null -eq $Bytes -or $Bytes.Length -eq 0) { return $false }
    $sampleLength = [Math]::Min(8192, $Bytes.Length)
    for ($i = 0; $i -lt $sampleLength; $i++) {
        if ($Bytes[$i] -eq 0) { return $true }
    }
    return $false
}

function Repair-FileContent {
    <#
        Reads the file, applies BOM strip + smart-punctuation replacement,
        writes it back if changed. Returns $true when the file was modified.
    #>
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) { return $false }

    $bytes = [System.IO.File]::ReadAllBytes($Path)
    if (Test-IsBinary -Bytes $bytes) { return $false }

    $changed = $false

    # 1. Strip leading UTF-8 BOM.
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        $bytes = $bytes[3..($bytes.Length - 1)]
        $changed = $true
    }

    $text = [System.Text.Encoding]::UTF8.GetString($bytes)

    # 2. Replace smart punctuation / invisible characters.
    $sb = [System.Text.StringBuilder]::new($text.Length)
    $hadSubstitution = $false
    foreach ($ch in $text.ToCharArray()) {
        if ($replacements.Contains($ch)) {
            [void]$sb.Append($replacements[$ch])
            $hadSubstitution = $true
        } else {
            [void]$sb.Append($ch)
        }
    }

    if ($hadSubstitution) {
        $text = $sb.ToString()
        $changed = $true
    }

    if ($changed) {
        [System.IO.File]::WriteAllText($Path, $text, $utf8NoBom)
    }

    return $changed
}

# --- Main -----------------------------------------------------------------

$staged = git diff --cached --name-only --diff-filter=ACMR
if (-not $staged) { exit 0 }

$fixed = New-Object System.Collections.Generic.List[string]

foreach ($file in $staged) {
    try {
        if (Repair-FileContent -Path $file) {
            git add -- $file | Out-Null
            $fixed.Add($file)
        }
    }
    catch {
        Write-Host ("[pre-commit] Skipped '{0}': {1}" -f $file, $_.Exception.Message)
    }
}

if ($fixed.Count -gt 0) {
    Write-Host "[pre-commit] Auto-cleaned and re-staged:"
    foreach ($f in $fixed) { Write-Host "  - $f" }
}

exit 0

