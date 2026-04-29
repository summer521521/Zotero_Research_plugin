param(
  [switch]$Check
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

if ([string]::IsNullOrWhiteSpace($env:ZOTERO_LOCAL)) {
  $env:ZOTERO_LOCAL = "true"
}
if ([string]::IsNullOrWhiteSpace($env:ZOTERO_NO_CLAUDE)) {
  $env:ZOTERO_NO_CLAUDE = "true"
}

$zoteroMcp = $env:ZOTERO_MCP_EXE
if ([string]::IsNullOrWhiteSpace($zoteroMcp)) {
  $command = Get-Command "zotero-mcp" -ErrorAction SilentlyContinue
  if ($null -eq $command) {
    Fail "ZOTERO_MCP_EXE is not set and zotero-mcp is not available on PATH."
  }
  $zoteroMcp = $command.Source
} elseif (-not (Test-Path -LiteralPath $zoteroMcp -PathType Leaf)) {
  Fail "ZOTERO_MCP_EXE does not exist: $zoteroMcp"
}

Assert-OptionalLeaf "ZOTERO_DB_PATH" $env:ZOTERO_DB_PATH

if ($Check) {
  Write-Output "OK: ZOTERO_MCP_EXE or PATH command"
  if (-not [string]::IsNullOrWhiteSpace($env:ZOTERO_DB_PATH)) { Write-Output "OK: ZOTERO_DB_PATH" }
  Write-Output "OK: Zotero MCP wrapper environment is valid."
  exit 0
}

& $zoteroMcp "serve"
if ($LASTEXITCODE -ne $null) {
  exit $LASTEXITCODE
}
