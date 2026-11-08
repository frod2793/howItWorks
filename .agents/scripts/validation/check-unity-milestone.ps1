# ==============================================================================
# [기능]: Unity 마일스톤 증거가 사전 빌드 또는 빌드 완료 게이트를 충족하는지 확인합니다.
# [작성자]: 윤승종
# ==============================================================================

[CmdletBinding()]
param(
    [AllowEmptyString()]
    [string]$Evidence,

    [AllowEmptyString()]
    [string]$Phase,

    [AllowEmptyString()]
    [string]$ExpectedChangeId,

    [AllowEmptyString()]
    [string]$ExpectedAuthority = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ScriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
$AgentsRoot = Split-Path -Parent (Split-Path -Parent $ScriptDirectory)
$ProfileScript = Join-Path $AgentsRoot "scripts/shared/profile.ps1"
$SchemaPath = Join-Path $AgentsRoot "config/unity-milestone-validation-schema.conf"

function Stop-MilestoneValidation
{
    param(
        [int]$Code,
        [string]$Message
    )

    [Console]::Error.WriteLine("[마일스톤 검증] $Message")
    exit $Code
}

function Test-MilestoneOrdinalEquals
{
    param(
        [AllowNull()]
        [string]$Left,
        [AllowNull()]
        [string]$Right
    )

    return $Left -ceq $Right -and [string]::Equals($Left, $Right, [System.StringComparison]::Ordinal)
}

function Stop-MilestoneArgument
{
    param([string]$Message)

    Stop-MilestoneValidation -Code 3 -Message "잘못된 인자: $Message"
}

function Test-MilestoneRegularFile
{
    param(
        [string]$Label,
        [string]$Path
    )

    try
    {
        if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Leaf))
        {
            Stop-MilestoneValidation -Code 4 -Message "입력 오류: $Label 파일을 읽을 수 없습니다: $Path"
        }

        $Item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
        $DisallowedAttributes = [System.IO.FileAttributes]::Directory -bor [System.IO.FileAttributes]::Device -bor [System.IO.FileAttributes]::ReparsePoint
        if ($Item -isnot [System.IO.FileInfo] -or ($Item.Attributes -band $DisallowedAttributes) -ne 0)
        {
            Stop-MilestoneValidation -Code 4 -Message "입력 오류: $Label 파일은 일반 파일이어야 합니다: $Path"
        }

        # FIFO는 PowerShell의 이식 가능한 FileInfo/Attributes API로 구별할 수 없고 열기 자체가 블로킹될 수 있습니다.
        # 이 검증기의 profile.ps1·schema·evidence는 모두 비어 있을 수 없으므로, 길이 0 leaf는 읽기 전에 거부합니다.
        if ($Item.Length -le 0)
        {
            Stop-MilestoneValidation -Code 4 -Message "입력 오류: $Label 파일은 비어 있을 수 없습니다: $Path"
        }

        $Stream = [System.IO.File]::Open($Item.FullName, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        try
        {
            [void]$Stream.ReadByte()
        }
        finally
        {
            $Stream.Dispose()
        }
    }
    catch
    {
        Stop-MilestoneValidation -Code 4 -Message "입력 오류: $Label 파일을 확인할 수 없습니다: $Path"
    }
}

function Test-MilestoneIdentifier
{
    param(
        [string]$Label,
        [AllowNull()]
        [string]$Value
    )

    if ([string]::IsNullOrWhiteSpace($Value) -or (Test-MilestoneOrdinalEquals -Left $Value -Right "none") -or $Value -cne $Value.Trim())
    {
        Stop-MilestoneValidation -Code 1 -Message "게이트 실패: $Label는 비어 있거나 공백으로 시작 또는 끝날 수 없습니다."
    }
}

function Get-MilestoneProfileValue
{
    param(
        [System.Collections.IDictionary]$Profile,
        [string]$Key
    )

    if (-not $Profile.Contains($Key))
    {
        Stop-MilestoneValidation -Code 4 -Message "입력 오류: 증거에서 $Key 값을 읽을 수 없습니다."
    }

    return [string]$Profile[$Key]
}

function Test-MilestoneListContains
{
    param(
        [string[]]$Values,
        [AllowNull()]
        [string]$Expected
    )

    foreach ($Value in $Values)
    {
        if (Test-MilestoneOrdinalEquals -Left $Value -Right $Expected)
        {
            return $true
        }
    }

    return $false
}

function Test-MilestoneScopeRecords
{
    param(
        [System.Collections.IDictionary]$Profile,
        [string]$Key
    )

    if (-not $Profile.Contains($Key))
    {
        Stop-MilestoneValidation -Code 4 -Message "입력 오류: 증거에서 $Key 기록을 읽을 수 없습니다."
    }

    $Scopes = @($Profile[$Key])
    if ($Scopes.Count -eq 0)
    {
        Stop-MilestoneValidation -Code 1 -Message "게이트 실패: $Key 기록이 하나 이상 필요합니다."
    }

    $ValidatedScopes = @()
    foreach ($ScopeObject in $Scopes)
    {
        $Scope = [string]$ScopeObject
        Test-MilestoneIdentifier -Label $Key -Value $Scope
        if ($Scope.IndexOf([char]'|') -ge 0)
        {
            Stop-MilestoneValidation -Code 1 -Message "게이트 실패: $Key 항목에는 구분자 |를 사용할 수 없습니다: $Scope"
        }
        if (Test-MilestoneListContains -Values $ValidatedScopes -Expected $Scope)
        {
            Stop-MilestoneValidation -Code 1 -Message "게이트 실패: $Key 항목이 중복되었습니다: $Scope"
        }

        $ValidatedScopes += $Scope
    }

    return [PSCustomObject]@{ Values = [string[]]$ValidatedScopes }
}

function Test-MilestoneResultRecords
{
    param(
        [System.Collections.IDictionary]$Profile,
        [string]$Key,
        [string[]]$ExpectedSubjects
    )

    if (-not $Profile.Contains($Key))
    {
        Stop-MilestoneValidation -Code 4 -Message "입력 오류: 증거에서 $Key 기록을 읽을 수 없습니다."
    }

    $Records = @($Profile[$Key])
    if ($Records.Count -eq 0)
    {
        Stop-MilestoneValidation -Code 1 -Message "게이트 실패: $Key 기록이 하나 이상 필요합니다."
    }

    $ResultSubjects = @()
    foreach ($RecordObject in $Records)
    {
        $Record = [string]$RecordObject
        $Parts = $Record.Split([char[]]@([char]'|'))
        if ($Parts.Length -ne 3)
        {
            Stop-MilestoneValidation -Code 1 -Message "게이트 실패: $Key 기록 형식이 올바르지 않습니다: $Record"
        }

        Test-MilestoneIdentifier -Label "$Key subject" -Value $Parts[0]
        Test-MilestoneIdentifier -Label "$Key automated-test-id" -Value $Parts[1]
        if (-not (Test-MilestoneOrdinalEquals -Left $Parts[2] -Right "passed"))
        {
            Stop-MilestoneValidation -Code 1 -Message "게이트 실패: $Key 기록이 통과 증거가 아닙니다: $Record"
        }
        if (Test-MilestoneListContains -Values $ResultSubjects -Expected $Parts[0])
        {
            Stop-MilestoneValidation -Code 1 -Message "게이트 실패: $Key subject가 중복되었습니다: $($Parts[0])"
        }
        if (-not (Test-MilestoneListContains -Values $ExpectedSubjects -Expected $Parts[0]))
        {
            Stop-MilestoneValidation -Code 1 -Message "게이트 실패: $Key subject가 확정 scope에 없습니다: $($Parts[0])"
        }

        $ResultSubjects += $Parts[0]
    }

    foreach ($ExpectedSubject in $ExpectedSubjects)
    {
        if (-not (Test-MilestoneListContains -Values $ResultSubjects -Expected $ExpectedSubject))
        {
            Stop-MilestoneValidation -Code 1 -Message "게이트 실패: $Key에 확정 scope 결과가 누락되었습니다: $ExpectedSubject"
        }
    }
}

if ([string]::IsNullOrWhiteSpace($Evidence))
{
    Stop-MilestoneArgument -Message "-Evidence 뒤에 증거 파일 경로가 필요합니다."
}

if ((-not (Test-MilestoneOrdinalEquals -Left $Phase -Right "prebuild")) -and (-not (Test-MilestoneOrdinalEquals -Left $Phase -Right "built")))
{
    Stop-MilestoneArgument -Message "-Phase에는 prebuild 또는 built가 필요합니다."
}

if ([string]::IsNullOrWhiteSpace($ExpectedChangeId) -or (Test-MilestoneOrdinalEquals -Left $ExpectedChangeId -Right "none") -or $ExpectedChangeId -cne $ExpectedChangeId.Trim())
{
    Stop-MilestoneArgument -Message "-ExpectedChangeId에는 공백 없이 비어 있지 않은 변경 식별자가 필요합니다."
}
if ($ExpectedAuthority -ne "" -and $ExpectedAuthority -cne "local" -and $ExpectedAuthority -cne "unity_ci")
{
    Stop-MilestoneArgument -Message "-ExpectedAuthority에는 local 또는 unity_ci가 필요합니다."
}
if ((Test-MilestoneOrdinalEquals -Left $Phase -Right "built") -and $ExpectedAuthority -eq "")
{
    Stop-MilestoneArgument -Message "built에는 -ExpectedAuthority가 필요합니다."
}

Test-MilestoneIdentifier -Label "ExpectedChangeId" -Value $ExpectedChangeId
Test-MilestoneRegularFile -Label "profile.ps1" -Path $ProfileScript
Test-MilestoneRegularFile -Label "스키마" -Path $SchemaPath
Test-MilestoneRegularFile -Label "증거" -Path $Evidence

try
{
    . $ProfileScript
}
catch
{
    Stop-MilestoneValidation -Code 4 -Message "입력 오류: profile.ps1을 불러올 수 없습니다."
}

if ($null -eq (Get-Command -Name "Read-HarnessProfile" -CommandType Function -ErrorAction SilentlyContinue))
{
    Stop-MilestoneValidation -Code 4 -Message "입력 오류: profile.ps1에 Read-HarnessProfile 명령이 없습니다."
}

try
{
    $Profiles = @(Read-HarnessProfile -ProfilePath $Evidence -SchemaPath $SchemaPath)
    if ($Profiles.Count -ne 1 -or $Profiles[0] -isnot [System.Collections.IDictionary])
    {
        throw "Read-HarnessProfile은 하나의 IDictionary를 반환해야 합니다."
    }

    $Profile = [System.Collections.IDictionary]$Profiles[0]
}
catch
{
    Stop-MilestoneValidation -Code 4 -Message "입력 오류: 증거 파일 형식이 올바르지 않습니다."
}

$CoverageStatus = @($Profile["coverage_status"])
if ($CoverageStatus.Count -ne 1 -or -not (Test-MilestoneOrdinalEquals -Left $CoverageStatus[0] -Right "confirmed"))
{
    Stop-MilestoneValidation -Code 1 -Message "게이트 실패: coverage_status는 정확히 한 번 confirmed여야 합니다."
}

$MilestoneId = Get-MilestoneProfileValue -Profile $Profile -Key "milestone_id"
$ChangeId = Get-MilestoneProfileValue -Profile $Profile -Key "change_id"
$BuildAuthority = Get-MilestoneProfileValue -Profile $Profile -Key "build_authority"
$CompileResult = Get-MilestoneProfileValue -Profile $Profile -Key "compile"
$UnitTestResult = Get-MilestoneProfileValue -Profile $Profile -Key "unit_test"
$IntegrationTestResult = Get-MilestoneProfileValue -Profile $Profile -Key "integration_test"
$BuildValidationResult = Get-MilestoneProfileValue -Profile $Profile -Key "build_validation"
$BuildRunId = Get-MilestoneProfileValue -Profile $Profile -Key "build_run_id"
$BuildArtifactHash = Get-MilestoneProfileValue -Profile $Profile -Key "build_artifact_hash"

Test-MilestoneIdentifier -Label "milestone_id" -Value $MilestoneId
Test-MilestoneIdentifier -Label "change_id" -Value $ChangeId
if (-not (Test-MilestoneOrdinalEquals -Left $ChangeId -Right $ExpectedChangeId))
{
    Stop-MilestoneValidation -Code 1 -Message "게이트 실패: change_id가 예상값과 다릅니다."
}
if ($ExpectedAuthority -ne "" -and -not (Test-MilestoneOrdinalEquals -Left $BuildAuthority -Right $ExpectedAuthority))
{
    Stop-MilestoneValidation -Code 1 -Message "게이트 실패: build_authority가 선택한 권위와 다릅니다."
}

if (-not (Test-MilestoneOrdinalEquals -Left $CompileResult -Right "passed"))
{
    Stop-MilestoneValidation -Code 1 -Message "게이트 실패: compile이 passed여야 합니다."
}

if (-not (Test-MilestoneOrdinalEquals -Left $UnitTestResult -Right "passed"))
{
    Stop-MilestoneValidation -Code 1 -Message "게이트 실패: unit_test가 passed여야 합니다."
}

if (-not (Test-MilestoneOrdinalEquals -Left $IntegrationTestResult -Right "passed"))
{
    Stop-MilestoneValidation -Code 1 -Message "게이트 실패: integration_test가 passed여야 합니다."
}

$ModuleScopeState = Test-MilestoneScopeRecords -Profile $Profile -Key "module_scope"
$InteractionScopeState = Test-MilestoneScopeRecords -Profile $Profile -Key "interaction_scope"
Test-MilestoneResultRecords -Profile $Profile -Key "module_result" -ExpectedSubjects $ModuleScopeState.Values
Test-MilestoneResultRecords -Profile $Profile -Key "interaction_result" -ExpectedSubjects $InteractionScopeState.Values

if (Test-MilestoneOrdinalEquals -Left $Phase -Right "prebuild")
{
    if (-not (Test-MilestoneOrdinalEquals -Left $BuildValidationResult -Right "pending"))
    {
        Stop-MilestoneValidation -Code 1 -Message "게이트 실패: prebuild에서는 build_validation이 pending이어야 합니다."
    }
    if (-not (Test-MilestoneOrdinalEquals -Left $BuildRunId -Right "pending"))
    {
        Stop-MilestoneValidation -Code 1 -Message "게이트 실패: prebuild에서는 build_run_id가 pending이어야 합니다."
    }
    if (-not (Test-MilestoneOrdinalEquals -Left $BuildArtifactHash -Right "pending"))
    {
        Stop-MilestoneValidation -Code 1 -Message "게이트 실패: prebuild에서는 build_artifact_hash가 pending이어야 합니다."
    }
}

if (Test-MilestoneOrdinalEquals -Left $Phase -Right "built")
{
    if (-not (Test-MilestoneOrdinalEquals -Left $BuildValidationResult -Right "passed"))
    {
        Stop-MilestoneValidation -Code 1 -Message "게이트 실패: built에서는 build_validation이 passed여야 합니다."
    }

    Test-MilestoneIdentifier -Label "build_run_id" -Value $BuildRunId
    if (@("pending", "none", "n/a", "not_run", "unknown", "tbd", "-") -ccontains $BuildRunId.Trim().ToLowerInvariant())
    {
        Stop-MilestoneValidation -Code 1 -Message "게이트 실패: built에서는 build_run_id에 실제 실행 ID가 필요합니다."
    }

    Test-MilestoneIdentifier -Label "build_artifact_hash" -Value $BuildArtifactHash
    if (-not [regex]::IsMatch($BuildArtifactHash, '\A[0-9a-f]{64}\z', [System.Text.RegularExpressions.RegexOptions]::CultureInvariant))
    {
        Stop-MilestoneValidation -Code 1 -Message "게이트 실패: built에서는 build_artifact_hash가 lowercase SHA-256이어야 합니다."
    }
}

Write-Output "[마일스톤 검증] phase=$Phase milestone=$MilestoneId change=$ChangeId authority=$BuildAuthority"
exit 0
