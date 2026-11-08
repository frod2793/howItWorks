# ==============================================================================
# [기능]: Git 상태를 변경하지 않고 PowerShell 하네스 검사를 실행합니다.
# [작성자]: 윤승종
# ==============================================================================

param(
    [string]$ProjectRoot = "",
    [string]$Profile = "",
    [string]$Format = "human"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (@("human", "machine") -notcontains $Format)
{
    [Console]::Error.WriteLine("[PowerShell CI] 지원하지 않는 출력 형식입니다: $Format")
    exit 3
}

$ScriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
$CheckScript = [System.IO.Path]::GetFullPath((Join-Path $ScriptDirectory "../lint/check-harness.ps1"))
if (-not (Test-Path -LiteralPath $CheckScript -PathType Leaf))
{
    [Console]::Error.WriteLine("[PowerShell CI] 하네스 검사 스크립트를 읽을 수 없습니다: $CheckScript")
    exit 4
}

$Arguments = @("-Format", $Format)
if (-not [string]::IsNullOrEmpty($ProjectRoot))
{
    $Arguments += @("-ProjectRoot", $ProjectRoot)
}
if (-not [string]::IsNullOrEmpty($Profile))
{
    $Arguments += @("-Profile", $Profile)
}

& $CheckScript @Arguments
exit $LASTEXITCODE
