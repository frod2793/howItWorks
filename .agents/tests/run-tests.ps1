# ==============================================================================
# [기능]: 범용 Unity 하네스의 PowerShell 계약 테스트를 실행하고 결과를 집계합니다.
# [작성자]: 윤승종
# ==============================================================================

param(
    [string]$Group = "all",
    [string]$Runtime = "all",
    [string]$ParityProjectRoot = "",
    [string]$ParityProfilePath = "",
    [string]$ParityReportPath = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ValidGroups = @("all", "profile", "detection", "readonly", "lint", "tooling", "validation", "parity")
$ValidRuntimes = @("all", "powershell")

if ($ValidGroups -notcontains $Group)
{
    Write-Host "지원하지 않는 테스트 그룹입니다: $Group"
    exit 2
}

if ($Runtime -eq "bash")
{
    Write-Host "PowerShell 러너에서는 Bash 테스트를 실행할 수 없습니다."
    exit 2
}

if ($ValidRuntimes -notcontains $Runtime)
{
    Write-Host "지원하지 않는 런타임입니다: $Runtime"
    exit 2
}

$ScriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
$AgentsRoot = Split-Path -Parent $ScriptDirectory
$SchemaPath = Join-Path $AgentsRoot "config/profile-schema.conf"
$SignaturesPath = Join-Path $AgentsRoot "config/detection-signatures.conf"
$ProfileScript = Join-Path $AgentsRoot "scripts/shared/profile.ps1"
$DetectScript = Join-Path $AgentsRoot "scripts/shared/detect.ps1"
$LintScript = Join-Path $AgentsRoot "scripts/shared/lint.ps1"
$InitializerScript = Join-Path $AgentsRoot "scripts/init/initialize-harness.ps1"
$ToolingScript = Join-Path $AgentsRoot "scripts/setup/check-agent-tooling.ps1"
$MilestoneValidator = Join-Path $AgentsRoot "scripts/validation/check-unity-milestone.ps1"
$MilestoneSchema = Join-Path $AgentsRoot "config/unity-milestone-validation-schema.conf"
$TestTempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("unity-harness-tests-" + [Guid]::NewGuid().ToString("N"))
$script:Utf8WithoutBom = New-Object System.Text.UTF8Encoding($false, $true)

$script:SelectedCount = 0
$script:PassedCount = 0
$script:FailedCount = 0
$script:SkippedCount = 0
$script:IsCurrentTestSkipped = $false
$script:CurrentTestSkipReason = ""
$script:HarnessProductionApisImported = $false
$script:ParityInputsProvided = -not [string]::IsNullOrEmpty($ParityProjectRoot) -and
    -not [string]::IsNullOrEmpty($ParityProfilePath) -and
    -not [string]::IsNullOrEmpty($ParityReportPath)

function Assert-Equal
{
    param(
        [object]$Expected,
        [object]$Actual,
        [string]$Message
    )

    if ([string]$Expected -ne [string]$Actual)
    {
        throw "$Message 기대값=[$Expected], 실제값=[$Actual]"
    }
}

function Assert-True
{
    param(
        [bool]$Condition,
        [string]$Message
    )

    if (-not $Condition)
    {
        throw $Message
    }
}

function Assert-ExitCode
{
    param(
        [int]$Expected,
        [object]$Result,
        [string]$Message
    )

    Assert-Equal -Expected $Expected -Actual ([int]$Result.ExitCode) -Message $Message
}

function Assert-Contains
{
    param(
        [string]$Actual,
        [string]$ExpectedFragment,
        [string]$Message
    )

    if (-not $Actual.Contains($ExpectedFragment))
    {
        throw "$Message [$ExpectedFragment] 문자열이 없습니다."
    }
}

function Assert-NotContains
{
    param(
        [string]$Actual,
        [string]$UnexpectedFragment,
        [string]$Message
    )

    if ($Actual.Contains($UnexpectedFragment))
    {
        throw "$Message 허용되지 않은 [$UnexpectedFragment] 문자열이 있습니다."
    }
}

function Assert-FileExists
{
    param(
        [string]$Path,
        [string]$Message
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf))
    {
        throw "$Message 파일이 없습니다: $Path"
    }
}

function Assert-FileNotExists
{
    param(
        [string]$Path,
        [string]$Message
    )

    if (Test-Path -LiteralPath $Path)
    {
        throw "$Message 파일이 생성되었습니다: $Path"
    }
}

function Assert-CrLfFile
{
    param([string]$Path)

    $Bytes = [System.IO.File]::ReadAllBytes($Path)
    $LineEndingCount = 0
    for ($Index = 0; $Index -lt $Bytes.Length; $Index++)
    {
        if ($Bytes[$Index] -eq 0x0A)
        {
            if ($Index -eq 0 -or $Bytes[$Index - 1] -ne 0x0D)
            {
                throw "CRLF 픽스처에 단독 LF 바이트가 있습니다: $Path"
            }

            $LineEndingCount++
        }
        elseif ($Bytes[$Index] -eq 0x0D)
        {
            if ($Index + 1 -ge $Bytes.Length -or $Bytes[$Index + 1] -ne 0x0A)
            {
                throw "CRLF 픽스처에 단독 CR 바이트가 있습니다: $Path"
            }
        }
    }

    if ($LineEndingCount -eq 0)
    {
        throw "CRLF 픽스처에 줄 끝 바이트가 없습니다: $Path"
    }
}

function Assert-CommandExists
{
    param([string]$Name)

    if ($null -eq (Get-Command -Name $Name -ErrorAction SilentlyContinue))
    {
        throw "필수 명령을 찾을 수 없습니다: $Name"
    }
}

function Skip-CurrentTest
{
    param([string]$Reason)

    $script:IsCurrentTestSkipped = $true
    $script:CurrentTestSkipReason = $Reason
    throw "테스트 건너뜀: $Reason"
}

function Write-Utf8WithoutBomLines
{
    param(
        [string]$Path,
        [string[]]$Lines
    )

    [System.IO.File]::WriteAllLines($Path, $Lines, $script:Utf8WithoutBom)
}

function Read-Utf8WithoutBomLines
{
    param([string]$Path)

    $Bytes = [System.IO.File]::ReadAllBytes($Path)
    if ($Bytes.Length -ge 3 -and $Bytes[0] -eq 0xEF -and $Bytes[1] -eq 0xBB -and $Bytes[2] -eq 0xBF)
    {
        throw "설정 파일에 허용되지 않은 UTF-8 BOM이 있습니다: $Path"
    }

    return [System.IO.File]::ReadAllLines($Path, $script:Utf8WithoutBom)
}

Read-Utf8WithoutBomLines -Path $SchemaPath | Out-Null
Read-Utf8WithoutBomLines -Path $SignaturesPath | Out-Null
Assert-FileExists -Path $ProfileScript -Message "profile.ps1 파일을 찾을 수 없습니다."
Assert-FileExists -Path $DetectScript -Message "detect.ps1 파일을 찾을 수 없습니다."
Assert-FileExists -Path $LintScript -Message "lint.ps1 파일을 찾을 수 없습니다."
. $ProfileScript
. $DetectScript
. $LintScript
$script:HarnessProductionApisImported = $true

function Import-ProfileApi
{
    Assert-True -Condition $script:HarnessProductionApisImported -Message "PowerShell 운영 API가 스크립트 범위에 로드되지 않았습니다."
    Assert-CommandExists -Name "Read-HarnessProfile"
    Assert-CommandExists -Name "Test-HarnessProfile"
    Assert-CommandExists -Name "Write-HarnessProfile"
}

function Import-DetectionApi
{
    Import-ProfileApi
    Assert-CommandExists -Name "Invoke-ProjectDetection"
}

function Import-LintApi
{
    Import-ProfileApi
    Assert-CommandExists -Name "Invoke-HarnessLint"
}

function New-ValidProfile
{
    param(
        [string]$Path,
        [string]$ConfirmationStatus,
        [string]$Architecture,
        [string]$ProjectName,
        [string]$SecondSourceRoot = ""
    )

    $Lines = @(
        "profile_version=1"
        "confirmation_status=$ConfirmationStatus"
        "project_name=$ProjectName"
        "unity_version=6000.3.16f1"
        "render_pipeline=urp"
        "architecture=$Architecture"
        "source_root=Assets/_Game"
        "dependency_injection=vcontainer"
        "async_backend=unitask"
        "tween_backend=dotween"
        "target_platform=unknown"
        "response_language=ko"
        "log_language=ko"
        "author_name=윤승종"
        "private_field_prefix=m_"
        "ui_callback_prefix=func_"
        "region_policy=encouraged"
        "xml_documentation_policy=all_methods"
        "gpu_resident_drawer=unknown"
        "gpu_occlusion_culling=unknown"
        "stp=unknown"
        "mesh_lod=unknown"
        "exclude_root=Assets/Plugins"
        "exclude_root=Assets/ThirdParty"
    )

    if (-not [string]::IsNullOrEmpty($SecondSourceRoot))
    {
        $Lines += "source_root=$SecondSourceRoot"
    }

    Write-Utf8WithoutBomLines -Path $Path -Lines $Lines
}

function New-MilestoneEvidence
{
    param(
        [string]$Path,
        [string]$IntegrationResult,
        [string]$BuildResult
    )

    Write-Utf8WithoutBomLines -Path $Path -Lines @(
        "validation_version=1"
        "milestone_id=login-flow"
        "change_id=commit-abc123"
        "coverage_status=confirmed"
        "build_authority=local"
        "compile=passed"
        "unit_test=passed"
        "integration_test=$IntegrationResult"
        "module_scope=Login"
        "module_scope=Profile"
        "interaction_scope=Login>Profile"
        "module_result=Login|Game.Tests.LoginModuleTests|passed"
        "module_result=Profile|Game.Tests.ProfileModuleTests|passed"
        "interaction_result=Login>Profile|Game.Tests.LoginProfileFlowTests|passed"
        "build_validation=$BuildResult"
        "build_run_id=pending"
        "build_artifact_hash=pending"
    )
}

function Invoke-MilestoneValidation
{
    param(
        [string]$EvidencePath,
        [string]$Phase,
        [string]$ExpectedChangeId,
        [string]$ValidatorPath = $MilestoneValidator,
        [string]$ExpectedAuthority = "local"
    )

    $Arguments = @(
        "-Evidence"
        $EvidencePath
        "-Phase"
        $Phase
        "-ExpectedChangeId"
        $ExpectedChangeId
    )
    if ($ExpectedAuthority -ne "") { $Arguments += @("-ExpectedAuthority", $ExpectedAuthority) }
    return Invoke-ChildPowerShell -ScriptPath $ValidatorPath -NonInteractive -Arguments $Arguments
}

function New-MilestoneValidatorFixture
{
    param([string]$FixtureRoot)

    $FixtureAgentsRoot = Join-Path $FixtureRoot ".agents"
    $FixtureValidationRoot = Join-Path $FixtureAgentsRoot "scripts/validation"
    $FixtureSharedRoot = Join-Path $FixtureAgentsRoot "scripts/shared"
    $FixtureConfigRoot = Join-Path $FixtureAgentsRoot "config"
    New-Item -ItemType Directory -Path $FixtureValidationRoot, $FixtureSharedRoot, $FixtureConfigRoot -Force | Out-Null
    Copy-Item -LiteralPath $MilestoneValidator -Destination (Join-Path $FixtureValidationRoot "check-unity-milestone.ps1") -Force
    Copy-Item -LiteralPath $ProfileScript -Destination (Join-Path $FixtureSharedRoot "profile.ps1") -Force
    Copy-Item -LiteralPath $MilestoneSchema -Destination (Join-Path $FixtureConfigRoot "unity-milestone-validation-schema.conf") -Force
    Copy-Item -LiteralPath (Join-Path $AgentsRoot "config/unity-milestone-validation.example.conf") -Destination (Join-Path $FixtureConfigRoot "evidence.conf") -Force
}

function Set-MilestoneEvidenceValues
{
    param(
        [string]$Path,
        [System.Collections.IDictionary]$Values
    )

    $UpdatedLines = @((Read-Utf8WithoutBomLines -Path $Path) | ForEach-Object {
        $SeparatorIndex = $_.IndexOf([char]'=')
        $Key = if ($SeparatorIndex -lt 0) { "" } else { $_.Substring(0, $SeparatorIndex) }
        if ($Values.Contains($Key)) { "$Key=$($Values[$Key])" } else { $_ }
    })
    Write-Utf8WithoutBomLines -Path $Path -Lines $UpdatedLines
}

function New-UnityFixture
{
    param(
        [string]$ProjectRoot,
        [string]$FixtureKind
    )

    New-Item -ItemType Directory -Path (Join-Path $ProjectRoot "ProjectSettings") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $ProjectRoot "Packages") -Force | Out-Null
    Write-Utf8WithoutBomLines -Path (Join-Path $ProjectRoot "ProjectSettings/ProjectVersion.txt") -Lines @("m_EditorVersion: 6000.3.16f1")
    Write-Utf8WithoutBomLines -Path (Join-Path $ProjectRoot "ProjectSettings/GraphicsSettings.asset") -Lines @("m_CustomRenderPipeline: {fileID: 0}")

    if ($FixtureKind -eq "mvvm")
    {
        $ViewsPath = Join-Path $ProjectRoot "Assets/_Game/Scripts/Views"
        $ViewModelsPath = Join-Path $ProjectRoot "Assets/_Game/Scripts/ViewModels"
        $ModelsPath = Join-Path $ProjectRoot "Assets/_Game/Scripts/Models"
        New-Item -ItemType Directory -Path $ViewsPath, $ViewModelsPath, $ModelsPath -Force | Out-Null
        Write-Utf8WithoutBomLines -Path (Join-Path $ProjectRoot "Packages/manifest.json") -Lines @(
            "{"
            '  "dependencies": {'
            '    "com.unity.render-pipelines.universal": "17.0.3",'
            '    "jp.hadashikick.vcontainer": "1.16.8",'
            '    "com.cysharp.unitask": "2.5.10"'
            "  }"
            "}"
        )
        Write-Utf8WithoutBomLines -Path (Join-Path $ViewsPath "GameView.cs") -Lines @(
            "using VContainer;"
            "using Cysharp.Threading.Tasks;"
            "using DG.Tweening;"
            "public sealed class GameView { }"
        )
        Write-Utf8WithoutBomLines -Path (Join-Path $ViewModelsPath "GameViewModel.cs") -Lines @("public sealed class GameViewModel { }")
        Write-Utf8WithoutBomLines -Path (Join-Path $ModelsPath "GameModel.cs") -Lines @("public sealed class GameModel { }")
    }
    else
    {
        $ViewsPath = Join-Path $ProjectRoot "Assets/_Game/Scripts/Views"
        $ViewModelsPath = Join-Path $ProjectRoot "Assets/_Game/Scripts/ViewModels"
        $PresentersPath = Join-Path $ProjectRoot "Assets/_Game/Scripts/Presenters"
        $ModelsPath = Join-Path $ProjectRoot "Assets/_Game/Scripts/Models"
        New-Item -ItemType Directory -Path $ViewsPath, $ViewModelsPath, $PresentersPath, $ModelsPath -Force | Out-Null
        Write-Utf8WithoutBomLines -Path (Join-Path $ProjectRoot "Packages/manifest.json") -Lines @('{ "dependencies": {} }')
        Write-Utf8WithoutBomLines -Path (Join-Path $ViewsPath "GameView.cs") -Lines @("public sealed class GameView { }")
        Write-Utf8WithoutBomLines -Path (Join-Path $ViewModelsPath "GameViewModel.cs") -Lines @("public sealed class GameViewModel { }")
        Write-Utf8WithoutBomLines -Path (Join-Path $PresentersPath "GamePresenter.cs") -Lines @("public sealed class GamePresenter { }")
        Write-Utf8WithoutBomLines -Path (Join-Path $ModelsPath "GameModel.cs") -Lines @("public sealed class GameModel { }")
    }
}

function New-LintFixture
{
    param([string]$ProjectRoot)

    $ViewsPath = Join-Path $ProjectRoot "Assets/_Game/Views"
    New-Item -ItemType Directory -Path $ViewsPath -Force | Out-Null
    Write-Utf8WithoutBomLines -Path (Join-Path $ViewsPath "InventoryView.cs") -Lines @(
        "using Sample.Models;"
        "namespace Sample.Views"
        "{"
        "    public sealed class InventoryView"
        "    {"
        "        private InventoryModel m_model;"
        "    }"
        "}"
    )
}

function Get-ProjectSnapshot
{
    param([string]$ProjectRoot)

    $NormalizedProjectRoot = [System.IO.Path]::GetFullPath($ProjectRoot).TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar)
    $AgentsPrefix = ".agents" + [System.IO.Path]::DirectorySeparatorChar
    $Snapshot = @()
    $Files = Get-ChildItem -LiteralPath $ProjectRoot -Recurse -File | Sort-Object FullName

    foreach ($File in $Files)
    {
        $NormalizedFilePath = [System.IO.Path]::GetFullPath($File.FullName)
        $RelativePath = $NormalizedFilePath.Substring($NormalizedProjectRoot.Length).TrimStart(
            [System.IO.Path]::DirectorySeparatorChar,
            [System.IO.Path]::AltDirectorySeparatorChar)
        $IsAgentsPath = $RelativePath.Equals(".agents", [System.StringComparison]::OrdinalIgnoreCase) -or
            $RelativePath.StartsWith($AgentsPrefix, [System.StringComparison]::OrdinalIgnoreCase)
        if ($IsAgentsPath)
        {
            continue
        }

        $Hash = (Get-FileHash -LiteralPath $File.FullName -Algorithm SHA256).Hash
        $Snapshot += "$RelativePath|$Hash"
    }

    return [string]::Join([Environment]::NewLine, $Snapshot)
}

function Invoke-ChildPowerShell
{
    param(
        [string]$ScriptPath,
        [string[]]$Arguments,
        [switch]$NonInteractive
    )

    $HostPath = (Get-Process -Id $PID).Path
    $Output = if ($NonInteractive)
    {
        @(& $HostPath -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $ScriptPath @Arguments 2>&1)
    }
    else
    {
        @(& $HostPath -NoProfile -ExecutionPolicy Bypass -File $ScriptPath @Arguments 2>&1)
    }
    return [PSCustomObject]@{
        ExitCode = $LASTEXITCODE
        Output = [string]::Join([Environment]::NewLine, @($Output))
    }
}

function Get-DetectionResult
{
    param(
        [string]$ProjectRoot,
        [string]$ProfilePath,
        [string]$ReportPath
    )

    return Invoke-ProjectDetection -ProjectRoot $ProjectRoot -ProfilePath $ProfilePath -ReportPath $ReportPath -SchemaPath $SchemaPath -SignaturesPath $SignaturesPath
}

function test_profile_accepts_repeated_source_roots
{
    $CaseRoot = Join-Path $TestTempRoot "profile-repeated-roots"
    $ProfilePath = Join-Path $CaseRoot "project-profile.conf"
    $OutputPath = Join-Path $CaseRoot "written-profile.conf"
    New-Item -ItemType Directory -Path $CaseRoot -Force | Out-Null
    New-ValidProfile -Path $ProfilePath -ConfirmationStatus "pending" -Architecture "custom" -ProjectName "RepeatedRoots" -SecondSourceRoot "Assets/Shared"
    $ProfileLines = Read-Utf8WithoutBomLines -Path $ProfilePath
    $CrLf = [string][char]13 + [string][char]10
    $CrLfContent = [string]::Join($CrLf, $ProfileLines) + $CrLf
    [System.IO.File]::WriteAllText($ProfilePath, $CrLfContent, $script:Utf8WithoutBom)
    Assert-CrLfFile -Path $ProfilePath
    Import-ProfileApi

    $Profile = Read-HarnessProfile -ProfilePath $ProfilePath -SchemaPath $SchemaPath
    Assert-True -Condition (Test-HarnessProfile -Profile $Profile -SchemaPath $SchemaPath) -Message "프로필 검증이 실패했습니다."
    $Roots = [string]::Join([Environment]::NewLine, @($Profile["source_root"]))
    $ExpectedRoots = [string]::Join([Environment]::NewLine, @("Assets/_Game", "Assets/Shared"))
    Assert-Equal -Expected $ExpectedRoots -Actual $Roots -Message "반복 source_root 순서가 보존되지 않았습니다."
    Assert-Equal -Expected "custom" -Actual $Profile["architecture"] -Message "architecture 조회 결과가 다릅니다."

    Write-HarnessProfile -Profile $Profile -SchemaPath $SchemaPath -OutputPath $OutputPath
    Assert-FileExists -Path $OutputPath -Message "프로필 쓰기 결과가 없습니다."
    $WrittenRoots = @(Read-Utf8WithoutBomLines -Path $OutputPath | Where-Object { $_.StartsWith("source_root=") } | ForEach-Object { $_.Substring("source_root=".Length) })
    Assert-Equal -Expected $ExpectedRoots -Actual ([string]::Join([Environment]::NewLine, $WrittenRoots)) -Message "작성된 source_root 순서가 다릅니다."
}

function test_profile_rejects_unknown_key
{
    Import-ProfileApi
    $CaseRoot = Join-Path $TestTempRoot "profile-unknown-key"
    $ProfilePath = Join-Path $CaseRoot "project-profile.conf"
    New-Item -ItemType Directory -Path $CaseRoot -Force | Out-Null
    New-ValidProfile -Path $ProfilePath -ConfirmationStatus "pending" -Architecture "custom" -ProjectName "UnknownKey"
    $Lines = @(Read-Utf8WithoutBomLines -Path $ProfilePath) + "unknown_key=value"
    Write-Utf8WithoutBomLines -Path $ProfilePath -Lines $Lines

    $DidThrow = $false
    $Diagnostic = ""
    try
    {
        $Profile = Read-HarnessProfile -ProfilePath $ProfilePath -SchemaPath $SchemaPath
        Test-HarnessProfile -Profile $Profile -SchemaPath $SchemaPath | Out-Null
    }
    catch
    {
        $DidThrow = $true
        $Diagnostic = $_.Exception.Message
    }

    Assert-True -Condition $DidThrow -Message "알 수 없는 키가 거부되지 않았습니다."
    Assert-Contains -Actual $Diagnostic -ExpectedFragment "unknown_key" -Message "알 수 없는 키 진단이 없습니다."
}

function test_profile_rejects_invalid_enum
{
    Import-ProfileApi
    $CaseRoot = Join-Path $TestTempRoot "profile-invalid-enum"
    $ProfilePath = Join-Path $CaseRoot "project-profile.conf"
    New-Item -ItemType Directory -Path $CaseRoot -Force | Out-Null
    New-ValidProfile -Path $ProfilePath -ConfirmationStatus "pending" -Architecture "custom" -ProjectName "InvalidEnum"
    $Lines = @(Read-Utf8WithoutBomLines -Path $ProfilePath | ForEach-Object {
        if ($_.StartsWith("render_pipeline="))
        {
            "render_pipeline=invalid_pipeline"
        }
        else
        {
            $_
        }
    })
    Write-Utf8WithoutBomLines -Path $ProfilePath -Lines $Lines

    $DidThrow = $false
    $Diagnostic = ""
    try
    {
        $Profile = Read-HarnessProfile -ProfilePath $ProfilePath -SchemaPath $SchemaPath
        Test-HarnessProfile -Profile $Profile -SchemaPath $SchemaPath | Out-Null
    }
    catch
    {
        $DidThrow = $true
        $Diagnostic = $_.Exception.Message
    }

    Assert-True -Condition $DidThrow -Message "잘못된 열거형이 거부되지 않았습니다."
    Assert-Contains -Actual $Diagnostic -ExpectedFragment "invalid_pipeline" -Message "잘못된 열거형 진단이 없습니다."
}

function test_profile_does_not_execute_values
{
    Import-ProfileApi
    $CaseRoot = Join-Path $TestTempRoot "profile-command-value"
    $ProfilePath = Join-Path $CaseRoot "project-profile.conf"
    $OutputPath = Join-Path $CaseRoot "written-profile.conf"
    $MarkerPath = Join-Path $CaseRoot "profile-value-executed"
    New-Item -ItemType Directory -Path $CaseRoot -Force | Out-Null
    $EscapedMarkerPath = $MarkerPath.Replace("'", "''")
    $Payload = '$(New-Item -ItemType File -Path ''' + $EscapedMarkerPath + ''' -Force)'
    New-ValidProfile -Path $ProfilePath -ConfirmationStatus "pending" -Architecture "custom" -ProjectName $Payload

    $Profile = Read-HarnessProfile -ProfilePath $ProfilePath -SchemaPath $SchemaPath
    Assert-True -Condition (Test-HarnessProfile -Profile $Profile -SchemaPath $SchemaPath) -Message "명령 문자열 프로필 검증이 실패했습니다."
    Assert-Equal -Expected $Payload -Actual $Profile["project_name"] -Message "프로필 값이 문자열 그대로 보존되지 않았습니다."
    Write-HarnessProfile -Profile $Profile -SchemaPath $SchemaPath -OutputPath $OutputPath
    Assert-FileExists -Path $OutputPath -Message "명령 문자열 프로필 출력이 없습니다."
    Assert-Contains -Actual ([string]::Join([Environment]::NewLine, (Read-Utf8WithoutBomLines -Path $OutputPath))) -ExpectedFragment "project_name=$Payload" -Message "명령 문자열이 출력 파일에 보존되지 않았습니다."
    Assert-FileNotExists -Path $MarkerPath -Message "프로필 값이 New-Item 명령으로 실행되었습니다."
}

function test_detect_rejects_non_unity_directory
{
    Import-DetectionApi
    $CaseRoot = Join-Path $TestTempRoot "detect-not-unity"
    $ProjectRoot = Join-Path $CaseRoot "project"
    $OutputRoot = Join-Path $CaseRoot "output"
    $ProfilePath = Join-Path $OutputRoot "project-profile.conf"
    $ReportPath = Join-Path $OutputRoot "detection-report.md"
    New-Item -ItemType Directory -Path $ProjectRoot, $OutputRoot -Force | Out-Null
    Write-Utf8WithoutBomLines -Path (Join-Path $ProjectRoot "README.md") -Lines @("# Unity 프로젝트가 아닌 픽스처")

    $Result = Get-DetectionResult -ProjectRoot $ProjectRoot -ProfilePath $ProfilePath -ReportPath $ReportPath
    Assert-Equal -Expected 2 -Actual $Result.ExitCode -Message "비Unity 디렉터리 감지 종료 코드가 다릅니다."
    Assert-Contains -Actual ([string]$Result.Output) -ExpectedFragment "Unity 프로젝트" -Message "비Unity 디렉터리 진단이 없습니다."
    Assert-FileNotExists -Path $ProfilePath -Message "비Unity 디렉터리에 프로필이 생성되었습니다."
    Assert-FileNotExists -Path $ReportPath -Message "비Unity 디렉터리에 보고서가 생성되었습니다."

    $MissingRoot = Join-Path $CaseRoot "missing-project"
    $Result = Get-DetectionResult -ProjectRoot $MissingRoot -ProfilePath $ProfilePath -ReportPath $ReportPath
    Assert-ExitCode -Expected 2 -Result $Result -Message "없는 프로젝트 경로 감지 종료 코드가 다릅니다."
}

function test_detects_mvvm_vcontainer_unitask_urp
{
    Import-DetectionApi
    $CaseRoot = Join-Path $TestTempRoot "detect-mvvm"
    $ProjectRoot = Join-Path $CaseRoot "project"
    $OutputRoot = Join-Path $CaseRoot "output"
    $ProfilePath = Join-Path $OutputRoot "project-profile.conf"
    $ReportPath = Join-Path $OutputRoot "detection-report.md"
    New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null
    New-UnityFixture -ProjectRoot $ProjectRoot -FixtureKind "mvvm"

    $Result = Get-DetectionResult -ProjectRoot $ProjectRoot -ProfilePath $ProfilePath -ReportPath $ReportPath
    Assert-Equal -Expected 0 -Actual $Result.ExitCode -Message "MVVM 픽스처 감지 종료 코드가 다릅니다."
    Assert-FileExists -Path $ProfilePath -Message "감지 프로필이 없습니다."
    Assert-FileExists -Path $ReportPath -Message "감지 보고서가 없습니다."
    $Profile = Read-HarnessProfile -ProfilePath $ProfilePath -SchemaPath $SchemaPath
    Assert-Equal -Expected "mvvm" -Actual $Profile["architecture"] -Message "아키텍처 감지값이 다릅니다."
    Assert-Equal -Expected "vcontainer" -Actual $Profile["dependency_injection"] -Message "DI 감지값이 다릅니다."
    Assert-Equal -Expected "unitask" -Actual $Profile["async_backend"] -Message "비동기 감지값이 다릅니다."
    Assert-Equal -Expected "urp" -Actual $Profile["render_pipeline"] -Message "렌더 파이프라인 감지값이 다릅니다."
}

function test_detection_uses_assets_game_as_only_code_scope
{
    Import-DetectionApi
    $CaseRoot = Join-Path $TestTempRoot "detect-assets-game-scope"
    $ProjectRoot = Join-Path $CaseRoot "project"
    $OutputRoot = Join-Path $CaseRoot "output"
    $ProfilePath = Join-Path $OutputRoot "project-profile.conf"
    $ReportPath = Join-Path $OutputRoot "detection-report.md"
    $Directories = @(
        $OutputRoot
        (Join-Path $ProjectRoot "ProjectSettings")
        (Join-Path $ProjectRoot "Packages")
        (Join-Path $ProjectRoot "Assets/_Game/Runtime")
        (Join-Path $ProjectRoot "Assets/SomeVendor")
    )
    New-Item -ItemType Directory -Path $Directories -Force | Out-Null
    Write-Utf8WithoutBomLines -Path (Join-Path $ProjectRoot "ProjectSettings/ProjectVersion.txt") -Lines @("m_EditorVersion: 6000.3.16f1")
    Write-Utf8WithoutBomLines -Path (Join-Path $ProjectRoot "Packages/manifest.json") -Lines @('{"dependencies":{"com.svermeulen.extenject":"9.2.0"}}')
    Write-Utf8WithoutBomLines -Path (Join-Path $ProjectRoot "Assets/_Game/Runtime/OwnedCode.cs") -Lines @("public sealed class OwnedCode { }")
    Write-Utf8WithoutBomLines -Path (Join-Path $ProjectRoot "Assets/SomeVendor/VendorCode.cs") -Lines @("using Zenject; public sealed class VendorCode { }")

    $Result = Get-DetectionResult -ProjectRoot $ProjectRoot -ProfilePath $ProfilePath -ReportPath $ReportPath
    Assert-ExitCode -Expected 0 -Result $Result -Message "Assets/_Game 전용 감지 종료 코드가 다릅니다."
    $Profile = Read-HarnessProfile -ProfilePath $ProfilePath -SchemaPath $SchemaPath
    Assert-Equal -Expected 'Assets/_Game' -Actual ([string]::Join([Environment]::NewLine, @($Profile['source_root']))) -Message '감지 소스 루트'
    Assert-Equal -Expected 'unknown' -Actual ([string]$Profile['dependency_injection']) -Message '외부 에셋 DI 감지'
}

function test_detection_rejects_missing_assets_game
{
    Import-DetectionApi
    $CaseRoot = Join-Path $TestTempRoot "detect-missing-assets-game"
    $ProjectRoot = Join-Path $CaseRoot "project"
    $OutputRoot = Join-Path $CaseRoot "output"
    $ProfilePath = Join-Path $OutputRoot "project-profile.conf"
    $ReportPath = Join-Path $OutputRoot "detection-report.md"
    $Directories = @(
        $OutputRoot
        (Join-Path $ProjectRoot "ProjectSettings")
        (Join-Path $ProjectRoot "Packages")
        (Join-Path $ProjectRoot "Assets/Scripts")
    )
    New-Item -ItemType Directory -Path $Directories -Force | Out-Null
    Write-Utf8WithoutBomLines -Path (Join-Path $ProjectRoot "ProjectSettings/ProjectVersion.txt") -Lines @("m_EditorVersion: 6000.3.16f1")
    Write-Utf8WithoutBomLines -Path (Join-Path $ProjectRoot "Packages/manifest.json") -Lines @('{"dependencies":{}}')
    Write-Utf8WithoutBomLines -Path (Join-Path $ProjectRoot "Assets/Scripts/LegacyCode.cs") -Lines @("public sealed class LegacyCode { }")

    $Result = Get-DetectionResult -ProjectRoot $ProjectRoot -ProfilePath $ProfilePath -ReportPath $ReportPath
    Assert-ExitCode -Expected 4 -Result $Result -Message "Assets/_Game 누락 종료 코드가 다릅니다."
    Assert-FileNotExists -Path $ProfilePath -Message "Assets/_Game 없이 프로필이 생성되었습니다."
}

function test_architecture_conflict_falls_back_to_custom
{
    Import-DetectionApi
    $CaseRoot = Join-Path $TestTempRoot "detect-conflict"
    $ProjectRoot = Join-Path $CaseRoot "project"
    $OutputRoot = Join-Path $CaseRoot "output"
    $ProfilePath = Join-Path $OutputRoot "project-profile.conf"
    $ReportPath = Join-Path $OutputRoot "detection-report.md"
    New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null
    New-UnityFixture -ProjectRoot $ProjectRoot -FixtureKind "conflict"

    $Result = Get-DetectionResult -ProjectRoot $ProjectRoot -ProfilePath $ProfilePath -ReportPath $ReportPath
    Assert-Equal -Expected 0 -Actual $Result.ExitCode -Message "충돌 픽스처 감지 종료 코드가 다릅니다."
    $Profile = Read-HarnessProfile -ProfilePath $ProfilePath -SchemaPath $SchemaPath
    Assert-Equal -Expected "custom" -Actual $Profile["architecture"] -Message "충돌 시 custom 폴백이 적용되지 않았습니다."
    Assert-Contains -Actual ([string]::Join([Environment]::NewLine, (Read-Utf8WithoutBomLines -Path $ReportPath))) -ExpectedFragment "충돌" -Message "충돌 근거가 보고서에 없습니다."
}

function test_detection_matches_render_async_and_asmdef_boundaries
{
    Import-DetectionApi
    $CaseRoot = Join-Path $TestTempRoot "detect-parity-boundaries"

    $ProjectRoot = Join-Path $CaseRoot "custom-render/project"
    $ProfilePath = Join-Path $CaseRoot "custom-render/output/project-profile.conf"
    $ReportPath = Join-Path $CaseRoot "custom-render/output/detection-report.md"
    New-Item -ItemType Directory -Path (Split-Path -Parent $ProfilePath) -Force | Out-Null
    New-UnityFixture -ProjectRoot $ProjectRoot -FixtureKind "conflict"
    Write-Utf8WithoutBomLines -Path (Join-Path $ProjectRoot "ProjectSettings/GraphicsSettings.asset") -Lines @("m_CustomRenderPipeline: {fileID: 11400000, guid: custom}")
    $Result = Get-DetectionResult -ProjectRoot $ProjectRoot -ProfilePath $ProfilePath -ReportPath $ReportPath
    Assert-ExitCode -Expected 0 -Result $Result -Message "custom SRP 감지 종료 코드가 다릅니다."
    $Profile = Read-HarnessProfile -ProfilePath $ProfilePath -SchemaPath $SchemaPath
    Assert-Equal -Expected "unknown" -Actual $Profile["render_pipeline"] -Message "패키지 없는 custom SRP를 builtin으로 오인했습니다."

    $ProjectRoot = Join-Path $CaseRoot "mixed-async/project"
    $ProfilePath = Join-Path $CaseRoot "mixed-async/output/project-profile.conf"
    $ReportPath = Join-Path $CaseRoot "mixed-async/output/detection-report.md"
    New-Item -ItemType Directory -Path (Split-Path -Parent $ProfilePath) -Force | Out-Null
    New-UnityFixture -ProjectRoot $ProjectRoot -FixtureKind "mvvm"
    Write-Utf8WithoutBomLines -Path (Join-Path $ProjectRoot "Assets/_Game/Scripts/Models/MixedAsync.cs") -Lines @(
        "using Cysharp.Threading.Tasks;"
        "using System.Threading.Tasks;"
        "public sealed class MixedAsync { private UniTask m_first; private Task m_second; }"
    )
    $Result = Get-DetectionResult -ProjectRoot $ProjectRoot -ProfilePath $ProfilePath -ReportPath $ReportPath
    Assert-ExitCode -Expected 0 -Result $Result -Message "mixed async 감지 종료 코드가 다릅니다."
    $Profile = Read-HarnessProfile -ProfilePath $ProfilePath -SchemaPath $SchemaPath
    Assert-Equal -Expected "mixed" -Actual $Profile["async_backend"] -Message "복수 비동기 코드 근거가 mixed로 감지되지 않았습니다."

    $ProjectRoot = Join-Path $CaseRoot "asmdef-priority/project"
    $ProfilePath = Join-Path $CaseRoot "asmdef-priority/output/project-profile.conf"
    $ReportPath = Join-Path $CaseRoot "asmdef-priority/output/detection-report.md"
    New-Item -ItemType Directory -Path (Split-Path -Parent $ProfilePath), (Join-Path $ProjectRoot "ProjectSettings"), (Join-Path $ProjectRoot "Packages"), (Join-Path $ProjectRoot "Assets/_Game/Game/Runtime"), (Join-Path $ProjectRoot "Assets/Scripts") -Force | Out-Null
    Write-Utf8WithoutBomLines -Path (Join-Path $ProjectRoot "ProjectSettings/ProjectVersion.txt") -Lines @("m_EditorVersion: 6000.3.16f1")
    Write-Utf8WithoutBomLines -Path (Join-Path $ProjectRoot "ProjectSettings/GraphicsSettings.asset") -Lines @("m_CustomRenderPipeline: {fileID: 0}")
    Write-Utf8WithoutBomLines -Path (Join-Path $ProjectRoot "Packages/manifest.json") -Lines @('{ "dependencies": {} }')
    Write-Utf8WithoutBomLines -Path (Join-Path $ProjectRoot "Assets/_Game/Game/Game.asmdef") -Lines @('{ "name": "Game" }')
    Write-Utf8WithoutBomLines -Path (Join-Path $ProjectRoot "Assets/_Game/Game/Runtime/Game.cs") -Lines @("public sealed class Game { }")
    Write-Utf8WithoutBomLines -Path (Join-Path $ProjectRoot "Assets/Scripts/Legacy.cs") -Lines @("public sealed class Legacy { }")
    $Result = Get-DetectionResult -ProjectRoot $ProjectRoot -ProfilePath $ProfilePath -ReportPath $ReportPath
    Assert-ExitCode -Expected 0 -Result $Result -Message "asmdef 루트 감지 종료 코드가 다릅니다."
    $Profile = Read-HarnessProfile -ProfilePath $ProfilePath -SchemaPath $SchemaPath
    Assert-Equal -Expected "Assets/_Game" -Actual ([string]::Join([Environment]::NewLine, @($Profile["source_root"]))) -Message "감지 소스 루트가 Assets/_Game으로 고정되지 않았습니다."
}

function test_existing_confirmed_profile_is_not_overwritten
{
    Import-DetectionApi
    Assert-FileExists -Path $InitializerScript -Message "initialize-harness.ps1 파일을 찾을 수 없습니다."
    $CaseRoot = Join-Path $TestTempRoot "detect-confirmed-profile"
    $ProjectRoot = Join-Path $CaseRoot "project"
    $ConfigRoot = Join-Path $ProjectRoot ".agents/config"
    $ProfilePath = Join-Path $ConfigRoot "project-profile.conf"
    New-UnityFixture -ProjectRoot $ProjectRoot -FixtureKind "mvvm"
    New-Item -ItemType Directory -Path $ConfigRoot -Force | Out-Null
    New-ValidProfile -Path $ProfilePath -ConfirmationStatus "confirmed" -Architecture "custom" -ProjectName "ConfirmedProfile"
    $BeforeHash = (Get-FileHash -LiteralPath $ProfilePath -Algorithm SHA256).Hash

    $Result = Invoke-ChildPowerShell -ScriptPath $InitializerScript -Arguments @("-ProjectRoot", $ProjectRoot)
    $AfterHash = (Get-FileHash -LiteralPath $ProfilePath -Algorithm SHA256).Hash
    Assert-Equal -Expected 0 -Actual $Result.ExitCode -Message "확정 프로필 보호 종료 코드가 다릅니다."
    Assert-Contains -Actual $Result.Output -ExpectedFragment "확정" -Message "확정 프로필 보호 안내가 없습니다."
    Assert-Equal -Expected $BeforeHash -Actual $AfterHash -Message "확정 프로필이 덮어써졌습니다."
    Assert-FileNotExists -Path (Join-Path $ConfigRoot "project-profile.candidate.conf") -Message "승인 없는 후보 프로필이 생성되었습니다."
}

function test_packages_lock_dependencies_are_merged_and_validated
{
    Import-DetectionApi
    $CaseRoot = Join-Path $TestTempRoot "detect-packages-lock"
    $ProjectRoot = Join-Path $CaseRoot "merged/project"
    $ProfilePath = Join-Path $CaseRoot "merged/output/project-profile.conf"
    $ReportPath = Join-Path $CaseRoot "merged/output/detection-report.md"
    New-Item -ItemType Directory -Path (Split-Path -Parent $ProfilePath) -Force | Out-Null
    New-UnityFixture -ProjectRoot $ProjectRoot -FixtureKind "conflict"
    Write-Utf8WithoutBomLines -Path (Join-Path $ProjectRoot "Packages/packages-lock.json") -Lines @(
        '{ "dependencies": {'
        '  "com.unity.render-pipelines.universal": { "version": "17.0.3" },'
        '  "jp.hadashikick.vcontainer": { "version": "1.16.8" }'
        '} }'
    )
    Write-Utf8WithoutBomLines -Path (Join-Path $ProjectRoot "Assets/_Game/Scripts/LockUsage.cs") -Lines @(
        "using VContainer;"
        "public sealed class LockUsage { private IObjectResolver m_resolver; }"
    )

    $Result = Get-DetectionResult -ProjectRoot $ProjectRoot -ProfilePath $ProfilePath -ReportPath $ReportPath
    Assert-ExitCode -Expected 0 -Result $Result -Message "packages-lock 병합 종료 코드가 다릅니다."
    $Profile = Read-HarnessProfile -ProfilePath $ProfilePath -SchemaPath $SchemaPath
    Assert-Equal -Expected "urp" -Actual $Profile["render_pipeline"] -Message "packages-lock 렌더 패키지가 병합되지 않았습니다."
    Assert-Equal -Expected "vcontainer" -Actual $Profile["dependency_injection"] -Message "packages-lock DI와 코드 근거가 결합되지 않았습니다."
    $Report = [string]::Join([Environment]::NewLine, (Read-Utf8WithoutBomLines -Path $ReportPath))
    Assert-Contains -Actual $Report -ExpectedFragment "Packages/packages-lock.json" -Message "보고서에 packages-lock 근거가 없습니다."

    $ProjectRoot = Join-Path $CaseRoot "installed-only/project"
    $ProfilePath = Join-Path $CaseRoot "installed-only/output/project-profile.conf"
    $ReportPath = Join-Path $CaseRoot "installed-only/output/detection-report.md"
    New-Item -ItemType Directory -Path (Split-Path -Parent $ProfilePath) -Force | Out-Null
    New-UnityFixture -ProjectRoot $ProjectRoot -FixtureKind "conflict"
    Write-Utf8WithoutBomLines -Path (Join-Path $ProjectRoot "Packages/manifest.json") -Lines @(
        '{ "dependencies": {'
        '  "jp.hadashikick.vcontainer": "1.16.8"'
        '} }'
    )
    Write-Utf8WithoutBomLines -Path (Join-Path $ProjectRoot "Packages/packages-lock.json") -Lines @(
        '{ "dependencies": {'
        '  "jp.hadashikick.vcontainer": { "version": "1.16.8" },'
        '  "com.cysharp.unitask": { "version": "2.5.10" },'
        '  "com.demigiant.dotween": { "version": "1.2.765" }'
        '} }'
    )
    $Result = Get-DetectionResult -ProjectRoot $ProjectRoot -ProfilePath $ProfilePath -ReportPath $ReportPath
    Assert-ExitCode -Expected 0 -Result $Result -Message "설치 전용 패키지 감지 종료 코드가 다릅니다."
    $Profile = Read-HarnessProfile -ProfilePath $ProfilePath -SchemaPath $SchemaPath
    Assert-Equal -Expected "unknown" -Actual $Profile["dependency_injection"] -Message "DI 패키지 설치만으로 실제 사용을 확정했습니다."
    Assert-Equal -Expected "unknown" -Actual $Profile["async_backend"] -Message "비동기 패키지 설치만으로 실제 사용을 확정했습니다."
    Assert-Equal -Expected "unknown" -Actual $Profile["tween_backend"] -Message "트윈 패키지 설치만으로 실제 사용을 확정했습니다."
    $Report = [string]::Join([Environment]::NewLine, (Read-Utf8WithoutBomLines -Path $ReportPath))
    foreach ($Evidence in @(
        "VContainer 패키지 설치만 확인, 코드 사용 미확정"
        "UniTask 패키지 설치만 확인, 코드 사용 미확정"
        "DOTween 패키지 설치만 확인, 코드 사용 미확정"
    ))
    {
        Assert-Contains -Actual $Report -ExpectedFragment $Evidence -Message "설치 전용 패키지 근거가 보고서에 없습니다."
    }
    $VContainerEvidence = "VContainer 패키지 설치만 확인, 코드 사용 미확정"
    Assert-Equal -Expected 1 -Actual ([regex]::Matches($Report, [regex]::Escape($VContainerEvidence)).Count) -Message "manifest와 packages-lock의 중복 패키지가 단일 근거로 병합되지 않았습니다."

    $ProjectRoot = Join-Path $CaseRoot "render-conflict/project"
    $ProfilePath = Join-Path $CaseRoot "render-conflict/output/project-profile.conf"
    $ReportPath = Join-Path $CaseRoot "render-conflict/output/detection-report.md"
    New-Item -ItemType Directory -Path (Split-Path -Parent $ProfilePath) -Force | Out-Null
    New-UnityFixture -ProjectRoot $ProjectRoot -FixtureKind "conflict"
    Write-Utf8WithoutBomLines -Path (Join-Path $ProjectRoot "Packages/manifest.json") -Lines @(
        '{ "dependencies": {'
        '  "com.unity.render-pipelines.universal": "17.0.3"'
        '} }'
    )
    Write-Utf8WithoutBomLines -Path (Join-Path $ProjectRoot "Packages/packages-lock.json") -Lines @(
        '{ "dependencies": {'
        '  "com.unity.render-pipelines.high-definition": { "version": "17.0.3" }'
        '} }'
    )
    $Result = Get-DetectionResult -ProjectRoot $ProjectRoot -ProfilePath $ProfilePath -ReportPath $ReportPath
    Assert-ExitCode -Expected 0 -Result $Result -Message "manifest/lock 렌더 패키지 충돌 감지 종료 코드가 다릅니다."
    $Profile = Read-HarnessProfile -ProfilePath $ProfilePath -SchemaPath $SchemaPath
    Assert-Equal -Expected "custom" -Actual $Profile["render_pipeline"] -Message "manifest URP와 packages-lock HDRP 충돌이 custom으로 병합되지 않았습니다."

    $ProjectRoot = Join-Path $CaseRoot "malformed/project"
    $ProfilePath = Join-Path $CaseRoot "malformed/output/project-profile.conf"
    $ReportPath = Join-Path $CaseRoot "malformed/output/detection-report.md"
    New-Item -ItemType Directory -Path (Split-Path -Parent $ProfilePath) -Force | Out-Null
    New-UnityFixture -ProjectRoot $ProjectRoot -FixtureKind "conflict"
    Write-Utf8WithoutBomLines -Path (Join-Path $ProjectRoot "Packages/packages-lock.json") -Lines @('{"dependencies":{"broken":}}')
    $Result = Get-DetectionResult -ProjectRoot $ProjectRoot -ProfilePath $ProfilePath -ReportPath $ReportPath
    Assert-ExitCode -Expected 4 -Result $Result -Message "손상된 packages-lock 종료 코드가 다릅니다."
    Assert-FileNotExists -Path $ProfilePath -Message "손상된 packages-lock에서 프로필이 생성되었습니다."
    Assert-FileNotExists -Path $ReportPath -Message "손상된 packages-lock에서 보고서가 생성되었습니다."

    foreach ($InvalidCase in @(
        [PSCustomObject]@{ Name = "manifest-array"; File = "manifest.json"; Json = '{ "dependencies": [] }' },
        [PSCustomObject]@{ Name = "lock-missing"; File = "packages-lock.json"; Json = '{ "metadata": {} }' },
        [PSCustomObject]@{ Name = "lock-array"; File = "packages-lock.json"; Json = '{ "dependencies": [] }' }
    ))
    {
        $ProjectRoot = Join-Path $CaseRoot ($InvalidCase.Name + "/project")
        $ProfilePath = Join-Path $CaseRoot ($InvalidCase.Name + "/output/project-profile.conf")
        $ReportPath = Join-Path $CaseRoot ($InvalidCase.Name + "/output/detection-report.md")
        New-Item -ItemType Directory -Path (Split-Path -Parent $ProfilePath) -Force | Out-Null
        New-UnityFixture -ProjectRoot $ProjectRoot -FixtureKind "conflict"
        Write-Utf8WithoutBomLines -Path (Join-Path $ProjectRoot ("Packages/" + $InvalidCase.File)) -Lines @([string]$InvalidCase.Json)
        $Result = Get-DetectionResult -ProjectRoot $ProjectRoot -ProfilePath $ProfilePath -ReportPath $ReportPath
        Assert-ExitCode -Expected 4 -Result $Result -Message "dependencies 형식 오류가 내부 오류로 처리되지 않았습니다: $($InvalidCase.Name)"
        Assert-Contains -Actual ([string]$Result.Output) -ExpectedFragment ([string]$InvalidCase.File) -Message "진단이 실제 오류 파일명을 가리키지 않습니다."
    }

    $ProjectRoot = Join-Path $CaseRoot "locked/project"
    $ProfilePath = Join-Path $CaseRoot "locked/output/project-profile.conf"
    $ReportPath = Join-Path $CaseRoot "locked/output/detection-report.md"
    New-Item -ItemType Directory -Path (Split-Path -Parent $ProfilePath) -Force | Out-Null
    New-UnityFixture -ProjectRoot $ProjectRoot -FixtureKind "conflict"
    $LockPath = Join-Path $ProjectRoot "Packages/packages-lock.json"
    Write-Utf8WithoutBomLines -Path $LockPath -Lines @('{ "dependencies": {} }')
    $ExclusiveStream = [System.IO.File]::Open($LockPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
    try
    {
        $Result = Get-DetectionResult -ProjectRoot $ProjectRoot -ProfilePath $ProfilePath -ReportPath $ReportPath
    }
    finally
    {
        $ExclusiveStream.Dispose()
    }
    Assert-ExitCode -Expected 4 -Result $Result -Message "잠긴 packages-lock 읽기 실패가 내부 오류로 처리되지 않았습니다."
    Assert-Contains -Actual ([string]$Result.Output) -ExpectedFragment "packages-lock.json" -Message "잠긴 파일 진단에 실제 파일명이 없습니다."
}

function test_detection_matches_bash_optimization_matrix
{
    Import-DetectionApi
    $Cases = @(
        [PSCustomObject]@{ Version = "6000.3.16f1"; Pipeline = "urp"; Grd = "applicable"; Occlusion = "unknown"; Stp = "applicable"; Mesh = "unknown" },
        [PSCustomObject]@{ Version = "6000.3.16f1"; Pipeline = "hdrp"; Grd = "applicable"; Occlusion = "unknown"; Stp = "not_applicable"; Mesh = "unknown" },
        [PSCustomObject]@{ Version = "6000.1.9f1"; Pipeline = "urp"; Grd = "applicable"; Occlusion = "unknown"; Stp = "applicable"; Mesh = "not_applicable" },
        [PSCustomObject]@{ Version = "2022.3.62f1"; Pipeline = "urp"; Grd = "not_applicable"; Occlusion = "not_applicable"; Stp = "not_applicable"; Mesh = "not_applicable" },
        [PSCustomObject]@{ Version = "6000.3.16f1"; Pipeline = "builtin"; Grd = "not_applicable"; Occlusion = "not_applicable"; Stp = "not_applicable"; Mesh = "not_applicable" },
        [PSCustomObject]@{ Version = "6000.3.16f1"; Pipeline = "custom"; Grd = "unknown"; Occlusion = "unknown"; Stp = "unknown"; Mesh = "unknown" },
        [PSCustomObject]@{ Version = "6000.3.16f1"; Pipeline = "unknown"; Grd = "unknown"; Occlusion = "unknown"; Stp = "unknown"; Mesh = "unknown" }
    )

    foreach ($Case in $Cases)
    {
        $States = Get-HarnessOptimizationStates -UnityVersion $Case.Version -RenderPipeline $Case.Pipeline
        Assert-Equal -Expected $Case.Grd -Actual $States.GpuResidentDrawer -Message "GPU Resident Drawer Bash 동등성이 다릅니다: $($Case.Version)/$($Case.Pipeline)"
        Assert-Equal -Expected $Case.Occlusion -Actual $States.GpuOcclusionCulling -Message "GPU Occlusion Culling Bash 동등성이 다릅니다: $($Case.Version)/$($Case.Pipeline)"
        Assert-Equal -Expected $Case.Stp -Actual $States.Stp -Message "STP Bash 동등성이 다릅니다: $($Case.Version)/$($Case.Pipeline)"
        Assert-Equal -Expected $Case.Mesh -Actual $States.MeshLod -Message "Mesh LOD Bash 동등성이 다릅니다: $($Case.Version)/$($Case.Pipeline)"
    }
}

function test_initializer_confirm_and_redetect_contracts
{
    Import-ProfileApi
    Assert-FileExists -Path $InitializerScript -Message "initialize-harness.ps1 파일을 찾을 수 없습니다."
    $CaseRoot = Join-Path $TestTempRoot "initializer-contracts"

    $ProjectRoot = Join-Path $CaseRoot "confirm/project"
    $ProfilePath = Join-Path $ProjectRoot ".agents/config/project-profile.conf"
    New-UnityFixture -ProjectRoot $ProjectRoot -FixtureKind "mvvm"
    New-Item -ItemType Directory -Path (Split-Path -Parent $ProfilePath) -Force | Out-Null
    New-ValidProfile -Path $ProfilePath -ConfirmationStatus "pending" -Architecture "mvvm" -ProjectName "ConfirmProject"
    $Result = Invoke-ChildPowerShell -ScriptPath $InitializerScript -Arguments @("-ProjectRoot", $ProjectRoot, "-Confirm")
    Assert-ExitCode -Expected 0 -Result $Result -Message "프로필 확정 종료 코드가 다릅니다."
    $Profile = Read-HarnessProfile -ProfilePath $ProfilePath -SchemaPath $SchemaPath
    Assert-Equal -Expected "confirmed" -Actual $Profile["confirmation_status"] -Message "프로필이 confirmed로 전환되지 않았습니다."

    $ProjectRoot = Join-Path $CaseRoot "confirm-failure/project"
    New-UnityFixture -ProjectRoot $ProjectRoot -FixtureKind "mvvm"
    $Result = Invoke-ChildPowerShell -ScriptPath $InitializerScript -Arguments @("-ProjectRoot", $ProjectRoot, "-Confirm")
    Assert-ExitCode -Expected 3 -Result $Result -Message "확정할 프로필 누락 종료 코드가 다릅니다."

    $ProjectRoot = Join-Path $CaseRoot "redetect/project"
    $ProfilePath = Join-Path $ProjectRoot ".agents/config/project-profile.conf"
    $CandidatePath = Join-Path $ProjectRoot ".agents/config/project-profile.candidate.conf"
    $ReportPath = Join-Path $ProjectRoot ".agents/reports/detection-report.md"
    New-UnityFixture -ProjectRoot $ProjectRoot -FixtureKind "mvvm"
    New-Item -ItemType Directory -Path (Split-Path -Parent $ProfilePath) -Force | Out-Null
    New-ValidProfile -Path $ProfilePath -ConfirmationStatus "confirmed" -Architecture "custom" -ProjectName "ExistingConfirmed"
    $BeforeHash = (Get-FileHash -LiteralPath $ProfilePath -Algorithm SHA256).Hash
    $Result = Invoke-ChildPowerShell -ScriptPath $InitializerScript -Arguments @("-ProjectRoot", $ProjectRoot, "-Redetect")
    Assert-ExitCode -Expected 0 -Result $Result -Message "재감지 종료 코드가 다릅니다."
    Assert-FileExists -Path $CandidatePath -Message "재감지 후보 프로필이 없습니다."
    Assert-FileExists -Path $ReportPath -Message "재감지 보고서가 없습니다."
    Assert-Equal -Expected $BeforeHash -Actual ((Get-FileHash -LiteralPath $ProfilePath -Algorithm SHA256).Hash) -Message "재감지가 기존 확정 프로필을 변경했습니다."
    $ReportLines = Read-Utf8WithoutBomLines -Path $ReportPath
    $Report = [string]::Join([Environment]::NewLine, $ReportLines)
    Assert-Contains -Actual $Report -ExpectedFragment "기존 프로필 비교" -Message "재감지 보고서에 기존 프로필 비교가 없습니다."
    Assert-Equal -Expected 7 -Actual @($ReportLines | Where-Object { $_.StartsWith("#") }).Count -Message "재감지 보고서에 추가 헤딩이 생성되었습니다."
}

function test_entrypoints_preserve_explicit_error_exit_codes
{
    $CheckHarnessScript = Join-Path $AgentsRoot "scripts/lint/check-harness.ps1"
    $PreCommitScript = Join-Path $AgentsRoot "scripts/ci/pre-commit-checks.ps1"
    $CaseRoot = Join-Path $TestTempRoot "entrypoint-exits"
    $NonUnityRoot = Join-Path $CaseRoot "non-unity"
    New-Item -ItemType Directory -Path $NonUnityRoot -Force | Out-Null

    $Result = Invoke-ChildPowerShell -ScriptPath $InitializerScript -Arguments @("-ProjectRoot", $NonUnityRoot, "-Confirm", "-Redetect")
    Assert-ExitCode -Expected 3 -Result $Result -Message "초기화 인자 오류 종료 코드가 다릅니다."
    $Result = Invoke-ChildPowerShell -ScriptPath $InitializerScript -Arguments @("-ProjectRoot", $NonUnityRoot)
    Assert-ExitCode -Expected 2 -Result $Result -Message "비Unity 초기화 종료 코드가 다릅니다."
    $Result = Invoke-ChildPowerShell -ScriptPath $CheckHarnessScript -Arguments @("-ProjectRoot", $NonUnityRoot, "-Profile", (Join-Path $CaseRoot "missing.conf"), "-Format", "machine")
    Assert-ExitCode -Expected 3 -Result $Result -Message "린트 프로필 오류 종료 코드가 다릅니다."
    $Result = Invoke-ChildPowerShell -ScriptPath $PreCommitScript -Arguments @("-ProjectRoot", $NonUnityRoot, "-Profile", (Join-Path $CaseRoot "missing.conf"), "-Format", "machine")
    Assert-ExitCode -Expected 3 -Result $Result -Message "CI 진입점이 린트 종료 코드를 전파하지 않았습니다."

    $Result = Invoke-ChildPowerShell -ScriptPath $CheckHarnessScript -Arguments @("-ProjectRoot", $NonUnityRoot, "-Format", "invalid")
    Assert-ExitCode -Expected 3 -Result $Result -Message "린트 출력 형식 오류 종료 코드가 다릅니다."
    $Result = Invoke-ChildPowerShell -ScriptPath $PreCommitScript -Arguments @("-ProjectRoot", $NonUnityRoot, "-Format", "invalid")
    Assert-ExitCode -Expected 3 -Result $Result -Message "CI 출력 형식 오류 종료 코드가 다릅니다."

    $OutputFailureProject = Join-Path $CaseRoot "output-failure/project"
    New-UnityFixture -ProjectRoot $OutputFailureProject -FixtureKind "mvvm"
    Write-Utf8WithoutBomLines -Path (Join-Path $OutputFailureProject ".agents") -Lines @("not a directory")
    $Result = Invoke-ChildPowerShell -ScriptPath $InitializerScript -Arguments @("-ProjectRoot", $OutputFailureProject)
    Assert-ExitCode -Expected 2 -Result $Result -Message "초기화 출력 경로 오류 종료 코드가 다릅니다."

    $IsolatedAgentsRoot = Join-Path $CaseRoot "isolated/.agents"
    $IsolatedInitializer = Join-Path $IsolatedAgentsRoot "scripts/init/initialize-harness.ps1"
    $IsolatedCheck = Join-Path $IsolatedAgentsRoot "scripts/lint/check-harness.ps1"
    $IsolatedPreCommit = Join-Path $IsolatedAgentsRoot "scripts/ci/pre-commit-checks.ps1"
    New-Item -ItemType Directory -Path (Split-Path -Parent $IsolatedInitializer), (Split-Path -Parent $IsolatedCheck), (Split-Path -Parent $IsolatedPreCommit) -Force | Out-Null
    [System.IO.File]::Copy($InitializerScript, $IsolatedInitializer)
    [System.IO.File]::Copy($CheckHarnessScript, $IsolatedCheck)
    [System.IO.File]::Copy($PreCommitScript, $IsolatedPreCommit)
    Assert-ExitCode -Expected 4 -Result (Invoke-ChildPowerShell -ScriptPath $IsolatedInitializer -Arguments @()) -Message "초기화 내부 파일 누락 종료 코드가 다릅니다."
    Assert-ExitCode -Expected 4 -Result (Invoke-ChildPowerShell -ScriptPath $IsolatedCheck -Arguments @()) -Message "린트 내부 파일 누락 종료 코드가 다릅니다."
    Assert-ExitCode -Expected 4 -Result (Invoke-ChildPowerShell -ScriptPath $IsolatedPreCommit -Arguments @()) -Message "CI 내부 파일 누락 종료 코드가 다릅니다."
}

function Invoke-LintScenario
{
    param(
        [string]$ConfirmationStatus,
        [string]$Architecture,
        [int]$ExpectedExitCode,
        [string]$ExpectedFragment,
        [string]$ForbiddenFragment,
        [string]$CaseName
    )

    Import-LintApi
    $CaseRoot = Join-Path $TestTempRoot $CaseName
    $ProjectRoot = Join-Path $CaseRoot "project"
    $ProfilePath = Join-Path $CaseRoot "project-profile.conf"
    New-Item -ItemType Directory -Path $CaseRoot -Force | Out-Null
    New-LintFixture -ProjectRoot $ProjectRoot
    New-ValidProfile -Path $ProfilePath -ConfirmationStatus $ConfirmationStatus -Architecture $Architecture -ProjectName "LintFixture"

    $Result = Invoke-HarnessLint -ProjectRoot $ProjectRoot -ProfilePath $ProfilePath -SchemaPath $SchemaPath
    $Output = [string]::Join([Environment]::NewLine, @($Result.Output))
    Assert-Equal -Expected $ExpectedExitCode -Actual $Result.ExitCode -Message "린터 종료 코드가 다릅니다."
    if (-not [string]::IsNullOrEmpty($ExpectedFragment))
    {
        Assert-Contains -Actual $Output -ExpectedFragment $ExpectedFragment -Message "필수 린터 결과가 없습니다."
    }
    if (-not [string]::IsNullOrEmpty($ForbiddenFragment))
    {
        Assert-NotContains -Actual $Output -UnexpectedFragment $ForbiddenFragment -Message "비활성 규칙이 실행되었습니다."
    }
}

function test_pending_profile_downgrades_profile_violation_to_warning
{
    Invoke-LintScenario -ConfirmationStatus "pending" -Architecture "mvvm" -ExpectedExitCode 0 -ExpectedFragment "MVVM001|warning|" -ForbiddenFragment "MVVM001|error|" -CaseName "lint-pending"
}

function test_confirmed_profile_blocks_profile_violation
{
    Invoke-LintScenario -ConfirmationStatus "confirmed" -Architecture "mvvm" -ExpectedExitCode 1 -ExpectedFragment "MVVM001|error|" -ForbiddenFragment "" -CaseName "lint-confirmed"
}

function test_custom_profile_skips_architecture_specific_rules
{
    Invoke-LintScenario -ConfirmationStatus "confirmed" -Architecture "custom" -ExpectedExitCode 0 -ExpectedFragment "" -ForbiddenFragment "MVVM001|" -CaseName "lint-custom"
}

function test_korean_and_space_path_is_supported
{
    Import-DetectionApi
    $CaseRoot = Join-Path $TestTempRoot "한글 및 공백 경로"
    $ProjectRoot = Join-Path $CaseRoot "한글 프로젝트"
    $OutputRoot = Join-Path $CaseRoot "출력 폴더"
    $ProfilePath = Join-Path $OutputRoot "project-profile.conf"
    $ReportPath = Join-Path $OutputRoot "detection-report.md"
    New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null
    New-UnityFixture -ProjectRoot $ProjectRoot -FixtureKind "mvvm"

    $Result = Get-DetectionResult -ProjectRoot $ProjectRoot -ProfilePath $ProfilePath -ReportPath $ReportPath
    Assert-Equal -Expected 0 -Actual $Result.ExitCode -Message "한글·공백 경로 감지 종료 코드가 다릅니다."
    Assert-FileExists -Path $ProfilePath -Message "한글·공백 경로의 프로필이 없습니다."
    Assert-FileExists -Path $ReportPath -Message "한글·공백 경로의 보고서가 없습니다."
    $Profile = Read-HarnessProfile -ProfilePath $ProfilePath -SchemaPath $SchemaPath
    Assert-Equal -Expected "한글 프로젝트" -Actual $Profile["project_name"] -Message "한글 프로젝트명이 보존되지 않았습니다."
}

function test_detection_does_not_modify_project_files
{
    Import-DetectionApi
    $CaseRoot = Join-Path $TestTempRoot "detect-readonly"
    $ProjectRoot = Join-Path $CaseRoot "project"
    $OutputRoot = Join-Path $CaseRoot "output"
    $ProfilePath = Join-Path $OutputRoot "project-profile.conf"
    $ReportPath = Join-Path $OutputRoot "detection-report.md"
    $BackupFilePath = Join-Path $ProjectRoot ".agents-backup/keep.txt"
    New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null
    New-UnityFixture -ProjectRoot $ProjectRoot -FixtureKind "mvvm"
    New-Item -ItemType Directory -Path (Split-Path -Parent $BackupFilePath) -Force | Out-Null
    Write-Utf8WithoutBomLines -Path $BackupFilePath -Lines @("감지 중 보존해야 하는 파일")
    $BeforeSnapshot = Get-ProjectSnapshot -ProjectRoot $ProjectRoot
    $BackupRelativePath = ".agents-backup" + [System.IO.Path]::DirectorySeparatorChar + "keep.txt|"
    Assert-Contains -Actual $BeforeSnapshot -ExpectedFragment $BackupRelativePath -Message ".agents-backup 파일이 스냅샷에서 잘못 제외되었습니다."

    $Result = Get-DetectionResult -ProjectRoot $ProjectRoot -ProfilePath $ProfilePath -ReportPath $ReportPath
    $AfterSnapshot = Get-ProjectSnapshot -ProjectRoot $ProjectRoot
    Assert-Equal -Expected 0 -Actual $Result.ExitCode -Message "읽기 전용 감지 종료 코드가 다릅니다."
    Assert-Equal -Expected $BeforeSnapshot -Actual $AfterSnapshot -Message "감지 과정에서 .agents 외부 프로젝트 파일이 변경되었습니다."
    Assert-FileExists -Path $ProfilePath -Message "읽기 전용 감지 프로필이 없습니다."
    Assert-FileExists -Path $ReportPath -Message "읽기 전용 감지 보고서가 없습니다."
}

function test_detection_report_has_required_headings
{
    Import-DetectionApi
    $CaseRoot = Join-Path $TestTempRoot "detect-report-headings"
    $ProjectRoot = Join-Path $CaseRoot "project"
    $ProfilePath = Join-Path $CaseRoot "output/project-profile.conf"
    $ReportPath = Join-Path $CaseRoot "output/detection-report.md"
    New-Item -ItemType Directory -Path (Split-Path -Parent $ProfilePath) -Force | Out-Null
    New-UnityFixture -ProjectRoot $ProjectRoot -FixtureKind "mvvm"

    $Result = Get-DetectionResult -ProjectRoot $ProjectRoot -ProfilePath $ProfilePath -ReportPath $ReportPath
    Assert-ExitCode -Expected 0 -Result $Result -Message "보고서 생성 종료 코드가 다릅니다."
    $Report = [string]::Join([Environment]::NewLine, (Read-Utf8WithoutBomLines -Path $ReportPath))
    $Headings = @(
        "# Unity 하네스 감지 보고서"
        "## 요약"
        "## 감지 근거와 신뢰도"
        "## 소스 및 테스트 루트"
        "## 조건부 최적화 적용 가능성"
        "## 충돌 및 미확정 항목"
        "## 사용자 확인 절차"
    )
    foreach ($Heading in $Headings)
    {
        Assert-Contains -Actual $Report -ExpectedFragment $Heading -Message "필수 보고서 헤딩이 없습니다."
    }
    $ActualHeadings = @(Read-Utf8WithoutBomLines -Path $ReportPath | Where-Object { $_.StartsWith("#") })
    Assert-Equal -Expected 7 -Actual $ActualHeadings.Count -Message "보고서 헤딩 개수가 다릅니다."
}

function test_detection_rolls_back_profile_when_report_fails
{
    Import-DetectionApi
    $CaseRoot = Join-Path $TestTempRoot "detect-output-rollback"
    $ProjectRoot = Join-Path $CaseRoot "project"
    $OutputRoot = Join-Path $CaseRoot "output"
    $ProfilePath = Join-Path $OutputRoot "project-profile.conf"
    $ReportPath = Join-Path $OutputRoot "detection-report.md"
    New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null
    New-UnityFixture -ProjectRoot $ProjectRoot -FixtureKind "mvvm"
    New-ValidProfile -Path $ProfilePath -ConfirmationStatus "pending" -Architecture "custom" -ProjectName "ExistingProfile"
    Write-Utf8WithoutBomLines -Path $ReportPath -Lines @("existing report")
    $BeforeHash = (Get-FileHash -LiteralPath $ProfilePath -Algorithm SHA256).Hash
    $BeforeReportHash = (Get-FileHash -LiteralPath $ReportPath -Algorithm SHA256).Hash

    $script:HarnessDetectionReportWriter = {
        param([string]$InjectedReportPath, [System.Collections.IDictionary]$InjectedContext)
        [System.IO.File]::WriteAllText($InjectedReportPath, "partially committed report", $script:Utf8WithoutBom)
        throw "injected report commit failure"
    }
    try
    {
        $Result = Get-DetectionResult -ProjectRoot $ProjectRoot -ProfilePath $ProfilePath -ReportPath $ReportPath
    }
    finally
    {
        $script:HarnessDetectionReportWriter = $null
    }
    $AfterHash = (Get-FileHash -LiteralPath $ProfilePath -Algorithm SHA256).Hash
    Assert-ExitCode -Expected 2 -Result $Result -Message "보고서 실패 종료 코드가 다릅니다."
    Assert-Equal -Expected $BeforeHash -Actual $AfterHash -Message "보고서 실패 후 기존 프로필이 복구되지 않았습니다."
    Assert-Equal -Expected $BeforeReportHash -Actual ((Get-FileHash -LiteralPath $ReportPath -Algorithm SHA256).Hash) -Message "보고서 실패 후 기존 보고서가 변경되었습니다."
}

function test_lint_machine_output_escapes_fields
{
    Import-LintApi
    $CaseRoot = Join-Path $TestTempRoot "lint-machine-escape"
    $ProjectRoot = Join-Path $CaseRoot "project"
    $ProfilePath = Join-Path $CaseRoot "project-profile.conf"
    $SourcePath = Join-Path $ProjectRoot "Assets/_Game"
    New-Item -ItemType Directory -Path $SourcePath -Force | Out-Null
    New-ValidProfile -Path $ProfilePath -ConfirmationStatus "confirmed" -Architecture "custom" -ProjectName "LintEscape"
    Write-Utf8WithoutBomLines -Path (Join-Path $SourcePath "Pipe%Name.cs") -Lines @(
        "public sealed class PipeName"
        "{"
        "    private int badName;"
        "}"
    )

    $Result = Invoke-HarnessLint -ProjectRoot $ProjectRoot -ProfilePath $ProfilePath -SchemaPath $SchemaPath
    $Output = [string]::Join([Environment]::NewLine, @($Result.Output))
    Assert-Contains -Actual $Output -ExpectedFragment "%25" -Message "기계 출력의 % 이스케이프가 없습니다."
    Assert-NotContains -Actual $Output -UnexpectedFragment "Pipe%Name.cs" -Message "기계 출력에 이스케이프되지 않은 경로가 있습니다."
}

function test_lint_rejects_source_root_outside_assets_game
{
    Import-LintApi
    $CaseRoot = Join-Path $TestTempRoot "lint-source-outside-assets-game"
    $ProjectRoot = Join-Path $CaseRoot "project"
    $ProfilePath = Join-Path $CaseRoot "project-profile.conf"
    $OutsideProfilePath = Join-Path $CaseRoot "outside-profile.conf"
    $VendorPath = Join-Path $ProjectRoot "Assets/Vendor"
    New-Item -ItemType Directory -Path $VendorPath -Force | Out-Null
    Write-Utf8WithoutBomLines -Path (Join-Path $VendorPath "VendorCode.cs") -Lines @("public sealed class VendorCode { }")
    New-ValidProfile -Path $ProfilePath -ConfirmationStatus "confirmed" -Architecture "layered_clean" -ProjectName "LintOutside"
    $ProfileLines = @(Read-Utf8WithoutBomLines -Path $ProfilePath | ForEach-Object {
        if ($_.StartsWith("source_root=")) { "source_root=Assets/Vendor" } else { $_ }
    })
    Write-Utf8WithoutBomLines -Path $OutsideProfilePath -Lines $ProfileLines

    $Result = Invoke-HarnessLint -ProjectRoot $ProjectRoot -ProfilePath $OutsideProfilePath -SchemaPath $SchemaPath
    $Output = [string]::Join([Environment]::NewLine, @($Result.Output))
    Assert-ExitCode -Expected 1 -Result $Result -Message "Assets/_Game 외부 source_root 종료 코드가 다릅니다."
    Assert-Contains -Actual $Output -ExpectedFragment "CONFIG001|error|Assets/Vendor|0|" -Message "Assets/_Game 외부 source_root 진단이 없습니다."
}

function test_lint_merges_defaults_and_routes_core_technology_rules
{
    Import-LintApi
    $CaseRoot = Join-Path $TestTempRoot "lint-defaults-routing"
    $ProjectRoot = Join-Path $CaseRoot "project"
    $ProfilePath = Join-Path $CaseRoot "project-profile.conf"
    $SourcePath = Join-Path $ProjectRoot "Assets/_Game/Views"
    $PluginPath = Join-Path $ProjectRoot "Assets/Plugins/Foreign"
    New-Item -ItemType Directory -Path $SourcePath, $PluginPath -Force | Out-Null
    New-ValidProfile -Path $ProfilePath -ConfirmationStatus "confirmed" -Architecture "mvvm" -ProjectName "LintRouting"
    $ProfileLines = @(Read-Utf8WithoutBomLines -Path $ProfilePath | ForEach-Object {
        if ($_.StartsWith("source_root=")) { "source_root=Assets/_Game" }
        elseif ($_.StartsWith("exclude_root=")) { $null }
        else { $_ }
    } | Where-Object { $null -ne $_ })
    Write-Utf8WithoutBomLines -Path $ProfilePath -Lines $ProfileLines
    Write-Utf8WithoutBomLines -Path (Join-Path $PluginPath "Ignored.cs") -Lines @(
        "public sealed class Ignored { public static Ignored Instance; private int badName; }"
    )
    Write-Utf8WithoutBomLines -Path (Join-Path $SourcePath "RoutingView.cs") -Lines @(
        "using UnityEngine;"
        "using Sample.Models;"
        "public sealed class RoutingView"
        "{"
        "    public static RoutingView Instance;"
        "    [SerializeField] private RoutingView m_view;"
        "    private GameObject m_object = other?.gameObject;"
        "    private void Update() { var values = source.ToList(); var item = new object(); transform.DOMoveX(1, 1); }"
        "    private void Configure(IContainerBuilder builder) { builder.RegisterInstance(m_view); }"
        "    private void StartWork() { StartCoroutine(Run()); }"
        "}"
    )

    $Result = Invoke-HarnessLint -ProjectRoot $ProjectRoot -ProfilePath $ProfilePath -SchemaPath $SchemaPath
    $Output = [string]::Join([Environment]::NewLine, @($Result.Output))
    Assert-ExitCode -Expected 1 -Result $Result -Message "핵심/기술 규칙 위반 종료 코드가 다릅니다."
    foreach ($RuleId in @("SOLID001", "PERF001", "PERF002", "UNITYNULL001", "MVVM001", "VCONTAINER001", "UNITASK001", "DOTWEEN001"))
    {
        Assert-Contains -Actual $Output -ExpectedFragment ($RuleId + "|") -Message "핵심/기술 린트 규칙이 라우팅되지 않았습니다."
    }
    Assert-NotContains -Actual $Output -UnexpectedFragment "Assets/Plugins" -Message "기본 제외 루트가 프로필 제외 누락 시 활성화되지 않았습니다."
}

function test_lint_io_failure_is_internal_exit_four
{
    Import-LintApi
    $CaseRoot = Join-Path $TestTempRoot "lint-io-failure"
    $ProjectRoot = Join-Path $CaseRoot "project"
    $ProfilePath = Join-Path $CaseRoot "project-profile.conf"
    $SourcePath = Join-Path $ProjectRoot "Assets/_Game"
    $UnreadablePath = Join-Path $SourcePath "Unreadable.cs"
    New-Item -ItemType Directory -Path $SourcePath -Force | Out-Null
    New-ValidProfile -Path $ProfilePath -ConfirmationStatus "confirmed" -Architecture "custom" -ProjectName "LintIoFailure"
    Write-Utf8WithoutBomLines -Path $UnreadablePath -Lines @("public sealed class Unreadable { }")
    $script:HarnessLintFileReader = {
        param([string]$InjectedPath)
        throw "injected C# read failure"
    }
    try
    {
        $Result = Invoke-HarnessLint -ProjectRoot $ProjectRoot -ProfilePath $ProfilePath -SchemaPath $SchemaPath
    }
    finally
    {
        $script:HarnessLintFileReader = $null
    }
    Assert-ExitCode -Expected 4 -Result $Result -Message "C# 읽기/I/O 실패가 내부 오류 4로 분류되지 않았습니다."
}

function test_profile_confirmed_is_noop_and_cleanup_failure_is_best_effort
{
    Import-ProfileApi
    $CaseRoot = Join-Path $TestTempRoot "profile-commit-semantics"
    $ProfilePath = Join-Path $CaseRoot "project-profile.conf"
    New-Item -ItemType Directory -Path $CaseRoot -Force | Out-Null
    New-ValidProfile -Path $ProfilePath -ConfirmationStatus "confirmed" -Architecture "custom" -ProjectName "AlreadyConfirmed"
    $BeforeWriteTime = [System.IO.File]::GetLastWriteTimeUtc($ProfilePath).Ticks
    Start-Sleep -Milliseconds 1100
    [void](Confirm-HarnessProfile -ProfilePath $ProfilePath -SchemaPath $SchemaPath)
    Assert-Equal -Expected $BeforeWriteTime -Actual ([System.IO.File]::GetLastWriteTimeUtc($ProfilePath).Ticks) -Message "이미 confirmed인 프로필을 다시 기록했습니다."

    $Profile = Read-HarnessProfile -ProfilePath $ProfilePath -SchemaPath $SchemaPath
    $Profile["project_name"] = "CommittedDespiteCleanupFailure"
    $script:HarnessProfileCleanupAction = {
        param([string]$InjectedBackupPath)
        throw "injected backup cleanup failure"
    }
    try
    {
        Write-HarnessProfile -Profile $Profile -SchemaPath $SchemaPath -OutputPath $ProfilePath
    }
    finally
    {
        $script:HarnessProfileCleanupAction = $null
    }
    $CommittedProfile = Read-HarnessProfile -ProfilePath $ProfilePath -SchemaPath $SchemaPath
    Assert-Equal -Expected "CommittedDespiteCleanupFailure" -Actual $CommittedProfile["project_name"] -Message "커밋 후 백업 정리 실패가 성공한 교체를 실패로 되돌렸습니다."
}

function test_reparse_paths_are_physicalized_and_entries_not_traversed
{
    Import-LintApi
    $CaseRoot = Join-Path $TestTempRoot "reparse-boundaries"
    $ProjectRoot = Join-Path $CaseRoot "project"
    $ProfilePath = Join-Path $CaseRoot "project-profile.conf"
    $SourcePath = Join-Path $ProjectRoot "Assets/_Game"
    $ExternalPath = Join-Path $CaseRoot "external"
    $LinkedPath = Join-Path $SourcePath "Linked"
    New-Item -ItemType Directory -Path $SourcePath, $ExternalPath -Force | Out-Null
    New-ValidProfile -Path $ProfilePath -ConfirmationStatus "confirmed" -Architecture "custom" -ProjectName "ReparseBoundary"
    Write-Utf8WithoutBomLines -Path (Join-Path $SourcePath "Safe.cs") -Lines @("public sealed class Safe { }")
    Write-Utf8WithoutBomLines -Path (Join-Path $ExternalPath "Outside.cs") -Lines @("public sealed class Outside { public static Outside Instance; }")
    try
    {
        New-Item -ItemType SymbolicLink -Path $LinkedPath -Target $ExternalPath -ErrorAction Stop | Out-Null
    }
    catch
    {
        Skip-CurrentTest -Reason "심볼릭 링크 또는 정션을 생성할 권한이 없습니다."
    }

    $Result = Invoke-HarnessLint -ProjectRoot $ProjectRoot -ProfilePath $ProfilePath -SchemaPath $SchemaPath
    $Output = [string]::Join([Environment]::NewLine, @($Result.Output))
    Assert-NotContains -Actual $Output -UnexpectedFragment "Outside.cs" -Message "린트 순회가 재파싱 디렉터리 안으로 진입했습니다."

    $Profile = Read-HarnessProfile -ProfilePath $ProfilePath -SchemaPath $SchemaPath
    $PhysicalizedOutputPath = Join-Path $LinkedPath "written.conf"
    Write-HarnessProfile -Profile $Profile -SchemaPath $SchemaPath -OutputPath $PhysicalizedOutputPath
    Assert-FileExists -Path (Join-Path $ExternalPath "written.conf") -Message "재파싱 조상을 물리 경로로 해석하지 못했습니다."

    $LinkedFilePath = Join-Path $SourcePath "linked-profile.conf"
    New-Item -ItemType SymbolicLink -Path $LinkedFilePath -Target (Join-Path $ExternalPath "written.conf") -ErrorAction Stop | Out-Null
    $DidThrow = $false
    try
    {
        Write-HarnessProfile -Profile $Profile -SchemaPath $SchemaPath -OutputPath $LinkedFilePath
    }
    catch
    {
        $DidThrow = $true
    }
    Assert-True -Condition $DidThrow -Message "출력 대상 엔트리 자체의 재파싱 지점을 허용했습니다."

    $PhysicalCaseRoot = Get-HarnessProfileCanonicalPath -Path $CaseRoot
    $TempAliasRoot = if ($PhysicalCaseRoot.StartsWith("/private/var/", [System.StringComparison]::Ordinal)) {
        "/var/" + $PhysicalCaseRoot.Substring("/private/var/".Length)
    } else {
        $CaseRoot
    }
    $TempAliasOutputPath = Join-Path $TempAliasRoot "temp-alias-profile.conf"
    Write-HarnessProfile -Profile $Profile -SchemaPath $SchemaPath -OutputPath $TempAliasOutputPath
    Assert-FileExists -Path $TempAliasOutputPath -Message "물리 임시 디렉터리 별칭 아래 프로필 쓰기가 실패했습니다."
}

function test_detection_rejects_non_object_manifest_roots
{
    Import-DetectionApi
    foreach ($Case in @(
        [PSCustomObject]@{ Name = "array"; Json = '[{"dependencies":{}}]' },
        [PSCustomObject]@{ Name = "string"; Json = '"dependencies"' }
    ))
    {
        $CaseRoot = Join-Path $TestTempRoot ("manifest-root-" + $Case.Name)
        $ProjectRoot = Join-Path $CaseRoot "project"
        $ProfilePath = Join-Path $CaseRoot "output/project-profile.conf"
        $ReportPath = Join-Path $CaseRoot "output/detection-report.md"
        New-Item -ItemType Directory -Path (Split-Path -Parent $ProfilePath) -Force | Out-Null
        New-UnityFixture -ProjectRoot $ProjectRoot -FixtureKind "mvvm"
        Write-Utf8WithoutBomLines -Path (Join-Path $ProjectRoot "Packages/manifest.json") -Lines @([string]$Case.Json)

        $Result = Get-DetectionResult -ProjectRoot $ProjectRoot -ProfilePath $ProfilePath -ReportPath $ReportPath
        Assert-ExitCode -Expected 4 -Result $Result -Message "JSON 객체가 아닌 manifest 최상위 값이 내부 오류로 거부되지 않았습니다: $($Case.Name)"
        Assert-FileNotExists -Path $ProfilePath -Message "잘못된 manifest에서 프로필이 생성되었습니다."
    }
}

function test_detection_lexically_sanitizes_interpolation_and_format_boundaries
{
    Import-DetectionApi
    $Cases = @(
        [PSCustomObject]@{
            Name = "standard-positive"
            FileName = "StandardInterpolation.cs"
            Expected = "unitask"
            Lines = @('public sealed class Probe { public string Value => $"{Use(new Cysharp.Threading.Tasks.UniTask())}"; }')
        },
        [PSCustomObject]@{
            Name = "raw-positive"
            FileName = "RawInterpolation.cs"
            Expected = "unitask"
            Lines = @('public sealed class Probe { public string Value => $"""{Use(global::Cysharp.Threading.Tasks.UniTask.CompletedTask)}"""; }')
        },
        [PSCustomObject]@{
            Name = "format-negative"
            FileName = "FormatOnly.cs"
            Expected = "unknown"
            Lines = @('public sealed class Probe { public string Value => $"{value:Cysharp.Threading.Tasks.UniTask}"; }')
        },
        [PSCustomObject]@{
            Name = "literal-negative"
            FileName = "LiteralOnly.cs"
            Expected = "unknown"
            Lines = @(
                '// VContainer Cysharp.Threading.Tasks.UniTask DG.Tweening.DOTween'
                'public sealed class Probe {'
                '    private const string Names = "VContainer Cysharp.Threading.Tasks.UniTask DG.Tweening.DOTween";'
                '    private const string RawNames = """VContainer Cysharp.Threading.Tasks.UniTask DG.Tweening.DOTween""";'
                '}'
            )
        },
        [PSCustomObject]@{
            Name = "path-negative"
            FileName = "VContainer_UniTask_DOTween.cs"
            Expected = "unknown"
            Lines = @('public sealed class NeutralPathProbe { }')
        }
    )

    foreach ($Case in $Cases)
    {
        $CaseRoot = Join-Path $TestTempRoot ("detect-lexical-" + $Case.Name)
        $ProjectRoot = Join-Path $CaseRoot "project"
        $ProfilePath = Join-Path $CaseRoot "output/project-profile.conf"
        $ReportPath = Join-Path $CaseRoot "output/detection-report.md"
        New-Item -ItemType Directory -Path (Split-Path -Parent $ProfilePath) -Force | Out-Null
        New-UnityFixture -ProjectRoot $ProjectRoot -FixtureKind "conflict"
        Write-Utf8WithoutBomLines -Path (Join-Path $ProjectRoot ("Assets/_Game/" + $Case.FileName)) -Lines @($Case.Lines)

        $Result = Get-DetectionResult -ProjectRoot $ProjectRoot -ProfilePath $ProfilePath -ReportPath $ReportPath
        Assert-ExitCode -Expected 0 -Result $Result -Message "lexical 감지 픽스처가 실패했습니다: $($Case.Name)"
        $Profile = Read-HarnessProfile -ProfilePath $ProfilePath -SchemaPath $SchemaPath
        Assert-Equal -Expected $Case.Expected -Actual $Profile["async_backend"] -Message "보간식·문자열·format 경계 감지가 다릅니다: $($Case.Name)"
        if ($Case.Expected -eq "unknown")
        {
            Assert-Equal -Expected "unknown" -Actual $Profile["dependency_injection"] -Message "문자열 또는 경로를 DI 근거로 오인했습니다: $($Case.Name)"
            Assert-Equal -Expected "unknown" -Actual $Profile["tween_backend"] -Message "문자열 또는 경로를 트윈 근거로 오인했습니다: $($Case.Name)"
        }
    }
}

function test_lint_sanitizes_noise_and_limits_hot_loop_rules_to_update_ranges
{
    Import-LintApi
    $CaseRoot = Join-Path $TestTempRoot "lint-sanitized-update-ranges"
    $ProjectRoot = Join-Path $CaseRoot "project"
    $ProfilePath = Join-Path $CaseRoot "project-profile.conf"
    $SourcePath = Join-Path $ProjectRoot "Assets/_Game/Views"
    New-Item -ItemType Directory -Path $SourcePath -Force | Out-Null
    New-ValidProfile -Path $ProfilePath -ConfirmationStatus "confirmed" -Architecture "mvvm" -ProjectName "LintSanitizer"
    Write-Utf8WithoutBomLines -Path (Join-Path $SourcePath "HarmlessView.cs") -Lines @(
        "using System.Linq;"
        "namespace Sample.Views"
        "{"
        "    public sealed class HarmlessView"
        "    {"
        "        // public static HarmlessView Instance; InventoryModel source.ToList() new object() transform.DOMoveX(1, 1);"
        '        private const string m_noise = "public static HarmlessView Instance InventoryModel source.ToList() new object() transform.DOMoveX(1, 1)";'
        "        private void Helper() { var copy = source.ToList(); var item = new object(); transform.DOMoveX(1, 1); }"
        '        private void Update() { var text = $"{source.Where(value => value != null).Count()}"; }'
        "    }"
        "}"
    )

    $Result = Invoke-HarnessLint -ProjectRoot $ProjectRoot -ProfilePath $ProfilePath -SchemaPath $SchemaPath
    $Output = [string]::Join([Environment]::NewLine, @($Result.Output))
    $PerfDiagnostics = @($Result.Output | Where-Object { $_.StartsWith("PERF001|") })
    Assert-Equal -Expected 1 -Actual $PerfDiagnostics.Count -Message "보간식 Update LINQ를 놓쳤거나 helper LINQ를 중복 감지했습니다."
    Assert-Contains -Actual ([string]$PerfDiagnostics[0]) -ExpectedFragment "|9|" -Message "Update 보간식의 실제 줄 번호를 보고하지 않았습니다."
    foreach ($ForbiddenRule in @("SOLID001|", "PERF002|", "MVVM001|", "DOTWEEN001|"))
    {
        Assert-NotContains -Actual $Output -UnexpectedFragment $ForbiddenRule -Message "주석·문자열·helper 메서드를 규칙 위반으로 오인했습니다."
    }
}

function test_lint_supports_update_modifiers_expression_bodies_and_new_forms
{
    Import-LintApi
    $CaseRoot = Join-Path $TestTempRoot "lint-update-forms"
    $ProjectRoot = Join-Path $CaseRoot "project"
    $ProfilePath = Join-Path $CaseRoot "project-profile.conf"
    $SourcePath = Join-Path $ProjectRoot "Assets/_Game"
    New-Item -ItemType Directory -Path $SourcePath -Force | Out-Null
    New-ValidProfile -Path $ProfilePath -ConfirmationStatus "confirmed" -Architecture "custom" -ProjectName "UpdateForms"
    $ProfileLines = @(Read-Utf8WithoutBomLines -Path $ProfilePath | ForEach-Object {
        if ($_.StartsWith("dependency_injection=")) { "dependency_injection=unknown" }
        elseif ($_.StartsWith("async_backend=")) { "async_backend=unknown" }
        elseif ($_.StartsWith("xml_documentation_policy=")) { "xml_documentation_policy=disabled" }
        else { $_ }
    })
    Write-Utf8WithoutBomLines -Path $ProfilePath -Lines $ProfileLines
    Write-Utf8WithoutBomLines -Path (Join-Path $SourcePath "AsyncUpdateProbe.cs") -Lines @(
        "using System.Linq;"
        "public sealed class AsyncUpdateProbe"
        "{"
        "    private async void Update() { var values = m_values.Distinct(); }"
        "}"
    )
    Write-Utf8WithoutBomLines -Path (Join-Path $SourcePath "VirtualLateUpdateProbe.cs") -Lines @(
        "public class VirtualLateUpdateProbe"
        "{"
        "    protected virtual void LateUpdate() { object value = new(); }"
        "}"
    )
    Write-Utf8WithoutBomLines -Path (Join-Path $SourcePath "FixedUpdateProbe.cs") -Lines @(
        "using System.Linq;"
        "public sealed class FixedUpdateProbe"
        "{"
        "    private void FixedUpdate() { object value = new(); var values = m_values.Distinct(); }"
        "}"
    )
    Write-Utf8WithoutBomLines -Path (Join-Path $SourcePath "ExpressionUpdateProbe.cs") -Lines @(
        "public sealed class ExpressionUpdateProbe"
        "{"
        "    private void Update() => DG.Tweening.DOTween.Sequence();"
        "}"
    )

    $Result = Invoke-HarnessLint -ProjectRoot $ProjectRoot -ProfilePath $ProfilePath -SchemaPath $SchemaPath
    $PerfOne = @($Result.Output | Where-Object { $_.StartsWith("PERF001|warning|") })
    $PerfTwo = @($Result.Output | Where-Object { $_.StartsWith("PERF002|warning|") })
    $Tween = @($Result.Output | Where-Object { $_.StartsWith("DOTWEEN001|warning|") })
    Assert-ExitCode -Expected 0 -Result $Result -Message "Update 복합 선언 경고 종료 코드가 다릅니다."
    Assert-Equal -Expected 2 -Actual $PerfOne.Count -Message "Distinct 감지 건수가 다릅니다."
    Assert-Equal -Expected 2 -Actual $PerfTwo.Count -Message "target-typed new() 감지 건수가 다릅니다."
    Assert-Equal -Expected 1 -Actual $Tween.Count -Message "expression-bodied Update Tween 감지 건수가 다릅니다."
}

function test_lint_all_methods_recognizes_implicit_and_generic_methods
{
    Import-LintApi
    $CaseRoot = Join-Path $TestTempRoot "lint-all-methods"
    $ProjectRoot = Join-Path $CaseRoot "project"
    $ProfilePath = Join-Path $CaseRoot "project-profile.conf"
    $SourcePath = Join-Path $ProjectRoot "Assets/_Game"
    New-Item -ItemType Directory -Path $SourcePath -Force | Out-Null
    New-ValidProfile -Path $ProfilePath -ConfirmationStatus "confirmed" -Architecture "custom" -ProjectName "AllMethods"
    Write-Utf8WithoutBomLines -Path (Join-Path $SourcePath "DocumentationProbe.cs") -Lines @(
        "public sealed class DocumentationProbe"
        "{"
        "    void Awake() { }"
        "    private T Convert<T>(T value) { return value; }"
        "}"
    )

    $Result = Invoke-HarnessLint -ProjectRoot $ProjectRoot -ProfilePath $ProfilePath -SchemaPath $SchemaPath
    $DocumentationDiagnostics = @($Result.Output | Where-Object { $_.StartsWith("DOC001|warning|") })
    $Output = [string]::Join([Environment]::NewLine, @($Result.Output))
    Assert-ExitCode -Expected 0 -Result $Result -Message "all_methods 문서화 경고 종료 코드가 다릅니다."
    Assert-Equal -Expected 2 -Actual $DocumentationDiagnostics.Count -Message "암시적 void와 제네릭 메서드 문서화 진단 건수가 다릅니다."
    Assert-Contains -Actual $Output -ExpectedFragment "DocumentationProbe.cs|3|" -Message "void Awake() 문서화 위반을 누락했습니다."
    Assert-Contains -Actual $Output -ExpectedFragment "DocumentationProbe.cs|4|" -Message "Convert<T> 문서화 위반을 누락했습니다."
}

function test_lint_matches_bash_linq_and_value_type_allocation_contracts
{
    Import-LintApi
    $CaseRoot = Join-Path $TestTempRoot "lint-bash-perf-parity"
    $ProjectRoot = Join-Path $CaseRoot "project"
    $ProfilePath = Join-Path $CaseRoot "project-profile.conf"
    $SourcePath = Join-Path $ProjectRoot "Assets/_Game"
    New-Item -ItemType Directory -Path $SourcePath -Force | Out-Null
    New-ValidProfile -Path $ProfilePath -ConfirmationStatus "confirmed" -Architecture "custom" -ProjectName "BashPerfParity"
    $ProfileLines = @(Read-Utf8WithoutBomLines -Path $ProfilePath | ForEach-Object {
        if ($_.StartsWith("dependency_injection=")) { "dependency_injection=unknown" }
        elseif ($_.StartsWith("async_backend=")) { "async_backend=unknown" }
        elseif ($_.StartsWith("tween_backend=")) { "tween_backend=unknown" }
        elseif ($_.StartsWith("xml_documentation_policy=")) { "xml_documentation_policy=disabled" }
        else { $_ }
    })
    Write-Utf8WithoutBomLines -Path $ProfilePath -Lines $ProfileLines

    $LinqExpressions = [ordered]@{
        SelectMany = "source.SelectMany(value => value.Items)"
        OrderByDescending = "source.OrderByDescending(value => value.Score)"
        ThenBy = "source.ThenBy(value => value.Name)"
        GroupBy = "source.GroupBy(value => value.Kind)"
        Any = "source.Any()"
        All = "source.All(value => value != null)"
        First = "source.First()"
        Single = "source.Single()"
        Count = "source.Count()"
        Enumerable = "System.Linq.Enumerable.Empty<int>()"
    }
    foreach ($Operator in $LinqExpressions.Keys)
    {
        Write-Utf8WithoutBomLines -Path (Join-Path $SourcePath ("Linq" + $Operator + ".cs")) -Lines @(
            ("public sealed class Linq" + $Operator)
            "{"
            ("    private void Update() { var result = " + $LinqExpressions[$Operator] + "; }")
            "}"
        )
    }
    Write-Utf8WithoutBomLines -Path (Join-Path $SourcePath "AggregateNegative.cs") -Lines @(
        "public sealed class AggregateNegative"
        "{"
        "    private void Update() { var result = source.Aggregate(0, (sum, value) => sum + value); }"
        "}"
    )
    Write-Utf8WithoutBomLines -Path (Join-Path $SourcePath "UnityValueTypes.cs") -Lines @(
        "public sealed class UnityValueTypes"
        "{"
        "    private void Update()"
        "    {"
        "        var a = new Vector2(); var b = new Vector3(); var c = new Vector4();"
        "        var d = new Quaternion(); var e = new Color(); var f = new Color32();"
        "        var g = new Rect(); var h = new Bounds(); var i = new Ray();"
        "        var j = new Plane(); var k = new Matrix4x4();"
        "    }"
        "}"
    )
    Write-Utf8WithoutBomLines -Path (Join-Path $SourcePath "TargetTypedAllocation.cs") -Lines @(
        "public sealed class TargetTypedAllocation { private void Update() { object value = new(); } }"
    )
    Write-Utf8WithoutBomLines -Path (Join-Path $SourcePath "ReferenceAllocation.cs") -Lines @(
        "public sealed class ReferenceAllocation { private void Update() { var value = new object(); } }"
    )

    $Result = Invoke-HarnessLint -ProjectRoot $ProjectRoot -ProfilePath $ProfilePath -SchemaPath $SchemaPath
    $PerfOne = @($Result.Output | Where-Object { $_.StartsWith("PERF001|warning|") })
    $PerfTwo = @($Result.Output | Where-Object { $_.StartsWith("PERF002|warning|") })
    $Output = [string]::Join([Environment]::NewLine, @($Result.Output))
    Assert-ExitCode -Expected 0 -Result $Result -Message "Bash 성능 규칙 parity 종료 코드가 다릅니다."
    Assert-Equal -Expected 10 -Actual $PerfOne.Count -Message "대표 LINQ operator 및 Enumerable 감지 건수가 다릅니다."
    Assert-Equal -Expected 2 -Actual $PerfTwo.Count -Message "참조/target-typed 할당 감지 건수가 다릅니다."
    Assert-NotContains -Actual $Output -UnexpectedFragment "AggregateNegative.cs" -Message "Bash 목록 밖 Aggregate를 LINQ 규칙으로 오인했습니다."
    Assert-NotContains -Actual $Output -UnexpectedFragment "UnityValueTypes.cs" -Message "Unity 값 타입 생성을 참조 타입 할당으로 오인했습니다."
}

function Write-ToolingCodexConfig
{
    param(
        [string]$Path,
        [string]$KarpathyState,
        [string]$SuperpowersState,
        [string]$UnderstandState,
        [string]$Marketplace = "test-marketplace"
    )

    $Lines = New-Object 'System.Collections.Generic.List[string]'
    $Definitions = @(
        @("andrej-karpathy-skills", $KarpathyState),
        @("superpowers", $SuperpowersState),
        @("understand-anything", $UnderstandState)
    )
    foreach ($Definition in $Definitions)
    {
        if ($Definition[1] -eq "absent")
        {
            continue
        }
        [void]$Lines.Add("[plugins.`"$($Definition[0])@$Marketplace`"]")
        [void]$Lines.Add("enabled = $($Definition[1])")
    }
    New-Item -ItemType Directory -Path (Split-Path -Parent $Path) -Force | Out-Null
    Write-Utf8WithoutBomLines -Path $Path -Lines $Lines
}

function New-ToolingCacheSkill
{
    param(
        [string]$CodexHome,
        [string]$PluginId,
        [string]$Version,
        [string]$SkillName,
        [string]$Marketplace = "test-marketplace"
    )

    $SkillPath = Join-Path $CodexHome "plugins/cache/$Marketplace/$PluginId/$Version/skills/$SkillName/SKILL.md"
    New-Item -ItemType Directory -Path (Split-Path -Parent $SkillPath) -Force | Out-Null
    Write-Utf8WithoutBomLines -Path $SkillPath -Lines @("name: $SkillName")
}

function New-ToolingStandaloneSkill
{
    param(
        [string]$CodexHome,
        [string]$SkillName
    )

    $SkillPath = Join-Path $CodexHome "skills/$SkillName/SKILL.md"
    New-Item -ItemType Directory -Path (Split-Path -Parent $SkillPath) -Force | Out-Null
    Write-Utf8WithoutBomLines -Path $SkillPath -Lines @("name: $SkillName")
}

function New-ToolingDirectoryLink
{
    param(
        [string]$Path,
        [string]$Target
    )

    New-Item -ItemType Directory -Path (Split-Path -Parent $Path) -Force | Out-Null
    $LinkType = if ($env:OS -eq "Windows_NT") { "Junction" } else { "SymbolicLink" }
    New-Item -ItemType $LinkType -Path $Path -Target $Target | Out-Null
}

function Assert-ToolingInstalledOutputOrder
{
    param([string]$Output)

    $ActualLines = @($Output -split "`r?`n" | Where-Object { $_ -match '^(karpathy_guidelines|superpowers|understand_anything)\|' })
    $ExpectedLines = @(
        "karpathy_guidelines|installed"
        "superpowers|installed"
        "understand_anything|installed"
    )
    Assert-Equal -Expected ([string]::Join([Environment]::NewLine, $ExpectedLines)) -Actual ([string]::Join([Environment]::NewLine, $ActualLines)) -Message "도구 상태 출력 순서가 다릅니다."
}

function New-ToolingCodexStub
{
    param([string]$BinRoot)

    New-Item -ItemType Directory -Path $BinRoot -Force | Out-Null
    Write-Utf8WithoutBomLines -Path (Join-Path $BinRoot "codex.cmd") -Lines @("@echo off", "exit /b 0")
    $UnixStub = Join-Path $BinRoot "codex"
    Write-Utf8WithoutBomLines -Path $UnixStub -Lines @("#!/bin/sh", "exit 0")
    if ($null -ne (Get-Command -Name chmod -ErrorAction SilentlyContinue))
    {
        & chmod +x $UnixStub
    }
}

function New-ToolingInstallStubs
{
    param([string]$BinRoot)

    New-Item -ItemType Directory -Path $BinRoot -Force | Out-Null
    Write-Utf8WithoutBomLines -Path (Join-Path $BinRoot "python3.cmd") -Lines @(
        '@echo off', 'echo python3^|%*>>"%TOOLING_CALL_LOG%"',
        'if "%TOOLING_FAIL%"=="python3" exit /b 9',
        'mkdir "%CODEX_HOME%\skills\karpathy-guidelines" 2>nul',
        'echo name: karpathy-guidelines>"%CODEX_HOME%\skills\karpathy-guidelines\SKILL.md"', 'exit /b 0'
    )
    $PythonUnix = Join-Path $BinRoot "python3"
    Write-Utf8WithoutBomLines -Path $PythonUnix -Lines @(
        '#!/bin/sh', 'printf "python3|%s\n" "$*" >> "$TOOLING_CALL_LOG"',
        '[ "$TOOLING_FAIL" = python3 ] && exit 9',
        'mkdir -p "$CODEX_HOME/skills/karpathy-guidelines"',
        'printf "%s\n" "name: karpathy-guidelines" > "$CODEX_HOME/skills/karpathy-guidelines/SKILL.md"', 'exit 0'
    )
    Write-Utf8WithoutBomLines -Path (Join-Path $BinRoot "git.cmd") -Lines @(
        '@echo off', 'echo git^|%*>>"%TOOLING_CALL_LOG%"',
        'mkdir "%~3" 2>nul', 'if "%TOOLING_FAIL%"=="git" exit /b 13',
        'echo %~2|findstr /c:"obra/superpowers" >nul && (',
        '  if "%TOOLING_FAIL%"=="git-superpowers" exit /b 13',
        '  mkdir "%~3\skills\using-superpowers" 2>nul',
        '  echo name: using-superpowers>"%~3\skills\using-superpowers\SKILL.md"',
        '  exit /b 0',
        ')',
        'if "%TOOLING_FAIL%"=="git-understand" (echo %~2|findstr /c:"Understand-Anything" >nul && exit /b 13)',
        'mkdir "%~3\understand-anything-plugin\skills\understand" 2>nul',
        'echo name: understand>"%~3\understand-anything-plugin\skills\understand\SKILL.md"',
        'echo Add-Content -LiteralPath $env:TOOLING_CALL_LOG -Value "understand-installer^|codex">"%~3\install.ps1"',
        'echo $source = Join-Path $env:HOME ".understand-anything/repo/understand-anything-plugin/skills/understand">>"%~3\install.ps1"',
        'echo $link = Join-Path $env:HOME ".agents/skills/understand">>"%~3\install.ps1"',
        'echo New-Item -ItemType Directory -Path (Split-Path -Parent $link) -Force ^| Out-Null>>"%~3\install.ps1"',
        'echo New-Item -ItemType Junction -Path $link -Target $source ^| Out-Null>>"%~3\install.ps1"',
        'echo if ($env:TOOLING_FAIL -eq "understand") { exit 23 }>>"%~3\install.ps1"', 'exit /b 0'
    )
    $GitUnix = Join-Path $BinRoot "git"
    Write-Utf8WithoutBomLines -Path $GitUnix -Lines @(
        '#!/bin/sh', 'printf "git|%s\n" "$*" >> "$TOOLING_CALL_LOG"', 'mkdir -p "$3"',
        '[ "$TOOLING_FAIL" = git ] && exit 13',
        'case "$TOOLING_FAIL|$2" in git-superpowers*obra/superpowers*) exit 13;; esac',
        'case "$2" in *obra/superpowers*) mkdir -p "$3/skills/using-superpowers"; printf "%s\n" "name: using-superpowers" > "$3/skills/using-superpowers/SKILL.md"; exit 0;; esac',
        'case "$TOOLING_FAIL|$2" in git-understand*Understand-Anything*) exit 13;; esac',
        'mkdir -p "$3/understand-anything-plugin/skills/understand"',
        'printf "%s\n" "name: understand" > "$3/understand-anything-plugin/skills/understand/SKILL.md"',
        'printf "%s\n" ''Add-Content -LiteralPath $env:TOOLING_CALL_LOG -Value "understand-installer|codex"'' ''$source = Join-Path $env:HOME ".understand-anything/repo/understand-anything-plugin/skills/understand"'' ''$link = Join-Path $env:HOME ".agents/skills/understand"'' ''New-Item -ItemType Directory -Path (Split-Path -Parent $link) -Force | Out-Null'' ''New-Item -ItemType SymbolicLink -Path $link -Target $source | Out-Null'' ''if ($env:TOOLING_FAIL -eq "understand") { exit 23 }'' > "$3/install.ps1"',
        'exit 0'
    )
    New-ToolingCodexStub -BinRoot $BinRoot
    Write-Utf8WithoutBomLines -Path (Join-Path $BinRoot "codex.cmd") -Lines @(
        '@echo off', 'echo codex^|%*>>"%TOOLING_CALL_LOG%"',
        'if "%TOOLING_FAIL%"=="codex" exit /b 11',
        'exit /b 0'
    )
    $CodexUnix = Join-Path $BinRoot "codex"
    Write-Utf8WithoutBomLines -Path $CodexUnix -Lines @(
        '#!/bin/sh', 'printf "codex|%s\n" "$*" >> "$TOOLING_CALL_LOG"',
        '[ "$TOOLING_FAIL" = codex ] && exit 11',
        'exit 0'
    )
    if ($null -ne (Get-Command -Name chmod -ErrorAction SilentlyContinue))
    {
        & chmod +x $PythonUnix $GitUnix $CodexUnix
    }
}

function Invoke-ToolingFixture
{
    param(
        [string]$HomeRoot,
        [string]$CodexHome,
        [string]$BinRoot,
        [string]$Mode = "-Check",
        [string]$ScriptPath = $ToolingScript
    )

    $PreviousHome = $env:HOME
    $PreviousUserProfile = $env:USERPROFILE
    $PreviousCodexHome = $env:CODEX_HOME
    $PreviousPath = $env:PATH
    try
    {
        $env:HOME = $HomeRoot
        $env:USERPROFILE = $HomeRoot
        $env:CODEX_HOME = $CodexHome
        $env:PATH = $BinRoot + [System.IO.Path]::PathSeparator + $PreviousPath
        return Invoke-ChildPowerShell -ScriptPath $ScriptPath -Arguments @($Mode)
    }
    finally
    {
        $env:HOME = $PreviousHome
        $env:USERPROFILE = $PreviousUserProfile
        $env:CODEX_HOME = $PreviousCodexHome
        $env:PATH = $PreviousPath
    }
}

function test_tooling_reports_installed_disabled_broken_and_missing
{
    Assert-FileExists -Path $ToolingScript -Message "PowerShell 에이전트 도구 점검기가 없습니다."
    $Cases = @(
        @{ Name = "installed"; SuperState = "true"; CreateSuperSkill = $true; Expected = "installed"; ExitCode = 0 },
        @{ Name = "disabled"; SuperState = "false"; CreateSuperSkill = $true; Expected = "disabled"; ExitCode = 1 },
        @{ Name = "broken"; SuperState = "true"; CreateSuperSkill = $false; Expected = "broken"; ExitCode = 1 },
        @{ Name = "missing"; SuperState = "absent"; CreateSuperSkill = $false; Expected = "missing"; ExitCode = 1 }
    )
    foreach ($Case in $Cases)
    {
        $CaseRoot = Join-Path $TestTempRoot ("tooling-" + $Case.Name)
        $HomeRoot = Join-Path $CaseRoot "사용자 홈"
        $CodexHome = Join-Path $CaseRoot "Codex 홈"
        $BinRoot = Join-Path $CaseRoot "bin"
        New-Item -ItemType Directory -Path $HomeRoot -Force | Out-Null
        Write-ToolingCodexConfig -Path (Join-Path $CodexHome "config.toml") -KarpathyState "true" -SuperpowersState $Case.SuperState -UnderstandState "true"
        New-ToolingCacheSkill -CodexHome $CodexHome -PluginId "andrej-karpathy-skills" -Version "old" -SkillName "unrelated"
        New-ToolingCacheSkill -CodexHome $CodexHome -PluginId "andrej-karpathy-skills" -Version "new" -SkillName "karpathy-guidelines"
        New-ToolingCacheSkill -CodexHome $CodexHome -PluginId "understand-anything" -Version "new" -SkillName "understand"
        if ($Case.CreateSuperSkill)
        {
            New-ToolingCacheSkill -CodexHome $CodexHome -PluginId "superpowers" -Version "new" -SkillName "using-superpowers"
        }
        New-ToolingCodexStub -BinRoot $BinRoot
        $Before = Get-ProjectSnapshot -ProjectRoot $CaseRoot
        $Result = Invoke-ToolingFixture -HomeRoot $HomeRoot -CodexHome $CodexHome -BinRoot $BinRoot
        $After = Get-ProjectSnapshot -ProjectRoot $CaseRoot
        Assert-ExitCode -Expected $Case.ExitCode -Result $Result -Message "PowerShell 도구 상태 종료 코드가 다릅니다."
        Assert-Contains -Actual $Result.Output -ExpectedFragment "karpathy_guidelines|installed" -Message "Karpathy 고정 출력이 없습니다."
        Assert-Contains -Actual $Result.Output -ExpectedFragment ("superpowers|" + $Case.Expected) -Message "Superpowers 상태가 다릅니다."
        Assert-Contains -Actual $Result.Output -ExpectedFragment "understand_anything|installed" -Message "Understand-Anything 고정 출력이 없습니다."
        Assert-Equal -Expected $Before -Actual $After -Message "PowerShell -Check가 홈 픽스처를 변경했습니다."
    }

    $UnknownResult = Invoke-ChildPowerShell -ScriptPath $ToolingScript -Arguments @("-Unknown")
    Assert-ExitCode -Expected 2 -Result $UnknownResult -Message "PowerShell 알 수 없는 인자 종료 코드가 다릅니다."
}

function test_tooling_covers_each_tool_state_matrix
{
    $Tools = @(
        @{ Id = "karpathy_guidelines"; Plugin = "andrej-karpathy-skills"; Skill = "karpathy-guidelines" },
        @{ Id = "superpowers"; Plugin = "superpowers"; Skill = "using-superpowers" },
        @{ Id = "understand_anything"; Plugin = "understand-anything"; Skill = "understand" }
    )
    $Cases = @(
        @{ Name = "installed"; Config = "true"; HasSkill = $true; Expected = "installed"; ExitCode = 0 },
        @{ Name = "disabled"; Config = "false"; HasSkill = $true; Expected = "disabled"; ExitCode = 1 },
        @{ Name = "broken"; Config = "true"; HasSkill = $false; Expected = "broken"; ExitCode = 1 },
        @{ Name = "missing"; Config = "absent"; HasSkill = $false; Expected = "missing"; ExitCode = 1 }
    )
    foreach ($Target in $Tools)
    {
        foreach ($Case in $Cases)
        {
            $CaseRoot = Join-Path $TestTempRoot ("tooling-matrix-" + $Target.Id + "-" + $Case.Name)
            $HomeRoot = Join-Path $CaseRoot "사용자 홈"
            $CodexHome = Join-Path $CaseRoot "Codex 홈"
            $BinRoot = Join-Path $CaseRoot "bin"
            $States = @{
                karpathy_guidelines = "true"
                superpowers = "true"
                understand_anything = "true"
            }
            $States[$Target.Id] = $Case.Config
            New-Item -ItemType Directory -Path $HomeRoot -Force | Out-Null
            Write-ToolingCodexConfig -Path (Join-Path $CodexHome "config.toml") -KarpathyState $States.karpathy_guidelines -SuperpowersState $States.superpowers -UnderstandState $States.understand_anything
            foreach ($Tool in $Tools)
            {
                if ($Tool.Id -ne $Target.Id -or $Case.HasSkill)
                {
                    New-ToolingCacheSkill -CodexHome $CodexHome -PluginId $Tool.Plugin -Version "new" -SkillName $Tool.Skill
                }
            }
            New-ToolingCodexStub -BinRoot $BinRoot
            $Before = Get-ProjectSnapshot -ProjectRoot $CaseRoot
            $Result = Invoke-ToolingFixture -HomeRoot $HomeRoot -CodexHome $CodexHome -BinRoot $BinRoot
            $After = Get-ProjectSnapshot -ProjectRoot $CaseRoot
            Assert-ExitCode -Expected $Case.ExitCode -Result $Result -Message ($Target.Id + " " + $Case.Name + " 종료 코드가 다릅니다.")
            foreach ($Tool in $Tools)
            {
                $Expected = if ($Tool.Id -eq $Target.Id) { $Case.Expected } else { "installed" }
                Assert-Contains -Actual $Result.Output -ExpectedFragment ($Tool.Id + "|" + $Expected) -Message ($Tool.Id + " 상태가 다릅니다.")
            }
            Assert-Equal -Expected $Before -Actual $After -Message "-Check가 사용자 홈을 변경했습니다."
        }
    }
}

function test_tooling_rejects_ambiguous_config_and_wrong_cache_boundaries
{
    $ConfigCases = @(
        @(
            '[plugins."andrej-karpathy-skills@test-marketplace"]', 'enabled = true',
            '[plugins."superpowers@test-marketplace"]', 'enabled = true', 'enabled = true',
            '[plugins."understand-anything@test-marketplace"]', 'enabled = true'
        ),
        @(
            '[plugins."andrej-karpathy-skills@test-marketplace"]', 'enabled = true',
            '[plugins."superpowers@test-marketplace"]', 'enabled = true',
            '[plugins."superpowers@test-marketplace"]', 'enabled = true',
            '[plugins."understand-anything@test-marketplace"]', 'enabled = true'
        ),
        @(
            '[plugins."andrej-karpathy-skills@test-marketplace"]', 'enabled = true',
            '[plugins."superpowers@test-marketplace"]', 'enabled = true',
            '[plugins."superpowers@other-marketplace"]', 'enabled = false',
            '[plugins."understand-anything@test-marketplace"]', 'enabled = true'
        ),
        @(
            '[plugins."andrej-karpathy-skills@test-marketplace"]', 'enabled = true',
            '[plugins."superpowers@test-marketplace"', 'enabled = true',
            '[plugins."understand-anything@test-marketplace"]', 'enabled = true'
        )
    )
    for ($Index = 0; $Index -lt $ConfigCases.Count; $Index++)
    {
        $CaseRoot = Join-Path $TestTempRoot ("tooling-ambiguous-" + $Index)
        $HomeRoot = Join-Path $CaseRoot "home"
        $CodexHome = Join-Path $CaseRoot "codex"
        $BinRoot = Join-Path $CaseRoot "bin"
        New-Item -ItemType Directory -Path $HomeRoot, (Join-Path $CodexHome "plugins") -Force | Out-Null
        Write-Utf8WithoutBomLines -Path (Join-Path $CodexHome "config.toml") -Lines $ConfigCases[$Index]
        New-ToolingCacheSkill -CodexHome $CodexHome -PluginId "andrej-karpathy-skills" -Version "1" -SkillName "karpathy-guidelines"
        New-ToolingCacheSkill -CodexHome $CodexHome -PluginId "superpowers" -Version "1" -SkillName "using-superpowers"
        New-ToolingCacheSkill -CodexHome $CodexHome -PluginId "understand-anything" -Version "1" -SkillName "understand"
        New-ToolingCodexStub -BinRoot $BinRoot
        $Result = Invoke-ToolingFixture -HomeRoot $HomeRoot -CodexHome $CodexHome -BinRoot $BinRoot
        Assert-ExitCode -Expected 1 -Result $Result -Message "중복·상충 플러그인 설정을 허용했습니다."
        Assert-Contains -Actual $Result.Output -ExpectedFragment "superpowers|broken" -Message "중복·상충 상태가 broken이 아닙니다."
    }

    foreach ($Boundary in @("cross-market", "wrong-depth"))
    {
        $CaseRoot = Join-Path $TestTempRoot ("tooling-boundary-" + $Boundary)
        $HomeRoot = Join-Path $CaseRoot "home"
        $CodexHome = Join-Path $CaseRoot "codex"
        $BinRoot = Join-Path $CaseRoot "bin"
        New-Item -ItemType Directory -Path $HomeRoot -Force | Out-Null
        Write-ToolingCodexConfig -Path (Join-Path $CodexHome "config.toml") -KarpathyState "true" -SuperpowersState "true" -UnderstandState "true"
        New-ToolingCacheSkill -CodexHome $CodexHome -PluginId "andrej-karpathy-skills" -Version "1" -SkillName "karpathy-guidelines"
        New-ToolingCacheSkill -CodexHome $CodexHome -PluginId "understand-anything" -Version "1" -SkillName "understand"
        if ($Boundary -eq "cross-market")
        {
            New-ToolingCacheSkill -CodexHome $CodexHome -PluginId "superpowers" -Version "1" -SkillName "using-superpowers" -Marketplace "other-marketplace"
        }
        else
        {
            $WrongDepth = Join-Path $CodexHome "plugins/cache/test-marketplace/superpowers/skills/using-superpowers/SKILL.md"
            New-Item -ItemType Directory -Path (Split-Path -Parent $WrongDepth) -Force | Out-Null
            Write-Utf8WithoutBomLines -Path $WrongDepth -Lines @("name: using-superpowers")
        }
        New-ToolingCodexStub -BinRoot $BinRoot
        $Result = Invoke-ToolingFixture -HomeRoot $HomeRoot -CodexHome $CodexHome -BinRoot $BinRoot
        Assert-ExitCode -Expected 1 -Result $Result -Message "$Boundary 캐시 경계를 허용했습니다."
        Assert-Contains -Actual $Result.Output -ExpectedFragment "superpowers|broken" -Message "$Boundary 캐시를 broken으로 보고하지 않았습니다."
        if ($Boundary -eq "wrong-depth")
        {
            New-ToolingCacheSkill -CodexHome $CodexHome -PluginId "superpowers" -Version "1" -SkillName "using-superpowers"
            $MixedDepthResult = Invoke-ToolingFixture -HomeRoot $HomeRoot -CodexHome $CodexHome -BinRoot $BinRoot
            Assert-ExitCode -Expected 1 -Result $MixedDepthResult -Message "유효 캐시와 함께 있는 잘못된 깊이를 허용했습니다."
            Assert-Contains -Actual $MixedDepthResult.Output -ExpectedFragment "superpowers|broken" -Message "혼합 깊이 캐시를 broken으로 보고하지 않았습니다."
        }
    }

    $NestedLinkRoot = Join-Path $TestTempRoot "tooling-nested-cache-link"
    $NestedLinkHome = Join-Path $NestedLinkRoot "home"
    $NestedLinkCodex = Join-Path $NestedLinkRoot "codex"
    $NestedLinkBin = Join-Path $NestedLinkRoot "bin"
    New-Item -ItemType Directory -Path $NestedLinkHome -Force | Out-Null
    Write-ToolingCodexConfig -Path (Join-Path $NestedLinkCodex "config.toml") -KarpathyState "true" -SuperpowersState "true" -UnderstandState "true"
    New-ToolingCacheSkill -CodexHome $NestedLinkCodex -PluginId "andrej-karpathy-skills" -Version "1" -SkillName "karpathy-guidelines"
    New-ToolingCacheSkill -CodexHome $NestedLinkCodex -PluginId "superpowers" -Version "1" -SkillName "using-superpowers"
    New-ToolingCacheSkill -CodexHome $NestedLinkCodex -PluginId "understand-anything" -Version "1" -SkillName "understand"
    $NestedSkills = Join-Path $NestedLinkCodex "plugins/cache/test-marketplace/superpowers/1/skills"
    $ExternalSkills = Join-Path $NestedLinkRoot "external-skills"
    Move-Item -LiteralPath $NestedSkills -Destination $ExternalSkills
    New-ToolingDirectoryLink -Path $NestedSkills -Target $ExternalSkills
    New-ToolingCodexStub -BinRoot $NestedLinkBin
    $NestedLinkResult = Invoke-ToolingFixture -HomeRoot $NestedLinkHome -CodexHome $NestedLinkCodex -BinRoot $NestedLinkBin
    Assert-ExitCode -Expected 1 -Result $NestedLinkResult -Message "캐시 내부 skills 링크를 허용했습니다."
    Assert-Contains -Actual $NestedLinkResult.Output -ExpectedFragment "superpowers|broken" -Message "캐시 내부 링크를 broken으로 보고하지 않았습니다."

    $StandaloneRoot = Join-Path $TestTempRoot "tooling-standalone-precedence"
    $StandaloneHome = Join-Path $StandaloneRoot "home"
    $StandaloneCodex = Join-Path $StandaloneRoot "codex"
    $StandaloneBin = Join-Path $StandaloneRoot "bin"
    New-Item -ItemType Directory -Path $StandaloneHome -Force | Out-Null
    Write-Utf8WithoutBomLines -Path (Join-Path $StandaloneCodex "config.toml") -Lines @(
        '[plugins."andrej-karpathy-skills@test-marketplace"]', 'enabled = invalid',
        '[plugins."superpowers@test-marketplace"]', 'enabled = invalid',
        '[plugins."understand-anything@test-marketplace"]', 'enabled = invalid'
    )
    New-ToolingStandaloneSkill -CodexHome $StandaloneCodex -SkillName "karpathy-guidelines"
    New-ToolingStandaloneSkill -CodexHome $StandaloneCodex -SkillName "using-superpowers"
    New-ToolingStandaloneSkill -CodexHome $StandaloneCodex -SkillName "understand"
    New-ToolingCodexStub -BinRoot $StandaloneBin
    $StandaloneResult = Invoke-ToolingFixture -HomeRoot $StandaloneHome -CodexHome $StandaloneCodex -BinRoot $StandaloneBin
    Assert-ExitCode -Expected 1 -Result $StandaloneResult -Message "손상된 대상 TOML 헤더를 독립 스킬로 숨겼습니다."
    Assert-Contains -Actual $StandaloneResult.Output -ExpectedFragment "karpathy_guidelines|broken" -Message "Karpathy 손상 설정을 놓쳤습니다."
    Assert-Contains -Actual $StandaloneResult.Output -ExpectedFragment "superpowers|broken" -Message "Superpowers 손상 설정을 놓쳤습니다."
    Assert-Contains -Actual $StandaloneResult.Output -ExpectedFragment "understand_anything|broken" -Message "Understand 손상 설정을 놓쳤습니다."
}

function test_tooling_rejects_noncanonical_tooling_config_rows
{
    $ValidRows = @(
        'karpathy_guidelines|andrej-karpathy-skills|multica-ai/andrej-karpathy-skills|required',
        'superpowers|superpowers|obra/superpowers|required',
        'understand_anything|understand-anything|Egonex-AI/Understand-Anything|required'
    )
    $InvalidRows = @(
        @(' karpathy_guidelines|andrej-karpathy-skills|multica-ai/andrej-karpathy-skills|required', $ValidRows[1], $ValidRows[2]),
        @($ValidRows[0] + '|extra', $ValidRows[1], $ValidRows[2])
    )
    for ($Index = 0; $Index -lt $InvalidRows.Count; $Index++)
    {
        $CaseRoot = Join-Path $TestTempRoot ("tooling-config-invalid-" + $Index)
        $IsolatedRoot = Join-Path $CaseRoot "isolated"
        $IsolatedScript = Join-Path $IsolatedRoot ".agents/scripts/setup/check-agent-tooling.ps1"
        $IsolatedConfig = Join-Path $IsolatedRoot ".agents/config/agent-tooling.conf"
        $HomeRoot = Join-Path $CaseRoot "home"
        $CodexHome = Join-Path $CaseRoot "codex"
        $BinRoot = Join-Path $CaseRoot "bin"
        New-Item -ItemType Directory -Path (Split-Path -Parent $IsolatedScript), (Split-Path -Parent $IsolatedConfig), $HomeRoot -Force | Out-Null
        Copy-Item -LiteralPath $ToolingScript -Destination $IsolatedScript
        Write-Utf8WithoutBomLines -Path $IsolatedConfig -Lines $InvalidRows[$Index]
        New-ToolingCodexStub -BinRoot $BinRoot
        $Result = Invoke-ToolingFixture -HomeRoot $HomeRoot -CodexHome $CodexHome -BinRoot $BinRoot -ScriptPath $IsolatedScript
        Assert-ExitCode -Expected 2 -Result $Result -Message "정확하지 않은 도구 설정 행을 허용했습니다."
    }
}

function test_tooling_accepts_exact_standalone_links_and_rejects_unsafe_roots
{
    $CaseRoot = Join-Path $TestTempRoot "tooling-exact-links"
    $HomeRoot = Join-Path $CaseRoot "사용자 홈"
    $CodexHome = Join-Path $CaseRoot "Codex 홈"
    $BinRoot = Join-Path $CaseRoot "bin"
    New-Item -ItemType Directory -Path $HomeRoot -Force | Out-Null
    Write-ToolingCodexConfig -Path (Join-Path $CodexHome "config.toml") -KarpathyState "absent" -SuperpowersState "absent" -UnderstandState "absent"
    New-ToolingStandaloneSkill -CodexHome $CodexHome -SkillName "karpathy-guidelines"
    $SuperpowersSource = Join-Path $CodexHome "superpowers/skills"
    New-Item -ItemType Directory -Path (Join-Path $SuperpowersSource "using-superpowers") -Force | Out-Null
    Write-Utf8WithoutBomLines -Path (Join-Path $SuperpowersSource "using-superpowers/SKILL.md") -Lines @("name: using-superpowers")
    New-ToolingDirectoryLink -Path (Join-Path $HomeRoot ".agents/skills/superpowers") -Target $SuperpowersSource
    $UnderstandSource = Join-Path $HomeRoot ".understand-anything/repo/understand-anything-plugin/skills/understand"
    New-Item -ItemType Directory -Path $UnderstandSource -Force | Out-Null
    Write-Utf8WithoutBomLines -Path (Join-Path $UnderstandSource "SKILL.md") -Lines @("name: understand")
    New-ToolingDirectoryLink -Path (Join-Path $HomeRoot ".agents/skills/understand") -Target $UnderstandSource
    New-ToolingCodexStub -BinRoot $BinRoot
    $Result = Invoke-ToolingFixture -HomeRoot $HomeRoot -CodexHome $CodexHome -BinRoot $BinRoot
    Assert-ExitCode -Expected 0 -Result $Result -Message "정확한 독립 스킬 링크를 인식하지 못했습니다."
    Assert-ToolingInstalledOutputOrder -Output $Result.Output

    $PreviousHome = $env:HOME
    $PreviousUserProfile = $env:USERPROFILE
    $PreviousCodexHome = $env:CODEX_HOME
    $PreviousPath = $env:PATH
    try
    {
        $env:HOME = "relative-home"
        $env:USERPROFILE = "relative-profile"
        $env:CODEX_HOME = $CodexHome
        $env:PATH = $BinRoot + [System.IO.Path]::PathSeparator + $PreviousPath
        $InvalidHomeResult = Invoke-ChildPowerShell -ScriptPath $ToolingScript -Arguments @("-Check")
        Assert-ExitCode -Expected 2 -Result $InvalidHomeResult -Message "상대 사용자 홈을 허용했습니다."

        $env:HOME = $HomeRoot
        $env:USERPROFILE = $HomeRoot
        $env:CODEX_HOME = [System.IO.Path]::GetPathRoot($CodexHome)
        $RootCodexResult = Invoke-ChildPowerShell -ScriptPath $ToolingScript -Arguments @("-Check")
        Assert-ExitCode -Expected 2 -Result $RootCodexResult -Message "파일 시스템 루트 CODEX_HOME을 허용했습니다."

        $RootLink = Join-Path $CaseRoot "root-link"
        New-ToolingDirectoryLink -Path $RootLink -Target ([System.IO.Path]::GetPathRoot($HomeRoot))
        $env:HOME = $RootLink
        $env:USERPROFILE = $RootLink
        $env:CODEX_HOME = $CodexHome
        $RootLinkResult = Invoke-ChildPowerShell -ScriptPath $ToolingScript -Arguments @("-Check")
        Assert-ExitCode -Expected 2 -Result $RootLinkResult -Message "파일 시스템 루트를 가리키는 HOME 링크를 허용했습니다."
    }
    finally
    {
        $env:HOME = $PreviousHome
        $env:USERPROFILE = $PreviousUserProfile
        $env:CODEX_HOME = $PreviousCodexHome
        $env:PATH = $PreviousPath
    }
}

function test_tooling_rejects_symlinked_cache_and_escaped_install_roots
{
    $CacheCaseRoot = Join-Path $TestTempRoot "tooling-symlinked-cache-root"
    $CacheHome = Join-Path $CacheCaseRoot "home"
    $CacheCodex = Join-Path $CacheCaseRoot "codex"
    $CacheBin = Join-Path $CacheCaseRoot "bin"
    $ExternalCache = Join-Path $CacheCaseRoot "external-cache"
    New-Item -ItemType Directory -Path $CacheHome, (Join-Path $CacheCodex "plugins"), $ExternalCache -Force | Out-Null
    New-ToolingDirectoryLink -Path (Join-Path $CacheCodex "plugins/cache") -Target $ExternalCache
    Write-ToolingCodexConfig -Path (Join-Path $CacheCodex "config.toml") -KarpathyState "true" -SuperpowersState "true" -UnderstandState "true"
    New-ToolingCacheSkill -CodexHome $CacheCodex -PluginId "andrej-karpathy-skills" -Version "1" -SkillName "karpathy-guidelines"
    New-ToolingCacheSkill -CodexHome $CacheCodex -PluginId "superpowers" -Version "1" -SkillName "using-superpowers"
    New-ToolingCacheSkill -CodexHome $CacheCodex -PluginId "understand-anything" -Version "1" -SkillName "understand"
    New-ToolingCodexStub -BinRoot $CacheBin
    $CacheResult = Invoke-ToolingFixture -HomeRoot $CacheHome -CodexHome $CacheCodex -BinRoot $CacheBin
    Assert-ExitCode -Expected 1 -Result $CacheResult -Message "CODEX_HOME 밖으로 연결된 캐시 루트를 허용했습니다."
    Assert-Contains -Actual $CacheResult.Output -ExpectedFragment "karpathy_guidelines|broken" -Message "탈출한 Karpathy 캐시를 broken으로 보고하지 않았습니다."
    Assert-Contains -Actual $CacheResult.Output -ExpectedFragment "superpowers|broken" -Message "탈출한 Superpowers 캐시를 broken으로 보고하지 않았습니다."
    Assert-Contains -Actual $CacheResult.Output -ExpectedFragment "understand_anything|broken" -Message "탈출한 Understand 캐시를 broken으로 보고하지 않았습니다."

    $AgentsCaseRoot = Join-Path $TestTempRoot "tooling-escaped-agents-root"
    $AgentsHome = Join-Path $AgentsCaseRoot "home"
    $AgentsCodex = Join-Path $AgentsCaseRoot "codex"
    $AgentsBin = Join-Path $AgentsCaseRoot "bin"
    $AgentsExternal = Join-Path $AgentsCaseRoot "external-agents"
    $AgentsCallLog = Join-Path $AgentsCaseRoot "calls.log"
    New-Item -ItemType Directory -Path $AgentsHome, $AgentsCodex, $AgentsExternal -Force | Out-Null
    New-ToolingDirectoryLink -Path (Join-Path $AgentsHome ".agents") -Target $AgentsExternal
    Write-ToolingCodexConfig -Path (Join-Path $AgentsCodex "config.toml") -KarpathyState "absent" -SuperpowersState "absent" -UnderstandState "absent"
    New-ToolingStandaloneSkill -CodexHome $AgentsCodex -SkillName "karpathy-guidelines"
    New-ToolingStandaloneSkill -CodexHome $AgentsCodex -SkillName "understand"
    New-ToolingInstallStubs -BinRoot $AgentsBin
    $PreviousLog = $env:TOOLING_CALL_LOG
    $PreviousFail = $env:TOOLING_FAIL
    try
    {
        $env:TOOLING_CALL_LOG = $AgentsCallLog
        $env:TOOLING_FAIL = ""
        $AgentsResult = Invoke-ToolingFixture -HomeRoot $AgentsHome -CodexHome $AgentsCodex -BinRoot $AgentsBin -Mode "-InstallMissing"
    }
    finally
    {
        $env:TOOLING_CALL_LOG = $PreviousLog
        $env:TOOLING_FAIL = $PreviousFail
    }
    $AgentsCalls = if (Test-Path -LiteralPath $AgentsCallLog) { [System.IO.File]::ReadAllText($AgentsCallLog) } else { "" }
    Assert-ExitCode -Expected 3 -Result $AgentsResult -Message "HOME 밖으로 연결된 .agents 하위에 설치했습니다."
    Assert-Equal -Expected "" -Actual $AgentsCalls -Message "탈출한 .agents 경로를 거부하기 전에 설치 명령을 실행했습니다."

    $UnderstandCaseRoot = Join-Path $TestTempRoot "tooling-escaped-understand-root"
    $UnderstandHome = Join-Path $UnderstandCaseRoot "home"
    $UnderstandCodex = Join-Path $UnderstandCaseRoot "codex"
    $UnderstandBin = Join-Path $UnderstandCaseRoot "bin"
    $UnderstandExternal = Join-Path $UnderstandCaseRoot "external-understand"
    $UnderstandCallLog = Join-Path $UnderstandCaseRoot "calls.log"
    New-Item -ItemType Directory -Path $UnderstandHome, $UnderstandCodex, $UnderstandExternal -Force | Out-Null
    New-ToolingDirectoryLink -Path (Join-Path $UnderstandHome ".understand-anything") -Target $UnderstandExternal
    Write-ToolingCodexConfig -Path (Join-Path $UnderstandCodex "config.toml") -KarpathyState "absent" -SuperpowersState "absent" -UnderstandState "absent"
    New-ToolingStandaloneSkill -CodexHome $UnderstandCodex -SkillName "karpathy-guidelines"
    New-ToolingStandaloneSkill -CodexHome $UnderstandCodex -SkillName "using-superpowers"
    New-ToolingInstallStubs -BinRoot $UnderstandBin
    $PreviousLog = $env:TOOLING_CALL_LOG
    $PreviousFail = $env:TOOLING_FAIL
    try
    {
        $env:TOOLING_CALL_LOG = $UnderstandCallLog
        $env:TOOLING_FAIL = ""
        $UnderstandResult = Invoke-ToolingFixture -HomeRoot $UnderstandHome -CodexHome $UnderstandCodex -BinRoot $UnderstandBin -Mode "-InstallMissing"
    }
    finally
    {
        $env:TOOLING_CALL_LOG = $PreviousLog
        $env:TOOLING_FAIL = $PreviousFail
    }
    $UnderstandCalls = if (Test-Path -LiteralPath $UnderstandCallLog) { [System.IO.File]::ReadAllText($UnderstandCallLog) } else { "" }
    Assert-ExitCode -Expected 3 -Result $UnderstandResult -Message "HOME 밖으로 연결된 Understand 저장소 하위에 설치했습니다."
    Assert-Equal -Expected "" -Actual $UnderstandCalls -Message "탈출한 Understand 경로를 거부하기 전에 설치 명령을 실행했습니다."

    if ($env:OS -ne "Windows_NT")
    {
        $CaseSensitiveParent = Join-Path $TestTempRoot "tooling-case-sensitive-roots"
        $CaseSensitiveHome = Join-Path $CaseSensitiveParent "home"
        $CaseSensitiveExternal = Join-Path $CaseSensitiveParent "HOME"
        New-Item -ItemType Directory -Path $CaseSensitiveHome -Force | Out-Null
        if (-not (Test-Path -LiteralPath $CaseSensitiveExternal))
        {
            $CaseSensitiveCodex = Join-Path $CaseSensitiveParent "codex"
            $CaseSensitiveBin = Join-Path $CaseSensitiveParent "bin"
            $CaseSensitiveCallLog = Join-Path $CaseSensitiveParent "calls.log"
            New-Item -ItemType Directory -Path $CaseSensitiveExternal, $CaseSensitiveCodex -Force | Out-Null
            New-ToolingDirectoryLink -Path (Join-Path $CaseSensitiveHome ".agents") -Target $CaseSensitiveExternal
            Write-ToolingCodexConfig -Path (Join-Path $CaseSensitiveCodex "config.toml") -KarpathyState "absent" -SuperpowersState "absent" -UnderstandState "absent"
            New-ToolingStandaloneSkill -CodexHome $CaseSensitiveCodex -SkillName "karpathy-guidelines"
            New-ToolingStandaloneSkill -CodexHome $CaseSensitiveCodex -SkillName "understand"
            New-ToolingInstallStubs -BinRoot $CaseSensitiveBin
            $PreviousLog = $env:TOOLING_CALL_LOG
            $PreviousFail = $env:TOOLING_FAIL
            try
            {
                $env:TOOLING_CALL_LOG = $CaseSensitiveCallLog
                $env:TOOLING_FAIL = ""
                $CaseSensitiveResult = Invoke-ToolingFixture -HomeRoot $CaseSensitiveHome -CodexHome $CaseSensitiveCodex -BinRoot $CaseSensitiveBin -Mode "-InstallMissing"
            }
            finally
            {
                $env:TOOLING_CALL_LOG = $PreviousLog
                $env:TOOLING_FAIL = $PreviousFail
            }
            $CaseSensitiveCalls = if (Test-Path -LiteralPath $CaseSensitiveCallLog) { [System.IO.File]::ReadAllText($CaseSensitiveCallLog) } else { "" }
            Assert-ExitCode -Expected 3 -Result $CaseSensitiveResult -Message "대소문자만 다른 외부 HOME 형제 경로를 허용했습니다."
            Assert-Equal -Expected "" -Actual $CaseSensitiveCalls -Message "대소문자 형제 경로를 거부하기 전에 설치 명령을 실행했습니다."
        }
    }
}

function test_tooling_install_missing_success_failure_and_sequential_stop
{
    $SuccessCases = @(
        @{ Name = "karpathy"; Karpathy = "absent"; Superpowers = "true"; Understand = "true"; ExpectedCall = "python3|" },
        @{ Name = "superpowers"; Karpathy = "true"; Superpowers = "absent"; Understand = "true"; ExpectedCall = "git|clone https://github.com/obra/superpowers.git" },
        @{ Name = "understand"; Karpathy = "true"; Superpowers = "true"; Understand = "absent"; ExpectedCall = "understand-installer|codex" }
    )
    foreach ($Case in $SuccessCases)
    {
        $CaseRoot = Join-Path $TestTempRoot ("tooling-install-success-" + $Case.Name)
        $HomeRoot = Join-Path $CaseRoot "home"
        $CodexHome = Join-Path $CaseRoot "codex"
        $BinRoot = Join-Path $CaseRoot "bin"
        $CallLog = Join-Path $CaseRoot "calls.log"
        New-Item -ItemType Directory -Path $HomeRoot, (Join-Path $CodexHome "skills/.system/skill-installer/scripts") -Force | Out-Null
        Write-Utf8WithoutBomLines -Path (Join-Path $CodexHome "skills/.system/skill-installer/scripts/install-skill-from-github.py") -Lines @("# fixture")
        Write-ToolingCodexConfig -Path (Join-Path $CodexHome "config.toml") -KarpathyState $Case.Karpathy -SuperpowersState $Case.Superpowers -UnderstandState $Case.Understand
        if ($Case.Karpathy -eq "true") { New-ToolingCacheSkill -CodexHome $CodexHome -PluginId "andrej-karpathy-skills" -Version "1" -SkillName "karpathy-guidelines" }
        if ($Case.Superpowers -eq "true") { New-ToolingCacheSkill -CodexHome $CodexHome -PluginId "superpowers" -Version "1" -SkillName "using-superpowers" }
        if ($Case.Understand -eq "true") { New-ToolingCacheSkill -CodexHome $CodexHome -PluginId "understand-anything" -Version "1" -SkillName "understand" }
        New-ToolingInstallStubs -BinRoot $BinRoot
        $PreviousLog = $env:TOOLING_CALL_LOG
        $PreviousFail = $env:TOOLING_FAIL
        try
        {
            $env:TOOLING_CALL_LOG = $CallLog
            $env:TOOLING_FAIL = ""
            $Result = Invoke-ToolingFixture -HomeRoot $HomeRoot -CodexHome $CodexHome -BinRoot $BinRoot -Mode "-InstallMissing"
        }
        finally
        {
            $env:TOOLING_CALL_LOG = $PreviousLog
            $env:TOOLING_FAIL = $PreviousFail
        }
        Assert-ExitCode -Expected 0 -Result $Result -Message ($Case.Name + " 설치 성공을 보고하지 않았습니다.")
        Assert-Contains -Actual ([System.IO.File]::ReadAllText($CallLog)) -ExpectedFragment $Case.ExpectedCall -Message ($Case.Name + " 설치 명령이 없습니다.")
        Assert-Contains -Actual $Result.Output -ExpectedFragment "karpathy_guidelines|installed" -Message "Karpathy 설치 후 상태가 다릅니다."
        Assert-Contains -Actual $Result.Output -ExpectedFragment "superpowers|installed" -Message "Superpowers 설치 후 상태가 다릅니다."
        Assert-Contains -Actual $Result.Output -ExpectedFragment "understand_anything|installed" -Message "Understand 설치 후 상태가 다릅니다."
        Assert-ToolingInstalledOutputOrder -Output $Result.Output
        if ($Case.Name -eq "superpowers")
        {
            Assert-FileExists -Path (Join-Path $CodexHome "superpowers/skills/using-superpowers/SKILL.md") -Message "Superpowers 공식 저장소 스킬이 없습니다."
            Assert-FileExists -Path (Join-Path $HomeRoot ".agents/skills/superpowers/using-superpowers/SKILL.md") -Message "Superpowers 공식 스킬 링크가 없습니다."
        }
        elseif ($Case.Name -eq "understand")
        {
            Assert-FileExists -Path (Join-Path $HomeRoot ".agents/skills/understand/SKILL.md") -Message "UA 검증 링크가 없습니다."
        }
    }

    $FailureCases = @(
        @{ Name = "python-stop"; Fail = "python3"; Karpathy = "absent"; Superpowers = "absent"; Understand = "absent"; Expected = "python3|"; Forbidden = "git|" },
        @{ Name = "superpowers-stop"; Fail = "git-superpowers"; Karpathy = "true"; Superpowers = "absent"; Understand = "absent"; Expected = "git|clone https://github.com/obra/superpowers.git"; Forbidden = "Understand-Anything" },
        @{ Name = "understand-clone-stop"; Fail = "git-understand"; Karpathy = "true"; Superpowers = "true"; Understand = "absent"; Expected = "git|"; Forbidden = "understand-installer|" },
        @{ Name = "understand-exit"; Fail = "understand"; Karpathy = "true"; Superpowers = "true"; Understand = "absent"; Expected = "understand-installer|codex"; Forbidden = "never-called|" }
    )
    foreach ($Case in $FailureCases)
    {
        $CaseRoot = Join-Path $TestTempRoot ("tooling-install-failure-" + $Case.Name)
        $HomeRoot = Join-Path $CaseRoot "home"
        $CodexHome = Join-Path $CaseRoot "codex"
        $BinRoot = Join-Path $CaseRoot "bin"
        $CallLog = Join-Path $CaseRoot "calls.log"
        New-Item -ItemType Directory -Path $HomeRoot, (Join-Path $CodexHome "skills/.system/skill-installer/scripts") -Force | Out-Null
        Write-Utf8WithoutBomLines -Path (Join-Path $CodexHome "skills/.system/skill-installer/scripts/install-skill-from-github.py") -Lines @("# fixture")
        Write-ToolingCodexConfig -Path (Join-Path $CodexHome "config.toml") -KarpathyState $Case.Karpathy -SuperpowersState $Case.Superpowers -UnderstandState $Case.Understand
        if ($Case.Karpathy -eq "true") { New-ToolingCacheSkill -CodexHome $CodexHome -PluginId "andrej-karpathy-skills" -Version "1" -SkillName "karpathy-guidelines" }
        if ($Case.Superpowers -eq "true") { New-ToolingCacheSkill -CodexHome $CodexHome -PluginId "superpowers" -Version "1" -SkillName "using-superpowers" }
        New-ToolingInstallStubs -BinRoot $BinRoot
        $PreviousLog = $env:TOOLING_CALL_LOG
        $PreviousFail = $env:TOOLING_FAIL
        try
        {
            $env:TOOLING_CALL_LOG = $CallLog
            $env:TOOLING_FAIL = $Case.Fail
            $Result = Invoke-ToolingFixture -HomeRoot $HomeRoot -CodexHome $CodexHome -BinRoot $BinRoot -Mode "-InstallMissing"
        }
        finally
        {
            $env:TOOLING_CALL_LOG = $PreviousLog
            $env:TOOLING_FAIL = $PreviousFail
        }
        Assert-ExitCode -Expected 3 -Result $Result -Message ($Case.Name + " 설치 실패 종료 코드가 다릅니다.")
        $Calls = [System.IO.File]::ReadAllText($CallLog)
        Assert-Contains -Actual $Calls -ExpectedFragment $Case.Expected -Message ($Case.Name + " 실패 호출이 없습니다.")
        Assert-NotContains -Actual $Calls -UnexpectedFragment $Case.Forbidden -Message ($Case.Name + " 실패 후 다음 설치를 실행했습니다.")
        if ($Case.Fail -eq "git-understand")
        {
            Assert-True -Condition (-not (Test-Path -LiteralPath (Join-Path $HomeRoot ".understand-anything/repo"))) -Message "실패한 clone이 최종 UA repo_root를 남겼습니다."
        }
        if ($Case.Fail -eq "understand")
        {
            $UnderstandLink = Get-Item -LiteralPath (Join-Path $HomeRoot ".agents/skills/understand") -Force -ErrorAction SilentlyContinue
            Assert-True -Condition ($null -eq $UnderstandLink) -Message "실패한 UA installer가 전역 링크를 남겼습니다."
            Assert-True -Condition (-not (Test-Path -LiteralPath (Join-Path $HomeRoot ".understand-anything/repo"))) -Message "실패한 UA installer가 최종 저장소를 남겼습니다."
            $PreviousLog = $env:TOOLING_CALL_LOG
            $PreviousFail = $env:TOOLING_FAIL
            try
            {
                $env:TOOLING_CALL_LOG = $CallLog
                $env:TOOLING_FAIL = ""
                $RetryResult = Invoke-ToolingFixture -HomeRoot $HomeRoot -CodexHome $CodexHome -BinRoot $BinRoot -Mode "-InstallMissing"
            }
            finally
            {
                $env:TOOLING_CALL_LOG = $PreviousLog
                $env:TOOLING_FAIL = $PreviousFail
            }
            Assert-ExitCode -Expected 0 -Result $RetryResult -Message "UA installer 실패 후 재시도가 실패했습니다."
        }
        if ($Case.Fail -eq "git-superpowers")
        {
            Assert-True -Condition (-not (Test-Path -LiteralPath (Join-Path $CodexHome "superpowers"))) -Message "실패한 clone이 최종 Superpowers 저장소를 남겼습니다."
            $PreviousLog = $env:TOOLING_CALL_LOG
            $PreviousFail = $env:TOOLING_FAIL
            try
            {
                $env:TOOLING_CALL_LOG = $CallLog
                $env:TOOLING_FAIL = ""
                $RetryResult = Invoke-ToolingFixture -HomeRoot $HomeRoot -CodexHome $CodexHome -BinRoot $BinRoot -Mode "-InstallMissing"
            }
            finally
            {
                $env:TOOLING_CALL_LOG = $PreviousLog
                $env:TOOLING_FAIL = $PreviousFail
            }
            Assert-ExitCode -Expected 0 -Result $RetryResult -Message "Superpowers clone 실패 후 재시도가 실패했습니다."
        }
    }

    $GuardRoot = Join-Path $TestTempRoot "tooling-install-nonmissing-guard"
    $GuardHome = Join-Path $GuardRoot "home"
    $GuardCodex = Join-Path $GuardRoot "codex"
    $GuardBin = Join-Path $GuardRoot "bin"
    $GuardLog = Join-Path $GuardRoot "calls.log"
    New-Item -ItemType Directory -Path $GuardHome -Force | Out-Null
    Write-ToolingCodexConfig -Path (Join-Path $GuardCodex "config.toml") -KarpathyState "false" -SuperpowersState "true" -UnderstandState "true"
    New-ToolingCacheSkill -CodexHome $GuardCodex -PluginId "andrej-karpathy-skills" -Version "1" -SkillName "karpathy-guidelines"
    New-ToolingCacheSkill -CodexHome $GuardCodex -PluginId "superpowers" -Version "1" -SkillName "using-superpowers"
    New-ToolingCacheSkill -CodexHome $GuardCodex -PluginId "understand-anything" -Version "1" -SkillName "understand"
    New-ToolingInstallStubs -BinRoot $GuardBin
    $PreviousLog = $env:TOOLING_CALL_LOG
    try
    {
        $env:TOOLING_CALL_LOG = $GuardLog
        $GuardResult = Invoke-ToolingFixture -HomeRoot $GuardHome -CodexHome $GuardCodex -BinRoot $GuardBin -Mode "-InstallMissing"
    }
    finally
    {
        $env:TOOLING_CALL_LOG = $PreviousLog
    }
    Assert-ExitCode -Expected 1 -Result $GuardResult -Message "disabled 상태 설치 거부 종료 코드가 다릅니다."
    Assert-True -Condition (-not (Test-Path -LiteralPath $GuardLog)) -Message "disabled·broken 상태에서 설치 명령을 실행했습니다."
}

function test_parity_writes_requested_profile
{
    Assert-True -Condition (-not [string]::IsNullOrEmpty($ParityProjectRoot)) -Message "parity 프로젝트 경로가 필요합니다."
    Assert-True -Condition (-not [string]::IsNullOrEmpty($ParityProfilePath)) -Message "parity 프로필 경로가 필요합니다."
    Assert-True -Condition (-not [string]::IsNullOrEmpty($ParityReportPath)) -Message "parity 보고서 경로가 필요합니다."
    Import-DetectionApi
    $Result = Get-DetectionResult -ProjectRoot $ParityProjectRoot -ProfilePath $ParityProfilePath -ReportPath $ParityReportPath
    Assert-ExitCode -Expected 0 -Result $Result -Message "parity 감지 종료 코드가 다릅니다."
    Assert-FileExists -Path $ParityProfilePath -Message "parity 프로필이 없습니다."
    Assert-FileExists -Path $ParityReportPath -Message "parity 보고서가 없습니다."
}

function test_milestone_prebuild_requires_all_automated_tests
{
    $IntegrationEvidencePath = Join-Path $TestTempRoot "milestone-prebuild-integration-test.conf"
    $CompileEvidencePath = Join-Path $TestTempRoot "milestone-prebuild-compile-test.conf"
    $UnitEvidencePath = Join-Path $TestTempRoot "milestone-prebuild-unit-test.conf"

    $PowerShellHostPath = (Get-Process -Id $PID).Path
    New-MilestoneEvidence -Path $IntegrationEvidencePath -IntegrationResult "not_run" -BuildResult "pending"
    & $PowerShellHostPath -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $MilestoneValidator -Evidence $IntegrationEvidencePath -Phase prebuild -ExpectedChangeId commit-abc123 *> $null
    Assert-Equal -Expected 1 -Actual $LASTEXITCODE -Message "prebuild 자동 테스트 누락 종료 코드가 다릅니다."

    New-MilestoneEvidence -Path $CompileEvidencePath -IntegrationResult "passed" -BuildResult "pending"
    $CompileEvidenceLines = @((Read-Utf8WithoutBomLines -Path $CompileEvidencePath) | ForEach-Object {
        if ($_ -eq "compile=passed") { "compile=not_run" } else { $_ }
    })
    Write-Utf8WithoutBomLines -Path $CompileEvidencePath -Lines $CompileEvidenceLines
    & $PowerShellHostPath -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $MilestoneValidator -Evidence $CompileEvidencePath -Phase prebuild -ExpectedChangeId commit-abc123 *> $null
    Assert-Equal -Expected 1 -Actual $LASTEXITCODE -Message "prebuild 컴파일 미실행 종료 코드가 다릅니다."

    New-MilestoneEvidence -Path $UnitEvidencePath -IntegrationResult "passed" -BuildResult "pending"
    $UnitEvidenceLines = @((Read-Utf8WithoutBomLines -Path $UnitEvidencePath) | ForEach-Object {
        if ($_ -eq "unit_test=passed") { "unit_test=failed" } else { $_ }
    })
    Write-Utf8WithoutBomLines -Path $UnitEvidencePath -Lines $UnitEvidenceLines
    & $PowerShellHostPath -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $MilestoneValidator -Evidence $UnitEvidencePath -Phase prebuild -ExpectedChangeId commit-abc123 *> $null
    Assert-Equal -Expected 1 -Actual $LASTEXITCODE -Message "prebuild 단위 테스트 실패 종료 코드가 다릅니다."
}

function test_milestone_prebuild_rejects_uncovered_records
{
    $EvidencePath = Join-Path $TestTempRoot "milestone-prebuild-uncovered-record.conf"
    New-MilestoneEvidence -Path $EvidencePath -IntegrationResult "passed" -BuildResult "pending"
    $EvidenceLines = @(Read-Utf8WithoutBomLines -Path $EvidencePath) + "interaction_result=Inventory>Reward|Game.Tests.InventoryRewardFlowTests|missing"
    Write-Utf8WithoutBomLines -Path $EvidencePath -Lines $EvidenceLines

    $PowerShellHostPath = (Get-Process -Id $PID).Path
    & $PowerShellHostPath -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $MilestoneValidator -Evidence $EvidencePath -Phase prebuild -ExpectedChangeId commit-abc123 *> $null
    Assert-Equal -Expected 1 -Actual $LASTEXITCODE -Message "prebuild 미커버 기록 거부 종료 코드가 다릅니다."
}

function test_milestone_build_requires_prebuild_contract
{
    $EvidencePath = Join-Path $TestTempRoot "milestone-build-prebuild-contract.conf"
    $ValidArtifactHash = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
    New-MilestoneEvidence -Path $EvidencePath -IntegrationResult "passed" -BuildResult "pending"

    $PowerShellHostPath = (Get-Process -Id $PID).Path
    & $PowerShellHostPath -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $MilestoneValidator -Evidence $EvidencePath -Phase prebuild -ExpectedChangeId commit-abc123 *> $null
    Assert-Equal -Expected 0 -Actual $LASTEXITCODE -Message "정상 prebuild 증거가 실패했습니다."

    & $PowerShellHostPath -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $MilestoneValidator -Evidence $EvidencePath -Phase built -ExpectedChangeId commit-abc123 *> $null
    Assert-Equal -Expected 1 -Actual $LASTEXITCODE -Message "pending 빌드 검증 종료 코드가 다릅니다."

    $EvidenceLines = Read-Utf8WithoutBomLines -Path $EvidencePath
    $UpdatedEvidenceLines = @($EvidenceLines | ForEach-Object {
        if ($_ -eq "build_validation=pending") { "build_validation=passed" }
        elseif ($_ -eq "build_run_id=pending") { "build_run_id=local-build-20260719-001" }
        elseif ($_ -eq "build_artifact_hash=pending") { "build_artifact_hash=$ValidArtifactHash" }
        else { $_ }
    })
    Write-Utf8WithoutBomLines -Path $EvidencePath -Lines $UpdatedEvidenceLines
    $BrokenEvidenceLines = @((Read-Utf8WithoutBomLines -Path $EvidencePath) | ForEach-Object {
        if ($_ -eq "integration_test=passed") { "integration_test=not_run" } else { $_ }
    })
    Write-Utf8WithoutBomLines -Path $EvidencePath -Lines $BrokenEvidenceLines
    & $PowerShellHostPath -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $MilestoneValidator -Evidence $EvidencePath -Phase built -ExpectedChangeId commit-abc123 *> $null
    Assert-Equal -Expected 1 -Actual $LASTEXITCODE -Message "사전 조건이 깨진 빌드 검증 종료 코드가 다릅니다."

    $RestoredEvidenceLines = @((Read-Utf8WithoutBomLines -Path $EvidencePath) | ForEach-Object {
        if ($_ -eq "integration_test=not_run") { "integration_test=passed" } else { $_ }
    })
    Write-Utf8WithoutBomLines -Path $EvidencePath -Lines $RestoredEvidenceLines
    & $PowerShellHostPath -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $MilestoneValidator -Evidence $EvidencePath -Phase built -ExpectedChangeId commit-abc123 *> $null
    Assert-Equal -Expected 0 -Actual $LASTEXITCODE -Message "완료된 빌드 검증 증거가 실패했습니다."
}

function test_milestone_rejects_different_change_id
{
    $EvidencePath = Join-Path $TestTempRoot "milestone-change-id.conf"
    New-MilestoneEvidence -Path $EvidencePath -IntegrationResult "passed" -BuildResult "pending"

    $PowerShellHostPath = (Get-Process -Id $PID).Path
    & $PowerShellHostPath -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $MilestoneValidator -Evidence $EvidencePath -Phase prebuild -ExpectedChangeId commit-other *> $null
    Assert-Equal -Expected 1 -Actual $LASTEXITCODE -Message "다른 change_id 거부 종료 코드가 다릅니다."
}

function test_milestone_rejects_invalid_arguments_and_nonregular_evidence
{
    $CaseRoot = Join-Path $TestTempRoot "milestone-invalid-arguments"
    $EvidencePath = Join-Path $CaseRoot "evidence.conf"
    $EvidenceDirectory = Join-Path $CaseRoot "evidence-directory"
    $EvidenceLink = Join-Path $CaseRoot "evidence-link.conf"
    New-Item -ItemType Directory -Path $CaseRoot, $EvidenceDirectory -Force | Out-Null
    New-MilestoneEvidence -Path $EvidencePath -IntegrationResult "passed" -BuildResult "pending"

    $NoArgumentResult = Invoke-ChildPowerShell -ScriptPath $MilestoneValidator -NonInteractive -Arguments @()
    Assert-ExitCode -Expected 3 -Result $NoArgumentResult -Message "인자 없는 마일스톤 검증 종료 코드가 다릅니다."

    # 알 수 없는 이름과 값 토큰 누락은 PowerShell 바인더가 본문보다 먼저 처리하므로, -NonInteractive에서 nonzero만 보장합니다.
    $UnknownArgumentResult = Invoke-ChildPowerShell -ScriptPath $MilestoneValidator -NonInteractive -Arguments @("-Unknown")
    Assert-True -Condition ([int]$UnknownArgumentResult.ExitCode -ne 0) -Message "알 수 없는 마일스톤 검증 인자를 거부하지 않았습니다."
    $MissingValueResult = Invoke-ChildPowerShell -ScriptPath $MilestoneValidator -NonInteractive -Arguments @("-Evidence")
    Assert-True -Condition ([int]$MissingValueResult.ExitCode -ne 0) -Message "값이 누락된 evidence 인자를 거부하지 않았습니다."
    # 바인더를 통과한 빈 값과 생략된 선택 매개변수는 수동 인자 검사로 종료 코드 3을 보장합니다.
    $EmptyEvidenceResult = Invoke-MilestoneValidation -EvidencePath "" -Phase "prebuild" -ExpectedChangeId "commit-abc123"
    Assert-ExitCode -Expected 3 -Result $EmptyEvidenceResult -Message "빈 evidence 인자 종료 코드가 다릅니다."
    $MissingPhaseResult = Invoke-ChildPowerShell -ScriptPath $MilestoneValidator -NonInteractive -Arguments @("-Evidence", $EvidencePath, "-ExpectedChangeId", "commit-abc123")
    Assert-ExitCode -Expected 3 -Result $MissingPhaseResult -Message "누락된 phase 인자 종료 코드가 다릅니다."
    $MissingExpectedChangeResult = Invoke-ChildPowerShell -ScriptPath $MilestoneValidator -NonInteractive -Arguments @("-Evidence", $EvidencePath, "-Phase", "prebuild")
    Assert-ExitCode -Expected 3 -Result $MissingExpectedChangeResult -Message "누락된 ExpectedChangeId 인자 종료 코드가 다릅니다."

    $DirectoryResult = Invoke-MilestoneValidation -EvidencePath $EvidenceDirectory -Phase "prebuild" -ExpectedChangeId "commit-abc123"
    Assert-ExitCode -Expected 4 -Result $DirectoryResult -Message "디렉터리 evidence 종료 코드가 다릅니다."

    New-Item -ItemType SymbolicLink -Path $EvidenceLink -Target $EvidencePath | Out-Null
    $LinkResult = Invoke-MilestoneValidation -EvidencePath $EvidenceLink -Phase "prebuild" -ExpectedChangeId "commit-abc123"
    Assert-ExitCode -Expected 4 -Result $LinkResult -Message "재파싱 evidence 종료 코드가 다릅니다."

    $PassedResultEvidence = @((Read-Utf8WithoutBomLines -Path $EvidencePath) | ForEach-Object {
        if ($_ -eq "module_result=Login|Game.Tests.LoginModuleTests|passed") { "module_result=Login|Game.Tests.LoginModuleTests|Passed" } else { $_ }
    })
    Write-Utf8WithoutBomLines -Path $EvidencePath -Lines $PassedResultEvidence
    $UppercaseResult = Invoke-MilestoneValidation -EvidencePath $EvidencePath -Phase "prebuild" -ExpectedChangeId "commit-abc123"
    Assert-ExitCode -Expected 1 -Result $UppercaseResult -Message "Passed 결과 대소문자 거부 종료 코드가 다릅니다."

    New-MilestoneEvidence -Path $EvidencePath -IntegrationResult "passed" -BuildResult "pending"
    $UppercasePhaseResult = Invoke-MilestoneValidation -EvidencePath $EvidencePath -Phase "PREBUILD" -ExpectedChangeId "commit-abc123"
    Assert-ExitCode -Expected 3 -Result $UppercasePhaseResult -Message "PREBUILD phase 대소문자 거부 종료 코드가 다릅니다."
    $UppercaseExpectedChangeResult = Invoke-MilestoneValidation -EvidencePath $EvidencePath -Phase "prebuild" -ExpectedChangeId "COMMIT-ABC123"
    Assert-ExitCode -Expected 1 -Result $UppercaseExpectedChangeResult -Message "ExpectedChangeId 대소문자 거부 종료 코드가 다릅니다."
}

function test_milestone_rejects_malformed_files_and_reparse_profile
{
    $CaseRoot = Join-Path $TestTempRoot "milestone-malformed-files"
    $MalformedEvidencePath = Join-Path $CaseRoot "malformed-evidence.conf"
    $FixtureRoot = Join-Path $CaseRoot "fixture"
    $ProfileFixtureRoot = Join-Path $CaseRoot "reparse-profile"
    New-Item -ItemType Directory -Path $CaseRoot -Force | Out-Null
    Write-Utf8WithoutBomLines -Path $MalformedEvidencePath -Lines @("malformed evidence")

    $MalformedEvidenceResult = Invoke-MilestoneValidation -EvidencePath $MalformedEvidencePath -Phase "prebuild" -ExpectedChangeId "commit-abc123"
    Assert-ExitCode -Expected 4 -Result $MalformedEvidenceResult -Message "형식이 잘못된 evidence 종료 코드가 다릅니다."

    $EmptyEvidencePath = Join-Path $CaseRoot "empty-evidence.conf"
    [System.IO.File]::WriteAllBytes($EmptyEvidencePath, [byte[]]@())
    $EmptyEvidenceResult = Invoke-MilestoneValidation -EvidencePath $EmptyEvidencePath -Phase "prebuild" -ExpectedChangeId "commit-abc123"
    Assert-ExitCode -Expected 4 -Result $EmptyEvidenceResult -Message "빈 evidence 종료 코드가 다릅니다."

    $ValidatorSource = [System.IO.File]::ReadAllText($MilestoneValidator)
    Assert-Contains -Actual $ValidatorSource -ExpectedFragment "System.IO.FileInfo" -Message "일반 파일 형식 계약이 없습니다."
    Assert-Contains -Actual $ValidatorSource -ExpectedFragment "FileAttributes]::Device" -Message "Device 특수 파일 거부 계약이 없습니다."
    Assert-Contains -Actual $ValidatorSource -ExpectedFragment "FileAttributes]::ReparsePoint" -Message "재파싱 지점 거부 계약이 없습니다."
    Assert-Contains -Actual $ValidatorSource -ExpectedFragment "Length -le 0" -Message "길이 0 leaf 거부 계약이 없습니다."
    Assert-Contains -Actual $ValidatorSource -ExpectedFragment "File]::Open" -Message "일반 파일 읽기 실패 정규화 계약이 없습니다."

    New-MilestoneValidatorFixture -FixtureRoot $FixtureRoot
    $FixtureValidator = Join-Path $FixtureRoot ".agents/scripts/validation/check-unity-milestone.ps1"
    $FixtureEvidence = Join-Path $FixtureRoot ".agents/config/evidence.conf"
    $FixtureSchema = Join-Path $FixtureRoot ".agents/config/unity-milestone-validation-schema.conf"
    Write-Utf8WithoutBomLines -Path $FixtureSchema -Lines @("malformed schema")
    $MalformedSchemaResult = Invoke-MilestoneValidation -ValidatorPath $FixtureValidator -EvidencePath $FixtureEvidence -Phase "prebuild" -ExpectedChangeId "commit-abc123"
    Assert-ExitCode -Expected 4 -Result $MalformedSchemaResult -Message "형식이 잘못된 schema 종료 코드가 다릅니다."

    New-MilestoneValidatorFixture -FixtureRoot $ProfileFixtureRoot
    $ProfileFixtureValidator = Join-Path $ProfileFixtureRoot ".agents/scripts/validation/check-unity-milestone.ps1"
    $ProfileFixtureEvidence = Join-Path $ProfileFixtureRoot ".agents/config/evidence.conf"
    $ProfilePath = Join-Path $ProfileFixtureRoot ".agents/scripts/shared/profile.ps1"
    $ProfileTarget = Join-Path $ProfileFixtureRoot "profile-target.ps1"
    Move-Item -LiteralPath $ProfilePath -Destination $ProfileTarget
    New-Item -ItemType SymbolicLink -Path $ProfilePath -Target $ProfileTarget | Out-Null
    $ReparseProfileResult = Invoke-MilestoneValidation -ValidatorPath $ProfileFixtureValidator -EvidencePath $ProfileFixtureEvidence -Phase "prebuild" -ExpectedChangeId "commit-abc123"
    Assert-ExitCode -Expected 4 -Result $ReparseProfileResult -Message "재파싱 profile.ps1 종료 코드가 다릅니다."
}

function test_milestone_rejects_invalid_result_records
{
    $CaseRoot = Join-Path $TestTempRoot "milestone-invalid-records"
    $EvidencePath = Join-Path $CaseRoot "evidence.conf"
    New-Item -ItemType Directory -Path $CaseRoot -Force | Out-Null
    $Cases = @(
        @{ Name = "missing-delimiter"; Match = "module_result=Login|Game.Tests.LoginModuleTests|passed"; Replacement = "module_result=Login|Game.Tests.LoginModuleTests" }
        @{ Name = "extra-delimiter"; Match = "interaction_result=Login>Profile|Game.Tests.LoginProfileFlowTests|passed"; Replacement = "interaction_result=Login>Profile|Game.Tests.LoginProfileFlowTests|passed|extra" }
        @{ Name = "blank-subject"; Match = "module_result=Login|Game.Tests.LoginModuleTests|passed"; Replacement = "module_result=|Game.Tests.LoginModuleTests|passed" }
        @{ Name = "blank-test-id"; Match = "interaction_result=Login>Profile|Game.Tests.LoginProfileFlowTests|passed"; Replacement = "interaction_result=Login>Profile||passed" }
        @{ Name = "non-passed"; Match = "module_result=Login|Game.Tests.LoginModuleTests|passed"; Replacement = "module_result=Login|Game.Tests.LoginModuleTests|failed" }
    )

    foreach ($Case in $Cases)
    {
        New-MilestoneEvidence -Path $EvidencePath -IntegrationResult "passed" -BuildResult "pending"
        $EvidenceLines = @((Read-Utf8WithoutBomLines -Path $EvidencePath) | ForEach-Object {
            if ($_ -eq $Case.Match) { $Case.Replacement } else { $_ }
        })
        Write-Utf8WithoutBomLines -Path $EvidencePath -Lines $EvidenceLines
        $Result = Invoke-MilestoneValidation -EvidencePath $EvidencePath -Phase "prebuild" -ExpectedChangeId "commit-abc123"
        Assert-ExitCode -Expected 1 -Result $Result -Message ($Case.Name + " 결과 기록 거부 종료 코드가 다릅니다.")
    }
}

function test_milestone_rejects_whitespace_identifiers
{
    $CaseRoot = Join-Path $TestTempRoot "milestone-whitespace-identifiers"
    $EvidencePath = Join-Path $CaseRoot "evidence.conf"
    New-Item -ItemType Directory -Path $CaseRoot -Force | Out-Null
    $Cases = @(
        @{ Name = "milestone-blank"; Match = "milestone_id=login-flow"; Replacement = "milestone_id=   "; ExpectedChangeId = "commit-abc123"; ExpectedExitCode = 1 }
        @{ Name = "milestone-trim"; Match = "milestone_id=login-flow"; Replacement = "milestone_id= login-flow "; ExpectedChangeId = "commit-abc123"; ExpectedExitCode = 1 }
        @{ Name = "change-blank"; Match = "change_id=commit-abc123"; Replacement = "change_id=   "; ExpectedChangeId = "   "; ExpectedExitCode = 3 }
        @{ Name = "change-trim"; Match = "change_id=commit-abc123"; Replacement = "change_id= commit-abc123 "; ExpectedChangeId = " commit-abc123 "; ExpectedExitCode = 3 }
        @{ Name = "subject-blank"; Match = "module_result=Login|Game.Tests.LoginModuleTests|passed"; Replacement = "module_result=   |Game.Tests.LoginModuleTests|passed"; ExpectedChangeId = "commit-abc123"; ExpectedExitCode = 1 }
        @{ Name = "subject-trim"; Match = "module_result=Login|Game.Tests.LoginModuleTests|passed"; Replacement = "module_result= Login |Game.Tests.LoginModuleTests|passed"; ExpectedChangeId = "commit-abc123"; ExpectedExitCode = 1 }
        @{ Name = "test-id-blank"; Match = "interaction_result=Login>Profile|Game.Tests.LoginProfileFlowTests|passed"; Replacement = "interaction_result=Login>Profile|   |passed"; ExpectedChangeId = "commit-abc123"; ExpectedExitCode = 1 }
        @{ Name = "test-id-trim"; Match = "interaction_result=Login>Profile|Game.Tests.LoginProfileFlowTests|passed"; Replacement = "interaction_result=Login>Profile| Game.Tests.LoginProfileFlowTests |passed"; ExpectedChangeId = "commit-abc123"; ExpectedExitCode = 1 }
    )

    foreach ($Case in $Cases)
    {
        New-MilestoneEvidence -Path $EvidencePath -IntegrationResult "passed" -BuildResult "pending"
        $EvidenceLines = @((Read-Utf8WithoutBomLines -Path $EvidencePath) | ForEach-Object {
            if ($_ -eq $Case.Match) { $Case.Replacement } else { $_ }
        })
        Write-Utf8WithoutBomLines -Path $EvidencePath -Lines $EvidenceLines
        $Result = Invoke-MilestoneValidation -EvidencePath $EvidencePath -Phase "prebuild" -ExpectedChangeId $Case.ExpectedChangeId
        Assert-ExitCode -Expected $Case.ExpectedExitCode -Result $Result -Message ($Case.Name + " 공백 식별자 거부 종료 코드가 다릅니다.")
    }
}

function test_milestone_example_is_valid_and_read_only
{
    $ExamplePath = Join-Path $AgentsRoot "config/unity-milestone-validation.example.conf"
    $BeforeHash = (Get-FileHash -LiteralPath $ExamplePath -Algorithm SHA256).Hash
    $Result = Invoke-MilestoneValidation -EvidencePath $ExamplePath -Phase "prebuild" -ExpectedChangeId "commit-abc123"
    Assert-ExitCode -Expected 0 -Result $Result -Message "마일스톤 예제 prebuild 검증 종료 코드가 다릅니다."
    $AfterHash = (Get-FileHash -LiteralPath $ExamplePath -Algorithm SHA256).Hash
    Assert-Equal -Expected $BeforeHash -Actual $AfterHash -Message "마일스톤 예제 파일이 검증 중 변경되었습니다."
}

function test_milestone_propagates_profile_parser_contract_failure_as_input_error
{
    $CaseRoot = Join-Path $TestTempRoot "milestone-profile-parser-contract"
    $MissingApiRoot = Join-Path $CaseRoot "missing-api"
    $FailureRoot = Join-Path $CaseRoot "parser-failure"
    $InvalidReturnCases = @(
        @{ Name = "null"; Body = "function Read-HarnessProfile { return `$null }" }
        @{ Name = "string"; Body = "function Read-HarnessProfile { return 'not-a-profile' }" }
        @{ Name = "multiple"; Body = "function Read-HarnessProfile { Write-Output ([ordered]@{}); Write-Output ([ordered]@{}) }" }
    )

    New-MilestoneValidatorFixture -FixtureRoot $MissingApiRoot
    $MissingApiValidator = Join-Path $MissingApiRoot ".agents/scripts/validation/check-unity-milestone.ps1"
    $MissingApiEvidence = Join-Path $MissingApiRoot ".agents/config/evidence.conf"
    Write-Utf8WithoutBomLines -Path (Join-Path $MissingApiRoot ".agents/scripts/shared/profile.ps1") -Lines @()
    $MissingApiResult = Invoke-MilestoneValidation -ValidatorPath $MissingApiValidator -EvidencePath $MissingApiEvidence -Phase "prebuild" -ExpectedChangeId "commit-abc123"
    Assert-ExitCode -Expected 4 -Result $MissingApiResult -Message "Read-HarnessProfile 누락이 입력 오류로 전파되지 않았습니다."

    New-MilestoneValidatorFixture -FixtureRoot $FailureRoot
    $FailureValidator = Join-Path $FailureRoot ".agents/scripts/validation/check-unity-milestone.ps1"
    $FailureEvidence = Join-Path $FailureRoot ".agents/config/evidence.conf"
    Write-Utf8WithoutBomLines -Path (Join-Path $FailureRoot ".agents/scripts/shared/profile.ps1") -Lines @(
        "function Read-HarnessProfile { throw 'parser contract failure' }"
    )
    $ParserFailureResult = Invoke-MilestoneValidation -ValidatorPath $FailureValidator -EvidencePath $FailureEvidence -Phase "prebuild" -ExpectedChangeId "commit-abc123"
    Assert-ExitCode -Expected 4 -Result $ParserFailureResult -Message "Read-HarnessProfile 실패가 입력 오류로 전파되지 않았습니다."

    foreach ($InvalidReturnCase in $InvalidReturnCases)
    {
        $InvalidReturnRoot = Join-Path $CaseRoot ("invalid-return-" + $InvalidReturnCase.Name)
        New-MilestoneValidatorFixture -FixtureRoot $InvalidReturnRoot
        $InvalidReturnValidator = Join-Path $InvalidReturnRoot ".agents/scripts/validation/check-unity-milestone.ps1"
        $InvalidReturnEvidence = Join-Path $InvalidReturnRoot ".agents/config/evidence.conf"
        Write-Utf8WithoutBomLines -Path (Join-Path $InvalidReturnRoot ".agents/scripts/shared/profile.ps1") -Lines @($InvalidReturnCase.Body)
        $InvalidReturnResult = Invoke-MilestoneValidation -ValidatorPath $InvalidReturnValidator -EvidencePath $InvalidReturnEvidence -Phase "prebuild" -ExpectedChangeId "commit-abc123"
        Assert-ExitCode -Expected 4 -Result $InvalidReturnResult -Message ($InvalidReturnCase.Name + " Read-HarnessProfile 반환형 종료 코드가 다릅니다.")
    }
}

function test_milestone_requires_exact_confirmed_scope_coverage
{
    $CaseRoot = Join-Path $TestTempRoot "milestone-exact-scope-coverage"
    New-Item -ItemType Directory -Path $CaseRoot -Force | Out-Null
    $Cases = @(
        "missing-module"
        "missing-interaction"
        "unexpected-result"
        "duplicate-result"
        "duplicate-scope"
        "blank-scope"
        "none-scope"
        "trimmed-scope"
        "delimiter-scope"
    )

    foreach ($Case in $Cases)
    {
        $EvidencePath = Join-Path $CaseRoot ("$Case.conf")
        New-MilestoneEvidence -Path $EvidencePath -IntegrationResult "passed" -BuildResult "pending"
        $EvidenceLines = @(Read-Utf8WithoutBomLines -Path $EvidencePath)

        switch ($Case)
        {
            "missing-module" { $EvidenceLines = @($EvidenceLines | Where-Object { $_ -ne "module_result=Profile|Game.Tests.ProfileModuleTests|passed" }) }
            "missing-interaction" { $EvidenceLines += "interaction_scope=Profile>Home" }
            "unexpected-result" { $EvidenceLines += "module_result=Inventory|Game.Tests.InventoryModuleTests|passed" }
            "duplicate-result" { $EvidenceLines += "module_result=Login|Game.Tests.LoginModuleTests|passed" }
            "duplicate-scope" { $EvidenceLines += "module_scope=Login" }
            "blank-scope" { $EvidenceLines = @($EvidenceLines | ForEach-Object { if ($_ -eq "interaction_scope=Login>Profile") { "interaction_scope=   " } else { $_ } }) }
            "none-scope" { $EvidenceLines = @($EvidenceLines | ForEach-Object { if ($_ -eq "interaction_scope=Login>Profile") { "interaction_scope=none" } else { $_ } }) }
            "trimmed-scope" { $EvidenceLines = @($EvidenceLines | ForEach-Object { if ($_ -eq "interaction_scope=Login>Profile") { "interaction_scope= Login>Profile " } else { $_ } }) }
            "delimiter-scope" { $EvidenceLines = @($EvidenceLines | ForEach-Object { if ($_ -eq "interaction_scope=Login>Profile") { "interaction_scope=Login|Profile" } else { $_ } }) }
        }

        Write-Utf8WithoutBomLines -Path $EvidencePath -Lines $EvidenceLines
        $Result = Invoke-MilestoneValidation -EvidencePath $EvidencePath -Phase "prebuild" -ExpectedChangeId "commit-abc123"
        Assert-ExitCode -Expected 1 -Result $Result -Message ("$Case scope exact-match 종료 코드가 다릅니다.")
    }

    $CaseDistinctPath = Join-Path $CaseRoot "case-distinct-valid.conf"
    New-MilestoneEvidence -Path $CaseDistinctPath -IntegrationResult "passed" -BuildResult "pending"
    $CaseDistinctLines = @(Read-Utf8WithoutBomLines -Path $CaseDistinctPath) + @(
        "module_scope=login"
        "module_result=login|Game.Tests.LowercaseLoginModuleTests|passed"
    )
    Write-Utf8WithoutBomLines -Path $CaseDistinctPath -Lines $CaseDistinctLines
    $CaseDistinctResult = Invoke-MilestoneValidation -EvidencePath $CaseDistinctPath -Phase "prebuild" -ExpectedChangeId "commit-abc123"
    Assert-ExitCode -Expected 0 -Result $CaseDistinctResult -Message "대소문자가 다른 scope를 ordinal 중복으로 오인했습니다."
}

function test_milestone_build_requires_run_and_artifact_evidence
{
    $CaseRoot = Join-Path $TestTempRoot "milestone-build-evidence"
    $ValidHash = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
    $Cases = @(
        "valid-built"
        "missing-authority"
        "prebuild-run-id"
        "prebuild-artifact-hash"
        "pending-run"
        "blank-run"
        "none-run"
        "na-run"
        "not-run"
        "unknown-run"
        "upper-pending-run"
        "upper-na-run"
        "tbd-run"
        "upper-tbd-run"
        "dash-run"
        "spaced-pending-run"
        "wrong-authority"
        "trimmed-run"
        "pending-hash"
        "blank-hash"
        "short-hash"
        "uppercase-hash"
    )
    New-Item -ItemType Directory -Path $CaseRoot -Force | Out-Null

    foreach ($Case in $Cases)
    {
        $EvidencePath = Join-Path $CaseRoot ("$Case.conf")
        $Phase = "built"
        $ExpectedExitCode = 1
        New-MilestoneEvidence -Path $EvidencePath -IntegrationResult "passed" -BuildResult "pending"

        if ($Case -eq "prebuild-run-id")
        {
            $Phase = "prebuild"
            Set-MilestoneEvidenceValues -Path $EvidencePath -Values @{ build_run_id = "local-build-20260719-001" }
        }
        elseif ($Case -eq "prebuild-artifact-hash")
        {
            $Phase = "prebuild"
            Set-MilestoneEvidenceValues -Path $EvidencePath -Values @{ build_artifact_hash = $ValidHash }
        }
        else
        {
            Set-MilestoneEvidenceValues -Path $EvidencePath -Values @{
                build_validation = "passed"
                build_run_id = "local-build-20260719-001"
                build_artifact_hash = $ValidHash
            }
            switch ($Case)
            {
                "pending-run" { Set-MilestoneEvidenceValues -Path $EvidencePath -Values @{ build_run_id = "pending" } }
                "blank-run" { Set-MilestoneEvidenceValues -Path $EvidencePath -Values @{ build_run_id = "   " } }
                "none-run" { Set-MilestoneEvidenceValues -Path $EvidencePath -Values @{ build_run_id = "none" } }
                "na-run" { Set-MilestoneEvidenceValues -Path $EvidencePath -Values @{ build_run_id = "n/a" } }
                "not-run" { Set-MilestoneEvidenceValues -Path $EvidencePath -Values @{ build_run_id = "not_run" } }
                "unknown-run" { Set-MilestoneEvidenceValues -Path $EvidencePath -Values @{ build_run_id = "unknown" } }
                "upper-pending-run" { Set-MilestoneEvidenceValues -Path $EvidencePath -Values @{ build_run_id = "Pending" } }
                "upper-na-run" { Set-MilestoneEvidenceValues -Path $EvidencePath -Values @{ build_run_id = "N/A" } }
                "tbd-run" { Set-MilestoneEvidenceValues -Path $EvidencePath -Values @{ build_run_id = "tbd" } }
                "upper-tbd-run" { Set-MilestoneEvidenceValues -Path $EvidencePath -Values @{ build_run_id = "TBD" } }
                "dash-run" { Set-MilestoneEvidenceValues -Path $EvidencePath -Values @{ build_run_id = "-" } }
                "spaced-pending-run" { Set-MilestoneEvidenceValues -Path $EvidencePath -Values @{ build_run_id = " Pending " } }
                "trimmed-run" { Set-MilestoneEvidenceValues -Path $EvidencePath -Values @{ build_run_id = " local-build-20260719-001 " } }
                "pending-hash" { Set-MilestoneEvidenceValues -Path $EvidencePath -Values @{ build_artifact_hash = "pending" } }
                "blank-hash" { Set-MilestoneEvidenceValues -Path $EvidencePath -Values @{ build_artifact_hash = "   " } }
                "short-hash" { Set-MilestoneEvidenceValues -Path $EvidencePath -Values @{ build_artifact_hash = "0123456789abcdef" } }
                "uppercase-hash" { Set-MilestoneEvidenceValues -Path $EvidencePath -Values @{ build_artifact_hash = "ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789" } }
                "valid-built" { $ExpectedExitCode = 0 }
            }
        }

        if ($Case -eq "missing-authority")
        {
            $ExpectedExitCode = 3
            $Result = Invoke-ChildPowerShell -ScriptPath $MilestoneValidator -NonInteractive -Arguments @("-Evidence", $EvidencePath, "-Phase", $Phase, "-ExpectedChangeId", "commit-abc123")
        }
        elseif ($Case -eq "wrong-authority")
        {
            $Result = Invoke-MilestoneValidation -EvidencePath $EvidencePath -Phase $Phase -ExpectedChangeId "commit-abc123" -ExpectedAuthority "unity_ci"
        }
        else
        {
            $Result = Invoke-MilestoneValidation -EvidencePath $EvidencePath -Phase $Phase -ExpectedChangeId "commit-abc123"
        }
        Assert-ExitCode -Expected $ExpectedExitCode -Result $Result -Message ("$Case 빌드 증거 종료 코드가 다릅니다.")
        if ($Case -eq "valid-built")
        {
            Assert-Contains -Actual $Result.Output -ExpectedFragment "authority=local" -Message "성공 출력에 build_authority가 없습니다."
        }
    }
}

function test_milestone_schema_requires_new_evidence_keys
{
    $FixtureRoot = Join-Path $TestTempRoot "milestone-missing-schema-key"
    New-MilestoneValidatorFixture -FixtureRoot $FixtureRoot
    $FixtureValidator = Join-Path $FixtureRoot ".agents/scripts/validation/check-unity-milestone.ps1"
    $FixtureSchema = Join-Path $FixtureRoot ".agents/config/unity-milestone-validation-schema.conf"
    $FixtureEvidence = Join-Path $FixtureRoot ".agents/config/evidence.conf"
    $SchemaLines = @((Read-Utf8WithoutBomLines -Path $FixtureSchema) | Where-Object { -not $_.StartsWith("build_artifact_hash|") })
    Write-Utf8WithoutBomLines -Path $FixtureSchema -Lines $SchemaLines

    $Result = Invoke-MilestoneValidation -ValidatorPath $FixtureValidator -EvidencePath $FixtureEvidence -Phase "prebuild" -ExpectedChangeId "commit-abc123"
    Assert-ExitCode -Expected 4 -Result $Result -Message "새 빌드 증거 키가 누락된 schema 종료 코드가 다릅니다."
}

function test_milestone_rejects_trailing_empty_multiple_records
{
    $CaseRoot = Join-Path $TestTempRoot "milestone-trailing-empty-records"
    New-Item -ItemType Directory -Path $CaseRoot -Force | Out-Null
    foreach ($Case in @("module-scope", "module-result"))
    {
        $EvidencePath = Join-Path $CaseRoot ("$Case.conf")
        New-MilestoneEvidence -Path $EvidencePath -IntegrationResult "passed" -BuildResult "pending"
        $TrailingRecord = if ($Case -eq "module-scope") { "module_scope=" } else { "module_result=" }
        $EvidenceLines = @(Read-Utf8WithoutBomLines -Path $EvidencePath) + $TrailingRecord
        Write-Utf8WithoutBomLines -Path $EvidencePath -Lines $EvidenceLines

        $Result = Invoke-MilestoneValidation -EvidencePath $EvidencePath -Phase "prebuild" -ExpectedChangeId "commit-abc123"
        Assert-ExitCode -Expected 1 -Result $Result -Message ("$Case trailing empty 반복행 종료 코드가 다릅니다.")
    }
}

function test_milestone_artifact_hash_is_locale_independent
{
    $EvidencePath = Join-Path $TestTempRoot "milestone-uppercase-hash.conf"
    New-MilestoneEvidence -Path $EvidencePath -IntegrationResult "passed" -BuildResult "passed"
    Set-MilestoneEvidenceValues -Path $EvidencePath -Values @{
        build_run_id = "locale-build-001"
        build_artifact_hash = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
    }

    $Result = Invoke-MilestoneValidation -EvidencePath $EvidencePath -Phase "built" -ExpectedChangeId "commit-abc123" -ExpectedAuthority "local"
    Assert-ExitCode -Expected 1 -Result $Result -Message "대문자 SHA-256 거부 종료 코드가 다릅니다."
    $ValidatorSource = [System.IO.File]::ReadAllText($MilestoneValidator)
    Assert-Contains -Actual $ValidatorSource -ExpectedFragment "RegexOptions]::CultureInvariant" -Message "artifact hash 검사가 culture invariant가 아닙니다."
}

function Invoke-RegisteredTest
{
    param([hashtable]$Test)

    $IsGroupSelected = $Group -eq "all" -or $Group -eq $Test.Group
    $IsRuntimeSelected = $Runtime -eq "all" -or $Runtime -eq $Test.Runtime

    if ($Group -eq "all" -and $Test.Group -eq "parity" -and -not $script:ParityInputsProvided)
    {
        $script:SkippedCount++
        Write-Host "[건너뜀] $($Test.Name) (명시적 parity 입력 없음)"
        return
    }

    if (-not ($IsGroupSelected -and $IsRuntimeSelected))
    {
        $script:SkippedCount++
        Write-Host "[건너뜀] $($Test.Name)"
        return
    }

    $script:SelectedCount++
    $script:IsCurrentTestSkipped = $false
    $script:CurrentTestSkipReason = ""
    Write-Host "[실행] $($Test.Name)"
    $Diagnostics = @()
    $DidPass = $true

    try
    {
        & $Test.Name *>&1 | ForEach-Object {
            $Diagnostics += $_.ToString()
        }
    }
    catch
    {
        if (-not $script:IsCurrentTestSkipped)
        {
            $DidPass = $false
            $Diagnostics += $_.Exception.Message
        }
    }

    foreach ($Diagnostic in $Diagnostics)
    {
        Write-Host "[진단:$($Test.Name)] $Diagnostic"
    }

    if ($script:IsCurrentTestSkipped)
    {
        $script:SkippedCount++
        Write-Host "[건너뜀] $($Test.Name): $script:CurrentTestSkipReason"
    }
    elseif ($DidPass)
    {
        $script:PassedCount++
        Write-Host "[통과] $($Test.Name)"
    }
    else
    {
        $script:FailedCount++
        Write-Host "[실패] $($Test.Name)"
    }
}

$Tests = @(
    @{ Name = "test_profile_accepts_repeated_source_roots"; Group = "profile"; Runtime = "powershell" }
    @{ Name = "test_profile_rejects_unknown_key"; Group = "profile"; Runtime = "powershell" }
    @{ Name = "test_profile_rejects_invalid_enum"; Group = "profile"; Runtime = "powershell" }
    @{ Name = "test_profile_does_not_execute_values"; Group = "profile"; Runtime = "powershell" }
    @{ Name = "test_profile_confirmed_is_noop_and_cleanup_failure_is_best_effort"; Group = "profile"; Runtime = "powershell" }
    @{ Name = "test_reparse_paths_are_physicalized_and_entries_not_traversed"; Group = "profile"; Runtime = "powershell" }
    @{ Name = "test_detect_rejects_non_unity_directory"; Group = "detection"; Runtime = "powershell" }
    @{ Name = "test_detects_mvvm_vcontainer_unitask_urp"; Group = "detection"; Runtime = "powershell" }
    @{ Name = "test_detection_uses_assets_game_as_only_code_scope"; Group = "detection"; Runtime = "powershell" }
    @{ Name = "test_detection_rejects_missing_assets_game"; Group = "detection"; Runtime = "powershell" }
    @{ Name = "test_architecture_conflict_falls_back_to_custom"; Group = "detection"; Runtime = "powershell" }
    @{ Name = "test_detection_matches_render_async_and_asmdef_boundaries"; Group = "detection"; Runtime = "powershell" }
    @{ Name = "test_packages_lock_dependencies_are_merged_and_validated"; Group = "detection"; Runtime = "powershell" }
    @{ Name = "test_detection_matches_bash_optimization_matrix"; Group = "detection"; Runtime = "powershell" }
    @{ Name = "test_existing_confirmed_profile_is_not_overwritten"; Group = "detection"; Runtime = "powershell" }
    @{ Name = "test_initializer_confirm_and_redetect_contracts"; Group = "detection"; Runtime = "powershell" }
    @{ Name = "test_entrypoints_preserve_explicit_error_exit_codes"; Group = "detection"; Runtime = "powershell" }
    @{ Name = "test_detection_rejects_non_object_manifest_roots"; Group = "detection"; Runtime = "powershell" }
    @{ Name = "test_detection_lexically_sanitizes_interpolation_and_format_boundaries"; Group = "detection"; Runtime = "powershell" }
    @{ Name = "test_pending_profile_downgrades_profile_violation_to_warning"; Group = "lint"; Runtime = "powershell" }
    @{ Name = "test_confirmed_profile_blocks_profile_violation"; Group = "lint"; Runtime = "powershell" }
    @{ Name = "test_custom_profile_skips_architecture_specific_rules"; Group = "lint"; Runtime = "powershell" }
    @{ Name = "test_lint_rejects_source_root_outside_assets_game"; Group = "lint"; Runtime = "powershell" }
    @{ Name = "test_lint_machine_output_escapes_fields"; Group = "lint"; Runtime = "powershell" }
    @{ Name = "test_lint_merges_defaults_and_routes_core_technology_rules"; Group = "lint"; Runtime = "powershell" }
    @{ Name = "test_lint_io_failure_is_internal_exit_four"; Group = "lint"; Runtime = "powershell" }
    @{ Name = "test_lint_sanitizes_noise_and_limits_hot_loop_rules_to_update_ranges"; Group = "lint"; Runtime = "powershell" }
    @{ Name = "test_lint_supports_update_modifiers_expression_bodies_and_new_forms"; Group = "lint"; Runtime = "powershell" }
    @{ Name = "test_lint_all_methods_recognizes_implicit_and_generic_methods"; Group = "lint"; Runtime = "powershell" }
    @{ Name = "test_lint_matches_bash_linq_and_value_type_allocation_contracts"; Group = "lint"; Runtime = "powershell" }
    @{ Name = "test_korean_and_space_path_is_supported"; Group = "detection"; Runtime = "powershell" }
    @{ Name = "test_detection_report_has_required_headings"; Group = "detection"; Runtime = "powershell" }
    @{ Name = "test_detection_rolls_back_profile_when_report_fails"; Group = "detection"; Runtime = "powershell" }
    @{ Name = "test_detection_does_not_modify_project_files"; Group = "readonly"; Runtime = "powershell" }
    @{ Name = "test_tooling_reports_installed_disabled_broken_and_missing"; Group = "tooling"; Runtime = "powershell" }
    @{ Name = "test_tooling_covers_each_tool_state_matrix"; Group = "tooling"; Runtime = "powershell" }
    @{ Name = "test_tooling_rejects_ambiguous_config_and_wrong_cache_boundaries"; Group = "tooling"; Runtime = "powershell" }
    @{ Name = "test_tooling_rejects_noncanonical_tooling_config_rows"; Group = "tooling"; Runtime = "powershell" }
    @{ Name = "test_tooling_accepts_exact_standalone_links_and_rejects_unsafe_roots"; Group = "tooling"; Runtime = "powershell" }
    @{ Name = "test_tooling_rejects_symlinked_cache_and_escaped_install_roots"; Group = "tooling"; Runtime = "powershell" }
    @{ Name = "test_tooling_install_missing_success_failure_and_sequential_stop"; Group = "tooling"; Runtime = "powershell" }
    @{ Name = "test_milestone_prebuild_requires_all_automated_tests"; Group = "validation"; Runtime = "powershell" }
    @{ Name = "test_milestone_prebuild_rejects_uncovered_records"; Group = "validation"; Runtime = "powershell" }
    @{ Name = "test_milestone_build_requires_prebuild_contract"; Group = "validation"; Runtime = "powershell" }
    @{ Name = "test_milestone_rejects_different_change_id"; Group = "validation"; Runtime = "powershell" }
    @{ Name = "test_milestone_rejects_invalid_arguments_and_nonregular_evidence"; Group = "validation"; Runtime = "powershell" }
    @{ Name = "test_milestone_rejects_malformed_files_and_reparse_profile"; Group = "validation"; Runtime = "powershell" }
    @{ Name = "test_milestone_rejects_invalid_result_records"; Group = "validation"; Runtime = "powershell" }
    @{ Name = "test_milestone_rejects_whitespace_identifiers"; Group = "validation"; Runtime = "powershell" }
    @{ Name = "test_milestone_example_is_valid_and_read_only"; Group = "validation"; Runtime = "powershell" }
    @{ Name = "test_milestone_propagates_profile_parser_contract_failure_as_input_error"; Group = "validation"; Runtime = "powershell" }
    @{ Name = "test_milestone_requires_exact_confirmed_scope_coverage"; Group = "validation"; Runtime = "powershell" }
    @{ Name = "test_milestone_build_requires_run_and_artifact_evidence"; Group = "validation"; Runtime = "powershell" }
    @{ Name = "test_milestone_schema_requires_new_evidence_keys"; Group = "validation"; Runtime = "powershell" }
    @{ Name = "test_milestone_rejects_trailing_empty_multiple_records"; Group = "validation"; Runtime = "powershell" }
    @{ Name = "test_milestone_artifact_hash_is_locale_independent"; Group = "validation"; Runtime = "powershell" }
    @{ Name = "test_parity_writes_requested_profile"; Group = "parity"; Runtime = "powershell" }
)

New-Item -ItemType Directory -Path $TestTempRoot -Force | Out-Null

try
{
    foreach ($Test in $Tests)
    {
        Invoke-RegisteredTest -Test $Test
    }

    if ($script:SelectedCount -eq 0)
    {
        Write-Host "선택된 테스트가 없습니다."
        Write-Host "통과 $script:PassedCount / 실패 $script:FailedCount / 건너뜀 $script:SkippedCount"
        exit 2
    }

    Write-Host "통과 $script:PassedCount / 실패 $script:FailedCount / 건너뜀 $script:SkippedCount"
}
finally
{
    if (Test-Path -LiteralPath $TestTempRoot)
    {
        Remove-Item -LiteralPath $TestTempRoot -Recurse -Force
    }
}

if ($script:FailedCount -gt 0)
{
    exit 1
}

exit 0
