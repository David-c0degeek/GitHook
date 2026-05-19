<#
.SYNOPSIS
    Installs the shared Git hooks from this repository by creating a directory
    symlink at the target location and pointing Git's global `core.hooksPath`
    at it.

.DESCRIPTION
    Single source of truth: the hook scripts live in `hooks/` inside this repo.
    The installer creates a symbolic link

        <LinkPath>  -->  <repo>\hooks

    and (unless `-NoGitConfig`) sets

        git config --global core.hooksPath = <LinkPath>

    A `git pull` in this repository then updates the hooks on every machine
    where the link exists — no copying, no drift.

.PARAMETER LinkPath
    Where to create the symlink. Defaults to `$HOME\.githooks`, which matches
    the conventional location and the existing setup on this workstation.

.PARAMETER NoGitConfig
    Skip setting `core.hooksPath` in the global Git config. Use this when the
    config is already managed elsewhere or when you only want the symlink.

.PARAMETER Force
    Replace an existing file/directory/symlink at LinkPath. Without -Force the
    installer refuses to touch a non-symlink target to avoid data loss.

.PARAMETER Uninstall
    Remove the symlink (only if it is a symlink) and unset the global
    `core.hooksPath` value if it points at LinkPath.

.NOTES
    Creating symbolic links on Windows requires either:
      - Running as Administrator, or
      - Windows 10/11 Developer Mode enabled (Settings > For developers).

.EXAMPLE
    .\install.ps1
    Symlinks $HOME\.githooks -> <repo>\hooks and sets core.hooksPath globally.

.EXAMPLE
    .\install.ps1 -LinkPath C:\Tools\githooks -Force
    Creates the link at a custom location, replacing whatever is there.

.EXAMPLE
    .\install.ps1 -Uninstall
    Removes the symlink and clears the global core.hooksPath setting.
#>
[CmdletBinding()]
param(
    [string]$LinkPath = (Join-Path $HOME '.githooks'),
    [switch]$NoGitConfig,
    [switch]$Force,
    [switch]$Uninstall
)

$ErrorActionPreference = 'Stop'

function Assert-GitAvailable {
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        throw "Git is not installed or not on PATH."
    }
}

function Get-RepoHooksPath {
    $scriptDir = $PSScriptRoot
    if (-not $scriptDir) { $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path }
    $hooks = Join-Path $scriptDir 'hooks'
    if (-not (Test-Path -LiteralPath $hooks)) {
        throw "Hooks folder not found: $hooks"
    }
    return (Resolve-Path -LiteralPath $hooks).Path
}

function Test-IsSymlink {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    $item = Get-Item -LiteralPath $Path -Force
    return [bool]($item.Attributes -band [IO.FileAttributes]::ReparsePoint)
}

function Remove-LinkIfPresent {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $false }

    if (Test-IsSymlink -Path $Path) {
        # Delete the reparse point itself, not its contents.
        [System.IO.Directory]::Delete($Path)
        return $true
    }

    if (-not $Force) {
        throw "Refusing to remove non-symlink at '$Path'. Re-run with -Force to overwrite."
    }

    Remove-Item -LiteralPath $Path -Recurse -Force
    return $true
}

function New-DirectorySymlink {
    param(
        [Parameter(Mandatory)] [string]$LinkPath,
        [Parameter(Mandatory)] [string]$TargetPath
    )

    $parent = Split-Path -Parent $LinkPath
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    try {
        New-Item -ItemType SymbolicLink -Path $LinkPath -Target $TargetPath -Force | Out-Null
    }
    catch {
        throw @"
Failed to create symbolic link:
  $LinkPath  ->  $TargetPath

        $($_.Exception.Message)

On Windows, creating symlinks requires either:
  - Running PowerShell as Administrator, or
  - Enabling Developer Mode (Settings > Privacy & Security > For developers).
"@
    }
}

function Test-PathsEqual {
    param([string]$A, [string]$B)
    if (-not $A -or -not $B) { return $false }
    $na = [IO.Path]::GetFullPath($A.Replace('/', '\'))
    $nb = [IO.Path]::GetFullPath($B.Replace('/', '\'))
    return [string]::Equals($na, $nb, [System.StringComparison]::OrdinalIgnoreCase)
}

Assert-GitAvailable
$repoHooks = Get-RepoHooksPath

if ($Uninstall) {
    if (Test-Path -LiteralPath $LinkPath) {
        if (Test-IsSymlink -Path $LinkPath) {
            [System.IO.Directory]::Delete($LinkPath)
            Write-Host "Removed symlink: $LinkPath" -ForegroundColor Green
        } else {
            Write-Warning "Path '$LinkPath' is not a symlink; leaving it untouched."
        }
    } else {
        Write-Host "No symlink at $LinkPath (nothing to remove)." -ForegroundColor DarkGray
    }

    $current = (& git config --global --get core.hooksPath) 2>$null
    if ($LASTEXITCODE -eq 0 -and $current -and (Test-PathsEqual $current $LinkPath)) {
        & git config --global --unset core.hooksPath
        Write-Host "Cleared global core.hooksPath." -ForegroundColor Green
    } elseif ($current) {
        Write-Host "Global core.hooksPath ('$current') does not point at '$LinkPath'; left as is." -ForegroundColor DarkGray
    }
    return
}

# --- Install ---

if ((Test-Path -LiteralPath $LinkPath) -and (Test-IsSymlink -Path $LinkPath)) {
    $existingTarget = (Get-Item -LiteralPath $LinkPath -Force).Target
    if (Test-PathsEqual $existingTarget $repoHooks) {
        Write-Host "Symlink already in place: $LinkPath -> $repoHooks" -ForegroundColor DarkGray
    } else {
        Write-Host "Replacing existing symlink (was -> $existingTarget) ..." -ForegroundColor Cyan
        Remove-LinkIfPresent -Path $LinkPath | Out-Null
        New-DirectorySymlink -LinkPath $LinkPath -TargetPath $repoHooks
        Write-Host "Created symlink: $LinkPath -> $repoHooks" -ForegroundColor Green
    }
}
elseif (Test-Path -LiteralPath $LinkPath) {
    Remove-LinkIfPresent -Path $LinkPath | Out-Null
    New-DirectorySymlink -LinkPath $LinkPath -TargetPath $repoHooks
    Write-Host "Created symlink: $LinkPath -> $repoHooks" -ForegroundColor Green
}
else {
    New-DirectorySymlink -LinkPath $LinkPath -TargetPath $repoHooks
    Write-Host "Created symlink: $LinkPath -> $repoHooks" -ForegroundColor Green
}

if (-not $NoGitConfig) {
    # Git on Windows accepts both, but forward slashes are the canonical form.
    $gitPath = $LinkPath.Replace('\', '/')
    & git config --global core.hooksPath $gitPath
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to set global core.hooksPath."
    }
    Write-Host "Set global core.hooksPath = $gitPath" -ForegroundColor Green
}

Write-Host ""
Write-Host "Done. To update hooks on this machine, just 'git pull' in:" -ForegroundColor Cyan
Write-Host "  $(Split-Path -Parent $repoHooks)"

