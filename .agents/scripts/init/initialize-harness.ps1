# ==============================================================================
# [기능]: PowerShell에서 Unity 하네스 감지, 재감지, 프로필 확정을 실행합니다.
# [작성자]: 윤승종
# ==============================================================================

param(
    [string]$ProjectRoot = "",
    [switch]$Confirm,
    [switch]$Redetect
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ($Confirm -and $Redetect)
{
    [Console]::Error.WriteLine("-Confirm과 -Redetect는 함께 사용할 수 없습니다.")
    exit 3
}

$ScriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
$AgentsRoot = [System.IO.Path]::GetFullPath((Join-Path $ScriptDirectory "../.."))
$ProfileScript = Join-Path $AgentsRoot "scripts/shared/profile.ps1"
$DetectScript = Join-Path $AgentsRoot "scripts/shared/detect.ps1"
$SchemaPath = Join-Path $AgentsRoot "config/profile-schema.conf"
$SignaturesPath = Join-Path $AgentsRoot "config/detection-signatures.conf"

foreach ($RequiredPath in @($ProfileScript, $DetectScript, $SchemaPath, $SignaturesPath))
{
    if (-not (Test-Path -LiteralPath $RequiredPath -PathType Leaf))
    {
        [Console]::Error.WriteLine("PowerShell 초기화 필수 파일을 읽을 수 없습니다: $RequiredPath")
        exit 4
    }
}

try
{
    . $ProfileScript
    . $DetectScript
}
catch
{
    [Console]::Error.WriteLine("[PowerShell 초기화] 필수 스크립트를 로드할 수 없습니다: $($_.Exception.Message)")
    exit 4
}

if ([string]::IsNullOrEmpty($ProjectRoot))
{
    $ProjectRoot = (Get-Location).Path
}

try
{
    $UnityRoot = Find-UnityProjectRoot -StartPath $ProjectRoot
}
catch
{
    [Console]::Error.WriteLine("[PowerShell 초기화] $($_.Exception.Message)")
    if ($_.Exception.Message.Contains("읽을 수 없습니다"))
    {
        exit 4
    }
    exit 2
}
if ([string]::IsNullOrEmpty($UnityRoot))
{
    [Console]::Error.WriteLine("[PowerShell 초기화] Unity 프로젝트 루트를 찾을 수 없습니다: $ProjectRoot")
    exit 2
}

$ProjectAgentsRoot = Join-Path $UnityRoot ".agents"
$ConfigDirectory = Join-Path $ProjectAgentsRoot "config"
$ReportDirectory = Join-Path $ProjectAgentsRoot "reports"
$ProfilePath = Join-Path $ConfigDirectory "project-profile.conf"
$CandidatePath = Join-Path $ConfigDirectory "project-profile.candidate.conf"
$ReportPath = Join-Path $ReportDirectory "detection-report.md"

foreach ($DirectoryPath in @($ProjectAgentsRoot, $ConfigDirectory))
{
    if (Test-HarnessReparsePoint -Path $DirectoryPath)
    {
        [Console]::Error.WriteLine("[PowerShell 초기화] 출력 디렉터리로 링크를 사용할 수 없습니다: $DirectoryPath")
        exit 2
    }
    if (-not (Test-Path -LiteralPath $DirectoryPath))
    {
        try
        {
            New-Item -ItemType Directory -Path $DirectoryPath -ErrorAction Stop | Out-Null
        }
        catch
        {
            [Console]::Error.WriteLine("[PowerShell 초기화] 출력 디렉터리를 만들 수 없습니다: $DirectoryPath")
            exit 2
        }
    }
    elseif (-not (Test-Path -LiteralPath $DirectoryPath -PathType Container))
    {
        [Console]::Error.WriteLine("[PowerShell 초기화] 출력 경로가 디렉터리가 아닙니다: $DirectoryPath")
        exit 2
    }
}

if ($Confirm)
{
    try
    {
        [void](Confirm-HarnessProfile -ProfilePath $ProfilePath -SchemaPath $SchemaPath)
        Write-Host "[PowerShell 초기화] 프로필 상태를 confirmed로 확정했습니다: $ProfilePath"
        exit 0
    }
    catch
    {
        [Console]::Error.WriteLine("[PowerShell 초기화] 프로필을 확정할 수 없습니다: $($_.Exception.Message)")
        exit 3
    }
}

if (Test-Path -LiteralPath $ProfilePath -PathType Leaf)
{
    try
    {
        $ExistingProfile = Read-HarnessProfile -ProfilePath $ProfilePath -SchemaPath $SchemaPath
        if ([string]$ExistingProfile["confirmation_status"] -eq "confirmed" -and -not $Redetect)
        {
            Write-Host "[PowerShell 초기화] 기존 확정 프로필을 보존했습니다: $ProfilePath"
            Write-Host "[PowerShell 초기화] 비교 후보가 필요하면 -Redetect를 사용하십시오."
            exit 0
        }
    }
    catch
    {
        [Console]::Error.WriteLine("[PowerShell 초기화] 기존 프로필 스키마 검증에 실패했습니다: $($_.Exception.Message)")
        exit 3
    }
}

if (-not (Test-Path -LiteralPath $ReportDirectory))
{
    try
    {
        New-Item -ItemType Directory -Path $ReportDirectory -ErrorAction Stop | Out-Null
    }
    catch
    {
        [Console]::Error.WriteLine("[PowerShell 초기화] 보고서 디렉터리를 만들 수 없습니다: $ReportDirectory")
        exit 2
    }
}
if (Test-HarnessReparsePoint -Path $ReportDirectory)
{
    [Console]::Error.WriteLine("[PowerShell 초기화] 보고서 디렉터리로 링크를 사용할 수 없습니다: $ReportDirectory")
    exit 2
}

$OutputProfilePath = if ($Redetect) { $CandidatePath } else { $ProfilePath }
if ($Redetect -and (Test-Path -LiteralPath $ProfilePath -PathType Leaf))
{
    $Result = Invoke-ProjectDetection -ProjectRoot $UnityRoot -ProfilePath $OutputProfilePath -ReportPath $ReportPath -SchemaPath $SchemaPath -SignaturesPath $SignaturesPath -ComparisonProfilePath $ProfilePath
}
else
{
    $Result = Invoke-ProjectDetection -ProjectRoot $UnityRoot -ProfilePath $OutputProfilePath -ReportPath $ReportPath -SchemaPath $SchemaPath -SignaturesPath $SignaturesPath
}
if (-not [string]::IsNullOrEmpty([string]$Result.Output))
{
    Write-Host ([string]$Result.Output)
}
if ([int]$Result.ExitCode -ne 0)
{
    exit ([int]$Result.ExitCode)
}

if ($Redetect)
{
    Write-Host "[PowerShell 초기화] 재감지 후보 프로필을 생성했습니다: $CandidatePath"
}
else
{
    Write-Host "[PowerShell 초기화] 감지 결과는 pending입니다. 보고서를 검토한 뒤 -Confirm을 실행하십시오."
}
exit 0
