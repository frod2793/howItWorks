# ==============================================================================
# [기능]: PowerShell에서 프로필 기반 Unity 하네스 린트를 실행합니다.
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
    [Console]::Error.WriteLine("[PowerShell 하네스 린트] 지원하지 않는 출력 형식입니다: $Format")
    exit 3
}

$ScriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
$AgentsRoot = [System.IO.Path]::GetFullPath((Join-Path $ScriptDirectory "../.."))
$ProfileScript = Join-Path $AgentsRoot "scripts/shared/profile.ps1"
$DetectScript = Join-Path $AgentsRoot "scripts/shared/detect.ps1"
$LintScript = Join-Path $AgentsRoot "scripts/shared/lint.ps1"
$SchemaPath = Join-Path $AgentsRoot "config/profile-schema.conf"

foreach ($RequiredPath in @($ProfileScript, $DetectScript, $LintScript, $SchemaPath))
{
    if (-not (Test-Path -LiteralPath $RequiredPath -PathType Leaf))
    {
        [Console]::Error.WriteLine("[PowerShell 하네스 린트] 필수 스크립트 또는 스키마를 읽을 수 없습니다.")
        exit 4
    }
}

try
{
    . $ProfileScript
    . $DetectScript
    . $LintScript
}
catch
{
    [Console]::Error.WriteLine("[PowerShell 하네스 린트] 필수 스크립트를 로드할 수 없습니다: $($_.Exception.Message)")
    exit 4
}

if ([string]::IsNullOrEmpty($ProjectRoot))
{
    $ProjectRoot = [System.IO.Path]::GetFullPath((Join-Path $AgentsRoot ".."))
}
if ([string]::IsNullOrEmpty($Profile))
{
    $Profile = Join-Path $ProjectRoot ".agents/config/project-profile.conf"
}

if ([string]::IsNullOrEmpty($ProjectRoot) -or [string]::IsNullOrEmpty($Profile))
{
    [Console]::Error.WriteLine("[PowerShell 하네스 린트] 프로젝트와 프로필 경로가 필요합니다.")
    exit 3
}

try
{
    $Result = Invoke-HarnessLint -ProjectRoot $ProjectRoot -ProfilePath $Profile -SchemaPath $SchemaPath
}
catch
{
    [Console]::Error.WriteLine("[PowerShell 하네스 린트] 린트 실행 중 내부 오류가 발생했습니다: $($_.Exception.Message)")
    exit 4
}
if ($Format -eq "machine")
{
    foreach ($Line in @($Result.Output))
    {
        Write-Output $Line
    }
    exit ([int]$Result.ExitCode)
}

$ErrorCount = 0
$WarningCount = 0
foreach ($Line in @($Result.Output))
{
    $Parts = ([string]$Line).Split([char]'|')
    if ($Parts.Length -ne 5)
    {
        Write-Host $Line
        continue
    }
    $RuleId = $Parts[0]
    $Severity = $Parts[1]
    $Path = $Parts[2].Replace("%0A", "\n").Replace("%0D", "\r").Replace("%7C", "|").Replace("%25", "%")
    $LineNumber = $Parts[3]
    $Message = $Parts[4].Replace("%0A", "\n").Replace("%0D", "\r").Replace("%7C", "|").Replace("%25", "%")
    if ($Severity -eq "error")
    {
        $ErrorCount++
        $SeverityLabel = "오류"
    }
    else
    {
        $WarningCount++
        $SeverityLabel = "경고"
    }
    Write-Host "[$SeverityLabel] $RuleId ${Path}:$LineNumber - $Message"
}
Write-Host "[요약] 오류 $ErrorCount건, 경고 $WarningCount건"
exit ([int]$Result.ExitCode)
