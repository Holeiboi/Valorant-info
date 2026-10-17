[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$MarkdownPath = (Get-ChildItem -LiteralPath $PSScriptRoot -File -Filter '*.md' |
        Select-Object -First 1 -ExpandProperty FullName)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = $PSScriptRoot
$assets = Join-Path $root 'assets'

if (-not (Test-Path -LiteralPath $MarkdownPath -PathType Leaf)) {
    throw "Markdown file not found: $MarkdownPath"
}

if (-not (Test-Path -LiteralPath $assets -PathType Container)) {
    if ($PSCmdlet.ShouldProcess($assets, 'Create assets directory')) {
        New-Item -ItemType Directory -Path $assets | Out-Null
    }
}

$imageExtensions = @('.png', '.jpg', '.jpeg', '.gif', '.webp', '.bmp', '.svg')
$imageFiles = Get-ChildItem -LiteralPath $root -File |
    Where-Object { $imageExtensions -contains $_.Extension.ToLowerInvariant() }

# Map original file names to their new relative paths.
$pathMap = @{}

foreach ($file in $imageFiles) {
    $targetName = $file.Name
    $targetPath = Join-Path $assets $targetName
    $index = 1

    while (Test-Path -LiteralPath $targetPath) {
        $targetName = '{0}-{1}{2}' -f $file.BaseName, $index, $file.Extension
        $targetPath = Join-Path $assets $targetName
        $index++
    }

    if ($PSCmdlet.ShouldProcess($file.FullName, "Move to $targetPath")) {
        Move-Item -LiteralPath $file.FullName -Destination $targetPath
    }

    $pathMap[$file.Name] = 'assets/' + $targetName
        Write-Host "Image: $($file.Name) -> assets/$targetName"
}

if ($pathMap.Count -eq 0) {
    Write-Host 'No images found in the project root.'
    exit 0
}

$markdown = Get-Content -LiteralPath $MarkdownPath -Raw -Encoding UTF8
$imagePattern = '!\[[^]]*\]\((?<path>[^)\s]+)[^)]*\)'
$updatedMarkdown = [regex]::Replace(
    $markdown,
    $imagePattern,
    [Text.RegularExpressions.MatchEvaluator]{
        param($match)

        $path = $match.Groups['path'].Value
        $fileName = [IO.Path]::GetFileName($path)

        # Only update root-level references; keep paths that already contain a directory.
        if (($path -notmatch '[/\\]') -and $pathMap.ContainsKey($fileName)) {
            return $match.Value.Replace($path, $pathMap[$fileName])
        }

        return $match.Value
    }
)

if ($updatedMarkdown -ne $markdown) {
    if ($PSCmdlet.ShouldProcess($MarkdownPath, 'Update Markdown image paths')) {
        [IO.File]::WriteAllText($MarkdownPath, $updatedMarkdown, [Text.UTF8Encoding]::new($false))
        Write-Host "Updated: $MarkdownPath"
    }
}

Write-Host 'Done.'
