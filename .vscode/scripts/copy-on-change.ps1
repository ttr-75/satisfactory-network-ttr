param(
  [string]$Source,
  [string]$Dest
)

$script:Source = (Resolve-Path $Source).Path
$script:Dest   = (Resolve-Path $Dest).Path

if (!(Test-Path $script:Dest)) {
  New-Item -ItemType Directory -Force -Path $script:Dest | Out-Null
}

function Copy-One([string]$path) {
  if (-not (Test-Path $path)) { return }
  $rel = $path.Substring($script:Source.Length).TrimStart('\','/')
  $targetDir = Join-Path $script:Dest (Split-Path $rel -Parent)
  if ($targetDir -and !(Test-Path $targetDir)) {
    New-Item -ItemType Directory -Force -Path $targetDir | Out-Null
  }
  Copy-Item -LiteralPath $path -Destination (Join-Path $targetDir (Split-Path $path -Leaf)) -Force
  Write-Host "Copied: $rel"
}

# Watcher
$fsw = New-Object IO.FileSystemWatcher $script:Source -Property @{
  IncludeSubdirectories = $true
  EnableRaisingEvents   = $true
  Filter                = '*.*'
}

Register-ObjectEvent $fsw Created -Action { Copy-One $EventArgs.FullPath } | Out-Null
Register-ObjectEvent $fsw Changed -Action { Copy-One $EventArgs.FullPath } | Out-Null
Register-ObjectEvent $fsw Renamed -Action { Copy-One $EventArgs.FullPath } | Out-Null

Write-Host "Watching $script:Source  ->  $script:Dest  (Strg+C zum Stoppen)"
while ($true) { Start-Sleep 1 }
