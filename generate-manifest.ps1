param(
    [string]$RepoOwner = "Va1elon",
    [string]$RepoName = "veltrix",
    [string]$Branch = "main",
    [string[]]$IncludeRoots = @(".minecraft", "instance", "config", ".launcher"),
    [string[]]$ExcludeDirs = @(".git", "cache", "obj", "bin"),
    [string[]]$ExcludeFilePatterns = @("*.log", "*.tmp", "*.download", "Thumbs.db", "Desktop.ini"),
    [string]$OutputFile = "client-manifest.json",
    [string]$Version = ""
)

$ErrorActionPreference = "Stop"

function Get-Sha256 {
    param([string]$FilePath)
    return (Get-FileHash -Path $FilePath -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-RelativePathCompat {
    param(
        [string]$BasePath,
        [string]$TargetPath
    )

    $base = [System.IO.Path]::GetFullPath($BasePath)
    $target = [System.IO.Path]::GetFullPath($TargetPath)

    if (-not $base.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
        $base += [System.IO.Path]::DirectorySeparatorChar
    }

    $baseUri = New-Object System.Uri($base)
    $targetUri = New-Object System.Uri($target)
    $relativeUri = $baseUri.MakeRelativeUri($targetUri)
    $relativePath = [System.Uri]::UnescapeDataString($relativeUri.ToString())

    return ($relativePath -replace "\\", "/")
}

function Test-ExcludedFile {
    param(
        [string]$RelativePath,
        [string[]]$Patterns
    )

    $name = [System.IO.Path]::GetFileName($RelativePath)

    foreach ($pattern in $Patterns) {
        if ($name -like $pattern -or $RelativePath -like $pattern) {
            return $true
        }
    }

    return $false
}

function Test-ExcludedByDir {
    param(
        [string]$RelativePath,
        [string[]]$Dirs
    )

    $normalized = $RelativePath -replace "\\", "/"

    foreach ($dir in $Dirs) {
        $d = $dir -replace "\\", "/"
        if ($normalized -eq $d -or $normalized.StartsWith("$d/")) {
            return $true
        }
    }

    return $false
}

$rootPath = (Get-Location).Path

if ([string]::IsNullOrWhiteSpace($Version)) {
    $Version = Get-Date -Format "yyyy.MM.dd-HH.mm.ss"
}

$files = New-Object System.Collections.Generic.List[object]

foreach ($includeRoot in $IncludeRoots) {
    $fullIncludeRoot = Join-Path $rootPath $includeRoot
    if (-not (Test-Path $fullIncludeRoot)) {
        continue
    }

    Get-ChildItem -Path $fullIncludeRoot -File -Recurse | ForEach-Object {
        $fullPath = $_.FullName
        $relativePath = Get-RelativePathCompat -BasePath $rootPath -TargetPath $fullPath
        $relativePath = $relativePath -replace "\\", "/"

        if (Test-ExcludedByDir -RelativePath $relativePath -Dirs $ExcludeDirs) {
            return
        }

        if (Test-ExcludedFile -RelativePath $relativePath -Patterns $ExcludeFilePatterns) {
            return
        }

        $url = "https://raw.githubusercontent.com/$RepoOwner/$RepoName/$Branch/$relativePath"

        $files.Add([PSCustomObject]@{
            Path   = $relativePath
            Url    = $url
            Sha256 = (Get-Sha256 -FilePath $fullPath)
            Size   = $_.Length
        })
    }
}

$sortedFiles = $files | Sort-Object Path

$manifest = [PSCustomObject]@{
    Version = $Version
    Files   = $sortedFiles
}

$manifest | ConvertTo-Json -Depth 6 | Set-Content -Path $OutputFile -Encoding UTF8

Write-Host "Done: $OutputFile"
Write-Host "Files in manifest: $($sortedFiles.Count)"