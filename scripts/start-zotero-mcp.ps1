param(
  [switch]$Check,
  [switch]$Status
)

$ErrorActionPreference = "Stop"

function Fail([string]$Message) {
  [Console]::Error.WriteLine($Message)
  exit 1
}

function Assert-OptionalLeaf([string]$Name, [string]$PathValue) {
  if (-not [string]::IsNullOrWhiteSpace($PathValue)) {
    if (-not (Test-Path -LiteralPath $PathValue -PathType Leaf)) {
      Fail "$Name does not exist: $PathValue"
    }
  }
}

function Write-State([string]$Level, [string]$Message) {
  Write-Output "$($Level): $Message"
}

function Resolve-ZoteroMcp {
  $zoteroMcp = $env:ZOTERO_MCP_EXE
  if ([string]::IsNullOrWhiteSpace($zoteroMcp)) {
    $command = Get-Command "zotero-mcp" -ErrorAction SilentlyContinue
    if ($null -eq $command) {
      return [pscustomobject]@{
        Ok = $false
        Path = ""
        Source = ""
        Message = "ZOTERO_MCP_EXE is not set and zotero-mcp is not available on PATH."
      }
    }

    return [pscustomobject]@{
      Ok = $true
      Path = $command.Source
      Source = "PATH"
      Message = "zotero-mcp found on PATH."
    }
  }

  if (-not (Test-Path -LiteralPath $zoteroMcp -PathType Leaf)) {
    return [pscustomobject]@{
      Ok = $false
      Path = $zoteroMcp
      Source = "ZOTERO_MCP_EXE"
      Message = "ZOTERO_MCP_EXE does not exist: $zoteroMcp"
    }
  }

  return [pscustomobject]@{
    Ok = $true
    Path = $zoteroMcp
    Source = "ZOTERO_MCP_EXE"
    Message = "ZOTERO_MCP_EXE points to an existing file."
  }
}

function Get-ZoteroAppRoot {
  $appData = [Environment]::GetFolderPath("ApplicationData")
  if ([string]::IsNullOrWhiteSpace($appData)) {
    $appData = $env:APPDATA
  }

  if ([string]::IsNullOrWhiteSpace($appData)) {
    return ""
  }

  return (Join-Path $appData "Zotero\Zotero")
}

function Get-DefaultZoteroProfilePath {
  $zoteroRoot = Get-ZoteroAppRoot
  if ([string]::IsNullOrWhiteSpace($zoteroRoot)) {
    return ""
  }

  $profilesIni = Join-Path $zoteroRoot "profiles.ini"
  if (-not (Test-Path -LiteralPath $profilesIni -PathType Leaf)) {
    return ""
  }

  $sections = New-Object System.Collections.Generic.List[object]
  $current = $null
  foreach ($line in [System.IO.File]::ReadAllLines($profilesIni)) {
    if ($line -match "^\[(.+)\]$") {
      if ($null -ne $current) {
        $sections.Add($current) | Out-Null
      }
      $current = @{}
      $current["Section"] = $Matches[1]
      continue
    }

    if ($null -ne $current -and $line -match "^\s*([^=]+)=(.*)$") {
      $current[$Matches[1].Trim()] = $Matches[2].Trim()
    }
  }

  if ($null -ne $current) {
    $sections.Add($current) | Out-Null
  }

  $profile = $sections |
    Where-Object { $_["Section"] -like "Profile*" -and $_["Default"] -eq "1" } |
    Select-Object -First 1
  if ($null -eq $profile) {
    $profile = $sections |
      Where-Object { $_["Section"] -like "Profile*" } |
      Select-Object -First 1
  }

  if ($null -eq $profile -or [string]::IsNullOrWhiteSpace([string]$profile["Path"])) {
    return ""
  }

  $profilePath = [string]$profile["Path"]
  if ($profile["IsRelative"] -eq "1") {
    $profilePath = Join-Path $zoteroRoot $profilePath
  }

  return [System.IO.Path]::GetFullPath($profilePath)
}

function Get-ZoteroPrefsFiles {
  $files = New-Object System.Collections.Generic.List[object]
  $defaultProfile = Get-DefaultZoteroProfilePath
  if (-not [string]::IsNullOrWhiteSpace($defaultProfile)) {
    $defaultPrefs = Join-Path $defaultProfile "prefs.js"
    if (Test-Path -LiteralPath $defaultPrefs -PathType Leaf) {
      $files.Add((Get-Item -LiteralPath $defaultPrefs)) | Out-Null
    }
  }

  $zoteroRoot = Get-ZoteroAppRoot
  if (-not [string]::IsNullOrWhiteSpace($zoteroRoot)) {
    $profileRoot = Join-Path $zoteroRoot "Profiles"
    if (Test-Path -LiteralPath $profileRoot -PathType Container) {
      Get-ChildItem -LiteralPath $profileRoot -Directory |
        ForEach-Object {
          $prefs = Join-Path $_.FullName "prefs.js"
          if (Test-Path -LiteralPath $prefs -PathType Leaf) {
            $item = Get-Item -LiteralPath $prefs
            if (-not ($files | Where-Object { $_.FullName -eq $item.FullName })) {
              $files.Add($item) | Out-Null
            }
          }
        }
    }
  }

  return $files
}

function Get-PrefsValue([string]$Content, [string]$Name) {
  $pattern = 'user_pref\("' + [regex]::Escape($Name) + '",\s*(?<value>.+?)\);'
  $match = [regex]::Match($Content, $pattern)
  if (-not $match.Success) {
    return $null
  }

  $raw = $match.Groups["value"].Value.Trim()
  if ($raw -eq "true") {
    return $true
  }
  if ($raw -eq "false") {
    return $false
  }
  if ($raw -match '^"(.*)"$') {
    $value = $Matches[1]
    $value = $value.Replace("\\", "\")
    $value = $value.Replace('\/', '/')
    return [Environment]::ExpandEnvironmentVariables($value)
  }

  return $raw
}

function Resolve-ZoteroDataDirectory {
  $userProfile = [Environment]::GetFolderPath("UserProfile")
  $defaultDataDir = if ([string]::IsNullOrWhiteSpace($userProfile)) {
    ""
  } else {
    Join-Path $userProfile "Zotero"
  }

  $prefsFiles = @(Get-ZoteroPrefsFiles)
  foreach ($prefsFile in $prefsFiles) {
    try {
      $content = Get-Content -Raw -LiteralPath $prefsFile.FullName -Encoding UTF8
    } catch {
      continue
    }

    $useDataDir = Get-PrefsValue $content "extensions.zotero.useDataDir"
    $dataDir = Get-PrefsValue $content "extensions.zotero.dataDir"
    if ($useDataDir -eq $true -and -not [string]::IsNullOrWhiteSpace([string]$dataDir)) {
      return [pscustomobject]@{
        Path = [System.IO.Path]::GetFullPath([string]$dataDir)
        Source = "Zotero profile dataDir preference"
        Profile = $prefsFile.Directory.FullName
        FoundPrefs = $true
      }
    }
  }

  $profilePath = if ($prefsFiles.Count -gt 0) { $prefsFiles[0].Directory.FullName } else { "" }
  return [pscustomobject]@{
    Path = $defaultDataDir
    Source = "default Windows Zotero data directory"
    Profile = $profilePath
    FoundPrefs = ($prefsFiles.Count -gt 0)
  }
}

function Test-LlmForZoteroMarker([string]$ProfilePath) {
  if ([string]::IsNullOrWhiteSpace($ProfilePath) -or -not (Test-Path -LiteralPath $ProfilePath -PathType Container)) {
    return $false
  }

  $candidateFiles = @("extensions.json", "prefs.js") |
    ForEach-Object { Join-Path $ProfilePath $_ } |
    Where-Object { Test-Path -LiteralPath $_ -PathType Leaf }

  foreach ($file in $candidateFiles) {
    try {
      $content = Get-Content -Raw -LiteralPath $file -Encoding UTF8
    } catch {
      continue
    }

    if ($content -match "llm-for-zotero|yilewang") {
      return $true
    }
  }

  return $false
}

function Write-ZoteroStatus {
  Write-State "INFO" "zotero-research-tools exposes the Codex MCP server named zotero; llm-for-zotero remains a Zotero desktop add-on."

  $mcp = Resolve-ZoteroMcp
  if ($mcp.Ok) {
    Write-State "OK" "$($mcp.Source) can start Zotero MCP."
  } else {
    Write-State "WARN" $mcp.Message
  }

  $dataDir = Resolve-ZoteroDataDirectory
  if (-not [string]::IsNullOrWhiteSpace($dataDir.Path) -and (Test-Path -LiteralPath $dataDir.Path -PathType Container)) {
    Write-State "OK" "Zotero data directory resolved from $($dataDir.Source): $($dataDir.Path)"
  } elseif (-not [string]::IsNullOrWhiteSpace($dataDir.Path)) {
    Write-State "WARN" "Zotero data directory was inferred from $($dataDir.Source) but does not exist: $($dataDir.Path)"
  } else {
    Write-State "WARN" "Unable to infer a Zotero data directory."
  }

  if (-not [string]::IsNullOrWhiteSpace($env:ZOTERO_DB_PATH)) {
    if (Test-Path -LiteralPath $env:ZOTERO_DB_PATH -PathType Leaf) {
      Write-State "OK" "ZOTERO_DB_PATH points to an existing zotero.sqlite."
    } else {
      Write-State "WARN" "ZOTERO_DB_PATH is set but missing: $env:ZOTERO_DB_PATH"
    }

    if (-not [string]::IsNullOrWhiteSpace($dataDir.Path) -and (Test-Path -LiteralPath $dataDir.Path -PathType Container)) {
      $dbFull = [System.IO.Path]::GetFullPath($env:ZOTERO_DB_PATH)
      $dataFull = [System.IO.Path]::GetFullPath($dataDir.Path).TrimEnd("\", "/")
      if (-not $dbFull.StartsWith("$dataFull\", [System.StringComparison]::OrdinalIgnoreCase)) {
        Write-State "WARN" "ZOTERO_DB_PATH is outside the resolved Zotero data directory; Codex and llm-for-zotero may be reading different libraries."
      }
    }
  } elseif (-not [string]::IsNullOrWhiteSpace($dataDir.Path)) {
    $inferredDb = Join-Path $dataDir.Path "zotero.sqlite"
    if (Test-Path -LiteralPath $inferredDb -PathType Leaf) {
      Write-State "OK" "No ZOTERO_DB_PATH set; inferred zotero.sqlite exists in the resolved data directory."
    } else {
      Write-State "INFO" "No ZOTERO_DB_PATH set and no zotero.sqlite found in the resolved data directory."
    }
  }

  if (Test-LlmForZoteroMarker $dataDir.Profile) {
    Write-State "OK" "llm-for-zotero marker found in the active Zotero profile metadata."
  } else {
    Write-State "INFO" "No llm-for-zotero marker found in profile metadata; verify inside Zotero Add-ons if installation status matters."
  }

  if (-not [string]::IsNullOrWhiteSpace($dataDir.Path)) {
    $mineruDir = Join-Path $dataDir.Path "llm-for-zotero-mineru"
    if (Test-Path -LiteralPath $mineruDir -PathType Container) {
      $fullMarkdownCount = @(Get-ChildItem -LiteralPath $mineruDir -Recurse -File -Filter "full.md" -ErrorAction SilentlyContinue).Count
      $manifestCount = @(Get-ChildItem -LiteralPath $mineruDir -Recurse -File -Filter "manifest.json" -ErrorAction SilentlyContinue).Count
      if ($fullMarkdownCount -gt 0) {
        Write-State "OK" "MinerU cache is present: $fullMarkdownCount full.md file(s), $manifestCount manifest.json file(s)."
      } else {
        Write-State "INFO" "MinerU cache directory exists but no full.md files were found."
      }
    } else {
      Write-State "INFO" "MinerU cache directory not found under the resolved Zotero data directory."
    }
  }

  Write-State "INFO" "Codex can use llm-for-zotero output only after it is saved to Zotero notes/annotations or the MinerU Markdown cache."
}

if ([string]::IsNullOrWhiteSpace($env:ZOTERO_LOCAL)) {
  $env:ZOTERO_LOCAL = "true"
}
if ([string]::IsNullOrWhiteSpace($env:ZOTERO_NO_CLAUDE)) {
  $env:ZOTERO_NO_CLAUDE = "true"
}

if ($Status) {
  Write-ZoteroStatus
  exit 0
}

$mcp = Resolve-ZoteroMcp
if (-not $mcp.Ok) {
  Fail $mcp.Message
}
$zoteroMcp = $mcp.Path

Assert-OptionalLeaf "ZOTERO_DB_PATH" $env:ZOTERO_DB_PATH

if ($Check) {
  Write-Output "OK: ZOTERO_MCP_EXE or PATH command"
  if (-not [string]::IsNullOrWhiteSpace($env:ZOTERO_DB_PATH)) { Write-Output "OK: ZOTERO_DB_PATH" }
  Write-Output "OK: Zotero MCP wrapper environment is valid."
  Write-Output "TIP: Run this script with -Status to inspect llm-for-zotero and MinerU cache compatibility."
  exit 0
}

& $zoteroMcp "serve"
if ($LASTEXITCODE -ne $null) {
  exit $LASTEXITCODE
}
