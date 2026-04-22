#Requires -Version 5.1
<#
.SYNOPSIS
    Download the Windows portable .zip for DBSAnnotator from GitHub Releases and install
    to your user profile (no unsigned MSI, no admin).

.DESCRIPTION
    Picks the newest non-draft release that has an asset named like "DBSAnnotator-<version>.zip" (BeeWare
    briefcase "zip" output). Installs to:
        %LOCALAPPDATA%\\WyssGeneva\\DBSAnnotator\\app
    and creates a Start Menu shortcut. Use -AddDesktopShortcut for a desktop link.

    Default GitHub repository: Brain-Modulation-Lab/DBSAnnotator. Override with
    -GitHubRepository or environment variable DBS_ANNOTATOR_INSTALL_REPO (format: "Owner/Name").

    Your release must include the portable .zip. If only an MSI exists, tag again after CI uploads the .zip.
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = "Medium")]
param(
    [string] $GitHubRepository = $(
        if ($env:DBS_ANNOTATOR_INSTALL_REPO) { $env:DBS_ANNOTATOR_INSTALL_REPO } else { "Brain-Modulation-Lab/DBSAnnotator" }
    ),
    [string] $VersionTag = "",
    [string] $InstallRoot = "",
    [switch] $AddDesktopShortcut,
    [switch] $NoStartMenuShortcut
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($InstallRoot)) {
    $InstallRoot = Join-Path $env:LOCALAPPDATA "WyssGeneva\DBSAnnotator\app"
}

$headers = @{
    "User-Agent"             = "DBSAnnotator-Windows-Install/1.0 (PowerShell; +https://github.com/$GitHubRepository)"
    "Accept"                 = "application/vnd.github+json"
    "X-GitHub-Api-Version"   = "2022-11-28"
}

function Get-TargetRelease {
    if ($VersionTag) {
        $u = "https://api.github.com/repos/$GitHubRepository/releases/tags/$([uri]::EscapeDataString($VersionTag))"
        try {
            return Invoke-RestMethod -Uri $u -Headers $headers -Method Get
        } catch {
            if ($_.Exception.Response -and $_.Exception.Response.StatusCode -eq 404) {
                throw "No GitHub release for tag '$VersionTag' in $GitHubRepository"
            }
            throw
        }
    }
    for ($p = 1; $p -le 3; $p++) {
        $u = "https://api.github.com/repos/$GitHubRepository/releases?per_page=100&page=$p"
        $page = Invoke-RestMethod -Uri $u -Headers $headers -Method Get
        if ($null -eq $page -or $page.Count -lt 1) { break }
        foreach ($rel in $page) {
            if ($rel.draft) { continue }
            $zip = $rel.assets | Where-Object { $_.name -match '^DBSAnnotator-.+\.zip$' } | Select-Object -First 1
            if ($zip) { return $rel }
        }
    }
    if ($WhatIfPreference) {
        Write-Warning @"
No DBSAnnotator-*.zip on recent releases. Install would fail until a release includes the Windows portable
.zip from briefcase (package -p zip). Cut a new tag after CI attaches that asset, or upload the .zip to an existing release.
"@
        return $null
    }
    throw @"
No DBSAnnotator-*.zip asset in recent GitHub releases of $GitHubRepository.
Windows CI upload must include the briefcase 'zip' package. Use a new tag after that asset exists, or
set -VersionTag to a tag that has the .zip, or add the .zip to the release manually.
"@
}

function Get-ZipAssetFromRelease {
    param([Parameter(Mandatory = $true)] $Release)
    $a = $Release.assets | Where-Object { $_.name -match '^DBSAnnotator-.+\.zip$' } | Select-Object -First 1
    if (-not $a) {
        $names = $Release.assets | ForEach-Object { $_.name }
        throw "Release $($Release.tag_name) has no DBSAnnotator-*.zip. Available assets: $($names -join ', ')"
    }
    return $a
}

$release = Get-TargetRelease
if ($null -eq $release) { return }
$asset = Get-ZipAssetFromRelease -Release $release
Write-Host "Release:  $($release.tag_name)"
Write-Host "Asset:    $($asset.name) ($([math]::Round($asset.size / 1MB, 1)) MB)"
Write-Host "Install:  $InstallRoot"
if ($WhatIfPreference) {
    Write-Host "What if:  would download, extract, and copy files, then add shortcuts (unless -NoStartMenuShortcut / -AddDesktopShortcut)."
    return
}
if (-not $PSCmdlet.ShouldProcess($InstallRoot, "Install DBSAnnotator (overwrite if present)")) {
    return
}

$work = $null
try {
    $work = Join-Path $env:TEMP "dbs-annotator-install\$([guid]::NewGuid().ToString('n'))"
    $zipFile = Join-Path $work "download.zip"
    $expand = Join-Path $work "e"
    New-Item -ItemType Directory -Path $work -Force -ErrorAction Stop | Out-Null
    if (-not (Test-Path (Split-Path $InstallRoot -Parent))) {
        New-Item -ItemType Directory -Path (Split-Path $InstallRoot -Parent) -Force -ErrorAction Stop | Out-Null
    }
    $ProgressPreference = "SilentlyContinue"
    try {
        Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zipFile -Headers @{ "User-Agent" = $headers["User-Agent"] } -UseBasicParsing
    } finally {
        $ProgressPreference = "Continue"
    }
    if (-not (Test-Path $zipFile)) { throw "Download failed (no file)." }
    if ((Get-Item $zipFile).Length -lt 512 * 1024) { throw "Downloaded .zip is too small; aborting." }
    New-Item -ItemType Directory -Path $expand -Force | Out-Null
    Expand-Archive -LiteralPath $zipFile -DestinationPath $expand -Force
    $inner = $expand
    $subdirs = @(Get-ChildItem -LiteralPath $expand -Directory -ErrorAction SilentlyContinue)
    $atRoot = @(Get-ChildItem -LiteralPath $expand -File -ErrorAction SilentlyContinue)
    if ($subdirs.Count -eq 1 -and $atRoot.Count -lt 1) { $inner = $subdirs[0].FullName }
    if (Test-Path $InstallRoot) { Remove-Item -LiteralPath $InstallRoot -Recurse -Force -ErrorAction Stop }
    New-Item -ItemType Directory -Path $InstallRoot -Force -ErrorAction Stop | Out-Null
    Get-ChildItem -LiteralPath $inner -Force -ErrorAction Stop | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $InstallRoot $_.Name) -Recurse -Force
    }
    $exe = Get-ChildItem -LiteralPath $InstallRoot -Recurse -Filter "DBSAnnotator.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $exe) { throw "DBSAnnotator.exe not found under $InstallRoot after install." }
    if (-not $NoStartMenuShortcut) {
        if ($PSCmdlet.ShouldProcess("Start Menu programs", "Create DBSAnnotator shortcut")) {
            $programs = [Environment]::GetFolderPath("Programs")
            if (-not (Test-Path $programs)) { New-Item -ItemType Directory -Path $programs -Force | Out-Null }
            $wsh = New-Object -ComObject WScript.Shell
            $lnk = $wsh.CreateShortcut((Join-Path $programs "DBSAnnotator.lnk"))
            $lnk.TargetPath = $exe.FullName
            $lnk.WorkingDirectory = $exe.DirectoryName
            $lnk.IconLocation = $exe.FullName
            $lnk.Save() | Out-Null
        }
    }
    if ($AddDesktopShortcut) {
        if ($PSCmdlet.ShouldProcess("Desktop", "Create DBSAnnotator shortcut")) {
            $desk = [Environment]::GetFolderPath("Desktop")
            $wsh2 = New-Object -ComObject WScript.Shell
            $dl = $wsh2.CreateShortcut((Join-Path $desk "DBSAnnotator.lnk"))
            $dl.TargetPath = $exe.FullName
            $dl.WorkingDirectory = $exe.DirectoryName
            $dl.IconLocation = $exe.FullName
            $dl.Save() | Out-Null
        }
    }
    Write-Host "Done. Run:  $($exe.FullName)"
} finally {
    if ($work -and (Test-Path $work)) { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
}
