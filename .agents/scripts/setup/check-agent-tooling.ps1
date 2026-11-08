# ==============================================================================
# [기능]: 범용 하네스에 필요한 전역 에이전트 도구의 설치 상태를 안전하게 확인합니다.
# [작성자]: 윤승종
# ==============================================================================

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$Check = $false
$InstallMissing = $false
foreach ($Argument in $args)
{
    switch ([string]$Argument)
    {
        "-Check"
        {
            if ($Check -or $InstallMissing) { [Console]::Error.WriteLine("[에이전트 도구] 실행 모드는 하나만 사용할 수 있습니다."); exit 2 }
            $Check = $true
        }
        "-InstallMissing"
        {
            if ($Check -or $InstallMissing) { [Console]::Error.WriteLine("[에이전트 도구] 실행 모드는 하나만 사용할 수 있습니다."); exit 2 }
            $InstallMissing = $true
        }
        default
        {
            [Console]::Error.WriteLine("[에이전트 도구] 알 수 없는 인자입니다: $Argument")
            exit 2
        }
    }
}

$ScriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
$AgentsRoot = Split-Path -Parent (Split-Path -Parent $ScriptDirectory)
$ToolingConfigPath = Join-Path $AgentsRoot "config/agent-tooling.conf"
$UserHome = ""
$CodexHome = ""
$Utf8WithoutBom = New-Object System.Text.UTF8Encoding($false, $true)

function Resolve-AgentToolingRoot
{
    param(
        [string]$Path,
        [string]$Label
    )

    if ([string]::IsNullOrWhiteSpace($Path) -or -not [System.IO.Path]::IsPathRooted($Path))
    {
        throw "$Label 경로는 루트가 있는 절대 경로여야 합니다."
    }
    $Resolved = [System.IO.Path]::GetFullPath($Path).TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar)
    $InitialRoot = [System.IO.Path]::GetPathRoot($Resolved)
    $Current = $InitialRoot
    $Relative = $Resolved.Substring($InitialRoot.Length)
    foreach ($Segment in @($Relative -split '[\\/]' | Where-Object { -not [string]::IsNullOrEmpty($_) }))
    {
        $Candidate = Join-Path $Current $Segment
        $Item = Get-Item -LiteralPath $Candidate -Force -ErrorAction SilentlyContinue
        if ($null -ne $Item -and ($Item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)
        {
            $TargetItem = $null
            if ($null -ne $Item.PSObject.Methods["ResolveLinkTarget"])
            {
                $TargetItem = $Item.ResolveLinkTarget($true)
            }
            elseif ($null -ne $Item.Target)
            {
                $Target = [string]@($Item.Target)[0]
                if (-not [System.IO.Path]::IsPathRooted($Target))
                {
                    $Target = Join-Path (Split-Path -Parent $Candidate) $Target
                }
                $TargetItem = Get-Item -LiteralPath $Target -Force -ErrorAction SilentlyContinue
            }
            if ($null -eq $TargetItem)
            {
                throw "$Label 경로의 심볼릭 링크를 확인할 수 없습니다."
            }
            $Current = $TargetItem.FullName
        }
        else
        {
            $Current = if ($null -ne $Item) { $Item.FullName } else { $Candidate }
        }
    }
    $Resolved = [System.IO.Path]::GetFullPath($Current).TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar)
    $PathRoot = [System.IO.Path]::GetPathRoot($Resolved).TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar)
    if ([string]::IsNullOrEmpty($Resolved) -or $Resolved.Equals($PathRoot, [StringComparison]::OrdinalIgnoreCase))
    {
        throw "$Label 경로로 파일 시스템 루트를 사용할 수 없습니다."
    }
    return $Resolved
}

function Test-AgentToolingConfinedChildPath
{
    param(
        [string]$Path,
        [string]$Root
    )

    try
    {
        $ResolvedChild = Resolve-AgentToolingRoot -Path $Path -Label "하위 경로"
        $ResolvedRoot = Resolve-AgentToolingRoot -Path $Root -Label "기준 경로"
    }
    catch
    {
        return $false
    }
    $RootPrefix = $ResolvedRoot.TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
    $PathComparison = if ($env:OS -eq "Windows_NT")
    {
        [StringComparison]::OrdinalIgnoreCase
    }
    else
    {
        [StringComparison]::Ordinal
    }
    return $ResolvedChild.StartsWith($RootPrefix, $PathComparison)
}

function Initialize-AgentToolingRoots
{
    $HomeCandidate = if (-not [string]::IsNullOrWhiteSpace($env:HOME))
    {
        $env:HOME
    }
    elseif (-not [string]::IsNullOrWhiteSpace($env:USERPROFILE))
    {
        $env:USERPROFILE
    }
    else
    {
        [Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile)
    }
    $script:UserHome = Resolve-AgentToolingRoot -Path $HomeCandidate -Label "사용자 홈"
    $CodexCandidate = if ([string]::IsNullOrWhiteSpace($env:CODEX_HOME))
    {
        Join-Path $script:UserHome ".codex"
    }
    else
    {
        $env:CODEX_HOME
    }
    $script:CodexHome = Resolve-AgentToolingRoot -Path $CodexCandidate -Label "CODEX_HOME"
}

function New-AgentToolingInstallException
{
    param([string]$Message)

    $Exception = New-Object System.InvalidOperationException($Message)
    $Exception.Data["AgentToolingExitCode"] = 3
    return $Exception
}

function Throw-AgentToolingInstallFailure
{
    param([string]$Message)

    throw (New-AgentToolingInstallException -Message $Message)
}

function Read-ToolingUtf8Lines
{
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf))
    {
        throw "도구 설정 파일을 읽을 수 없습니다."
    }
    $Bytes = [System.IO.File]::ReadAllBytes($Path)
    if ($Bytes.Length -ge 3 -and $Bytes[0] -eq 0xEF -and $Bytes[1] -eq 0xBB -and $Bytes[2] -eq 0xBF)
    {
        throw "도구 설정 파일에 UTF-8 BOM을 사용할 수 없습니다."
    }
    return [System.IO.File]::ReadAllLines($Path, $Utf8WithoutBom)
}

function Read-AgentToolingConfig
{
    $Expected = [ordered]@{
        karpathy_guidelines = @("andrej-karpathy-skills", "multica-ai/andrej-karpathy-skills", "required")
        superpowers = @("superpowers", "obra/superpowers", "required")
        understand_anything = @("understand-anything", "Egonex-AI/Understand-Anything", "required")
    }
    $Result = [ordered]@{}
    foreach ($Line in (Read-ToolingUtf8Lines -Path $ToolingConfigPath))
    {
        $Trimmed = $Line.Trim()
        if ([string]::IsNullOrEmpty($Trimmed) -or $Trimmed.StartsWith("#", [StringComparison]::Ordinal))
        {
            continue
        }
        $Parts = $Line.Split([char]'|')
        if ($Parts.Length -ne 4 -or -not $Expected.Contains($Parts[0]) -or $Result.Contains($Parts[0]))
        {
            throw "도구 설정 행 형식이 올바르지 않습니다."
        }
        $ExpectedParts = $Expected[$Parts[0]]
        if ($Parts[1] -ne $ExpectedParts[0] -or $Parts[2] -ne $ExpectedParts[1] -or $Parts[3] -ne $ExpectedParts[2])
        {
            throw "허용되지 않은 도구 설정입니다."
        }
        $Result[$Parts[0]] = [PSCustomObject]@{
            Plugin = $Parts[1]
            Repository = $Parts[2]
            Policy = $Parts[3]
        }
    }
    if ($Result.Count -ne 3)
    {
        throw "필수 도구 설정이 누락되었습니다."
    }
    return $Result
}

function Get-PluginConfigInfo
{
    param([string]$PluginId)

    $ConfigPath = Join-Path $CodexHome "config.toml"
    if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf))
    {
        return [PSCustomObject]@{ IsBroken = $false; Records = @() }
    }

    $Records = New-Object 'System.Collections.Generic.List[object]'
    $SeenSections = New-Object 'System.Collections.Generic.HashSet[string]' -ArgumentList (, [StringComparer]::Ordinal)
    $CurrentRecord = $null
    $IsBroken = $false
    $HeaderPattern = '^\[plugins\."' + [Regex]::Escape($PluginId) + '@(?<marketplace>[A-Za-z0-9._-]+)"\]$'
    $TargetHeaderPrefix = '[plugins."' + $PluginId + '@'
    try
    {
        foreach ($Line in (Read-ToolingUtf8Lines -Path $ConfigPath))
        {
            $Trimmed = $Line.Trim()
            if ([string]::IsNullOrEmpty($Trimmed) -or $Trimmed.StartsWith("#", [StringComparison]::Ordinal))
            {
                continue
            }
            if ($Trimmed.StartsWith("[", [StringComparison]::Ordinal))
            {
                $CurrentRecord = $null
                $Match = [Regex]::Match($Trimmed, $HeaderPattern)
                if ($Match.Success)
                {
                    $Marketplace = $Match.Groups["marketplace"].Value
                    if ($Marketplace -in @(".", ".."))
                    {
                        $IsBroken = $true
                        continue
                    }
                    $SectionKey = $Match.Value
                    if (-not $SeenSections.Add($SectionKey))
                    {
                        $IsBroken = $true
                    }
                    $CurrentRecord = [PSCustomObject]@{
                        Marketplace = $Marketplace
                        State = "unset"
                        EnabledKeyCount = 0
                    }
                    [void]$Records.Add($CurrentRecord)
                }
                elseif ($Trimmed.StartsWith($TargetHeaderPrefix, [StringComparison]::Ordinal) -or
                    $Trimmed -match ('^\[plugins\."' + [Regex]::Escape($PluginId) + '"'))
                {
                    $IsBroken = $true
                }
                continue
            }
            if ($null -eq $CurrentRecord)
            {
                continue
            }
            if ($Trimmed -match '^enabled\s*=\s*(true|false)\s*(#.*)?$')
            {
                $CurrentRecord.EnabledKeyCount++
                if ($CurrentRecord.EnabledKeyCount -gt 1)
                {
                    $IsBroken = $true
                }
                $CurrentRecord.State = $Matches[1]
            }
            elseif ($Trimmed -match '^enabled\s*=')
            {
                $IsBroken = $true
            }
        }
    }
    catch
    {
        return [PSCustomObject]@{ IsBroken = $true; Records = @() }
    }

    foreach ($Record in $Records)
    {
        if ($Record.EnabledKeyCount -ne 1 -or $Record.State -eq "unset")
        {
            $IsBroken = $true
        }
    }
    if ($Records.Count -gt 1)
    {
        $IsBroken = $true
    }
    $DistinctStates = @($Records | ForEach-Object { $_.State } | Select-Object -Unique)
    if ($DistinctStates.Count -gt 1)
    {
        $IsBroken = $true
    }
    return [PSCustomObject]@{ IsBroken = $IsBroken; Records = @($Records) }
}

function Test-CacheSkillForMarketplace
{
    param(
        [string]$PluginId,
        [string]$Marketplace,
        [string]$SkillName
    )

    $CacheRoot = Join-Path $CodexHome "plugins/cache"
    if (-not (Test-AgentToolingConfinedChildPath -Path $CacheRoot -Root $CodexHome))
    {
        return $false
    }
    $PluginRoot = Join-Path $CacheRoot "$Marketplace/$PluginId"
    if (-not (Test-Path -LiteralPath $PluginRoot -PathType Container))
    {
        return $false
    }
    $MarketplaceRoot = Join-Path $CodexHome "plugins/cache/$Marketplace"
    $MarketplaceItem = Get-Item -LiteralPath $MarketplaceRoot -Force
    $PluginItem = Get-Item -LiteralPath $PluginRoot -Force
    if (($MarketplaceItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0 -or
        ($PluginItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)
    {
        return $false
    }
    foreach ($Version in @(Get-ChildItem -LiteralPath $PluginRoot -Directory -Force -ErrorAction SilentlyContinue))
    {
        if (($Version.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)
        {
            continue
        }
        $SkillsRoot = Get-Item -LiteralPath (Join-Path $Version.FullName "skills") -Force -ErrorAction SilentlyContinue
        $SkillRoot = Get-Item -LiteralPath (Join-Path $Version.FullName "skills/$SkillName") -Force -ErrorAction SilentlyContinue
        $SkillFile = Get-Item -LiteralPath (Join-Path $Version.FullName "skills/$SkillName/SKILL.md") -Force -ErrorAction SilentlyContinue
        if ($null -ne $SkillsRoot -and $null -ne $SkillRoot -and $null -ne $SkillFile -and
            ($SkillsRoot.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -eq 0 -and
            ($SkillRoot.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -eq 0 -and
            ($SkillFile.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -eq 0 -and
            $SkillsRoot.PSIsContainer -and $SkillRoot.PSIsContainer -and -not $SkillFile.PSIsContainer)
        {
            return $true
        }
    }
    return $false
}

function Test-AnyCacheSkill
{
    param(
        [string]$PluginId,
        [string]$SkillName
    )

    $CacheRoot = Join-Path $CodexHome "plugins/cache"
    if (-not (Test-AgentToolingConfinedChildPath -Path $CacheRoot -Root $CodexHome) -or
        -not (Test-Path -LiteralPath $CacheRoot -PathType Container))
    {
        return $false
    }
    foreach ($Marketplace in @(Get-ChildItem -LiteralPath $CacheRoot -Directory -Force -ErrorAction SilentlyContinue))
    {
        if (($Marketplace.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)
        {
            continue
        }
        if (Test-CacheSkillForMarketplace -PluginId $PluginId -Marketplace $Marketplace.Name -SkillName $SkillName)
        {
            return $true
        }
    }
    return $false
}

function Test-CacheHasWrongDepth
{
    param([string]$PluginId)

    $CacheRoot = Join-Path $CodexHome "plugins/cache"
    if (-not (Test-AgentToolingConfinedChildPath -Path $CacheRoot -Root $CodexHome))
    {
        return $true
    }
    if (-not (Test-Path -LiteralPath $CacheRoot -PathType Container))
    {
        return $false
    }
    foreach ($PluginRoot in @(Get-ChildItem -LiteralPath $CacheRoot -Directory -Recurse -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq $PluginId }))
    {
        $Relative = $PluginRoot.FullName.Substring($CacheRoot.Length).TrimStart(
            [System.IO.Path]::DirectorySeparatorChar,
            [System.IO.Path]::AltDirectorySeparatorChar)
        $Segments = @($Relative -split '[\\/]' | Where-Object { -not [string]::IsNullOrEmpty($_) })
        if ($Segments.Count -ne 2 -or $Segments[1] -ne $PluginId)
        {
            return $true
        }
    }
    return $false
}

function Test-AgentToolingPathEntry
{
    param([string]$Path)

    return $null -ne (Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue)
}

function Test-StandaloneSkill
{
    param(
        [string]$SkillName,
        [bool]$AllowAgentsRoot
    )

    if (Test-Path -LiteralPath (Join-Path $CodexHome "skills/$SkillName/SKILL.md") -PathType Leaf)
    {
        return $true
    }
    if ($AllowAgentsRoot -and (Test-Path -LiteralPath (Join-Path $UserHome ".agents/skills/$SkillName/SKILL.md") -PathType Leaf))
    {
        return $true
    }
    return $false
}

function Test-UnderstandRepoLink
{
    $LinkPath = Join-Path $UserHome ".agents/skills/understand"
    $SourcePath = Join-Path $UserHome ".understand-anything/repo/understand-anything-plugin/skills/understand"
    if (-not (Test-Path -LiteralPath (Join-Path $LinkPath "SKILL.md") -PathType Leaf) -or
        -not (Test-Path -LiteralPath (Join-Path $SourcePath "SKILL.md") -PathType Leaf))
    {
        return $false
    }
    $LinkItem = Get-Item -LiteralPath $LinkPath -Force
    if ([string]::IsNullOrEmpty([string]$LinkItem.LinkType))
    {
        return $false
    }
    $TargetValues = @($LinkItem.Target)
    if ($TargetValues.Count -eq 0) { return $false }
    $Target = [string]$TargetValues[0]
    if (-not [System.IO.Path]::IsPathRooted($Target))
    {
        $Target = Join-Path (Split-Path -Parent $LinkPath) $Target
    }
    $ResolvedTarget = [System.IO.Path]::GetFullPath($Target).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    $ResolvedSource = [System.IO.Path]::GetFullPath($SourcePath).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    $Comparison = if ($env:OS -eq "Windows_NT") { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
    return $ResolvedTarget.Equals($ResolvedSource, $Comparison)
}

function Test-SuperpowersRepoLink
{
    $LinkPath = Join-Path $UserHome ".agents/skills/superpowers"
    $SourcePath = Join-Path $CodexHome "superpowers/skills"
    if (-not (Test-Path -LiteralPath (Join-Path $LinkPath "using-superpowers/SKILL.md") -PathType Leaf) -or
        -not (Test-Path -LiteralPath (Join-Path $SourcePath "using-superpowers/SKILL.md") -PathType Leaf))
    {
        return $false
    }
    $LinkItem = Get-Item -LiteralPath $LinkPath -Force
    if (($LinkItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -eq 0)
    {
        return $false
    }
    $TargetValues = @($LinkItem.Target)
    if ($TargetValues.Count -eq 0) { return $false }
    $Target = [string]$TargetValues[0]
    if (-not [System.IO.Path]::IsPathRooted($Target))
    {
        $Target = Join-Path (Split-Path -Parent $LinkPath) $Target
    }
    $ResolvedTarget = [System.IO.Path]::GetFullPath($Target).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    $ResolvedSource = [System.IO.Path]::GetFullPath($SourcePath).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    $Comparison = if ($env:OS -eq "Windows_NT") { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
    return $ResolvedTarget.Equals($ResolvedSource, $Comparison)
}

function Get-AgentToolStatus
{
    param(
        [string]$PluginId,
        [string]$SkillName,
        [bool]$IsUnderstand,
        [bool]$IsSuperpowers
    )

    $ConfigInfo = Get-PluginConfigInfo -PluginId $PluginId
    if ($ConfigInfo.IsBroken)
    {
        return "broken"
    }

    $HasStandalone = Test-StandaloneSkill -SkillName $SkillName -AllowAgentsRoot (-not $IsUnderstand)
    if ($IsSuperpowers -and (Test-SuperpowersRepoLink))
    {
        $HasStandalone = $true
    }
    $RepoOnly = $false
    if ($IsUnderstand)
    {
        if (Test-UnderstandRepoLink)
        {
            $HasStandalone = $true
        }
        elseif (Test-Path -LiteralPath (Join-Path $UserHome ".understand-anything/repo/understand-anything-plugin/skills/understand/SKILL.md") -PathType Leaf)
        {
            $RepoOnly = $true
        }
        elseif (Test-AgentToolingPathEntry -Path (Join-Path $UserHome ".agents/skills/understand"))
        {
            $RepoOnly = $true
        }
    }
    elseif ($IsSuperpowers -and
        ((Test-AgentToolingPathEntry -Path (Join-Path $CodexHome "superpowers")) -or
         (Test-AgentToolingPathEntry -Path (Join-Path $UserHome ".agents/skills/superpowers"))))
    {
        $RepoOnly = $true
    }

    if ($HasStandalone)
    {
        return "installed"
    }
    if (Test-CacheHasWrongDepth -PluginId $PluginId)
    {
        return "broken"
    }
    $HasAnyCache = Test-AnyCacheSkill -PluginId $PluginId -SkillName $SkillName
    $Records = @($ConfigInfo.Records)
    if ($Records.Count -eq 0)
    {
        if ($HasAnyCache -or $RepoOnly)
        {
            return "broken"
        }
        return "missing"
    }
    if ($Records[0].State -eq "false")
    {
        return "disabled"
    }
    foreach ($Record in $Records)
    {
        if (-not (Test-CacheSkillForMarketplace -PluginId $PluginId -Marketplace $Record.Marketplace -SkillName $SkillName))
        {
            return "broken"
        }
    }
    return "installed"
}

function Get-AgentToolStates
{
    param([System.Collections.IDictionary]$Tools)

    return [ordered]@{
        karpathy_guidelines = Get-AgentToolStatus -PluginId $Tools.karpathy_guidelines.Plugin -SkillName "karpathy-guidelines" -IsUnderstand $false -IsSuperpowers $false
        superpowers = Get-AgentToolStatus -PluginId $Tools.superpowers.Plugin -SkillName "using-superpowers" -IsUnderstand $false -IsSuperpowers $true
        understand_anything = Get-AgentToolStatus -PluginId $Tools.understand_anything.Plugin -SkillName "understand" -IsUnderstand $true -IsSuperpowers $false
    }
}

function Write-AgentToolStates
{
    param([System.Collections.IDictionary]$States)

    foreach ($ToolId in @("karpathy_guidelines", "superpowers", "understand_anything"))
    {
        Write-Output "$ToolId|$($States[$ToolId])"
    }
}

function Write-CodexSandboxWarning
{
    # Warning only: read-only Codex sandboxes block the orca CLI runtime connection (EPERM).
    # Same reader as check-agent-tooling.sh: a verified TOML parser only (tomllib, tomli or pip's
    # vendored tomli); a parse error or a missing parser warns.
    $ConfigPath = Join-Path $CodexHome "config.toml"
    $Reader = @'
import sys

# A verified TOML parser only: tomllib (3.11+), tomli, or the tomli that pip vendors
# (macOS /usr/bin/python3 3.9). Without one the setting cannot be confirmed, so warn.
for name in ('tomllib', 'tomli', 'pip._vendor.tomli'):
    try:
        parser = __import__(name, fromlist=['loads'])
        break
    except ImportError:
        continue
else:
    sys.exit(1)
data = parser.loads(open(sys.argv[1], encoding='utf-8').read())
table = data.get('sandbox_workspace_write')
mode, network = data.get('sandbox_mode'), table.get('network_access') if isinstance(table, dict) else None
sys.exit(0 if mode == 'danger-full-access' or (mode == 'workspace-write' and network is True) else 1)
'@
    $Python = Get-Command -Name python3, python -ErrorAction SilentlyContinue | Select-Object -First 1
    if ((Test-Path -LiteralPath $ConfigPath -PathType Leaf) -and $null -ne $Python)
    {
        $Reader | & $Python.Source -I -B - $ConfigPath 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) { return }
    }
    [Console]::Error.WriteLine("[에이전트 도구] 경고: Codex 샌드박스가 orca 연결을 EPERM(runtime_access_denied)으로 막을 수 있습니다. $ConfigPath 최상위에 sandbox_mode = `"workspace-write`"와 [sandbox_workspace_write] network_access = true를 두고 codex app-server daemon restart 후 실행 중인 Codex 세션을 재시작하세요. 설정을 읽을 수 없어도 이 경고를 표시합니다.")
}

function Test-AllToolsInstalled
{
    param([System.Collections.IDictionary]$States)

    return $States.karpathy_guidelines -eq "installed" -and
        $States.superpowers -eq "installed" -and
        $States.understand_anything -eq "installed"
}

function Write-RecoveryGuidance
{
    param([System.Collections.IDictionary]$States)

    if ($States.karpathy_guidelines -in @("disabled", "broken"))
    {
        Write-RecoveryPrerequisites -ToolId "karpathy_guidelines" -State $States.karpathy_guidelines
        [Console]::Error.WriteLine('Karpathy 복구 1: $CodexRoot = if ([string]::IsNullOrWhiteSpace($env:CODEX_HOME)) { Join-Path $HOME ".codex" } else { $env:CODEX_HOME }')
        [Console]::Error.WriteLine('Karpathy 복구 2: python3 (Join-Path $CodexRoot "skills/.system/skill-installer/scripts/install-skill-from-github.py") --repo multica-ai/andrej-karpathy-skills --path skills/karpathy-guidelines')
        [Console]::Error.WriteLine('복구 확인: powershell -NoProfile -ExecutionPolicy Bypass -File .agents/scripts/setup/check-agent-tooling.ps1 -Check')
    }
    if ($States.superpowers -in @("disabled", "broken"))
    {
        Write-RecoveryPrerequisites -ToolId "superpowers" -State $States.superpowers
        [Console]::Error.WriteLine('Superpowers 복구 1: $CodexRoot = if ([string]::IsNullOrWhiteSpace($env:CODEX_HOME)) { Join-Path $HOME ".codex" } else { $env:CODEX_HOME }')
        [Console]::Error.WriteLine('Superpowers 복구 2: $SuperpowersRoot = Join-Path $CodexRoot "superpowers"; $SkillsRoot = Join-Path $HOME ".agents/skills"')
        [Console]::Error.WriteLine('Superpowers 복구 3: git clone https://github.com/obra/superpowers.git $SuperpowersRoot; New-Item -ItemType Directory -Path $SkillsRoot -Force')
        [Console]::Error.WriteLine('Superpowers 복구 4: $LinkType = if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) { "Junction" } else { "SymbolicLink" }; New-Item -ItemType $LinkType -Path (Join-Path $SkillsRoot "superpowers") -Target (Join-Path $SuperpowersRoot "skills")')
        [Console]::Error.WriteLine('복구 확인: powershell -NoProfile -ExecutionPolicy Bypass -File .agents/scripts/setup/check-agent-tooling.ps1 -Check')
    }
    if ($States.understand_anything -in @("disabled", "broken"))
    {
        Write-RecoveryPrerequisites -ToolId "understand_anything" -State $States.understand_anything
        [Console]::Error.WriteLine('Understand-Anything 복구 1: $UnderstandRoot = Join-Path $HOME ".understand-anything/repo"')
        [Console]::Error.WriteLine('Understand-Anything 복구 2: git clone https://github.com/Egonex-AI/Understand-Anything.git $UnderstandRoot')
        [Console]::Error.WriteLine('Understand-Anything 복구 3: & (Get-Process -Id $PID).Path -NoProfile -ExecutionPolicy Bypass -File (Join-Path $UnderstandRoot "install.ps1") codex')
        [Console]::Error.WriteLine('복구 확인: powershell -NoProfile -ExecutionPolicy Bypass -File .agents/scripts/setup/check-agent-tooling.ps1 -Check')
    }
}

function Write-RecoveryPrerequisites
{
    param(
        [string]$ToolId,
        [string]$State
    )

    [Console]::Error.WriteLine("$ToolId $State 상태: 기존 설정과 설치 경로를 자동으로 덮어쓰지 않습니다.")
    if ($State -eq "disabled")
    {
        [Console]::Error.WriteLine('복구 준비 1: config.toml을 비파괴 백업한 뒤 대상 plugin@marketplace의 enabled = false를 enabled = true로 변경하십시오.')
    }
    else
    {
        [Console]::Error.WriteLine('복구 준비 1: config.toml을 비파괴 백업하고 malformed 설정 또는 중복 plugin@marketplace 항목을 먼저 교정하십시오.')
    }
    [Console]::Error.WriteLine('복구 준비 2: 기존 저장소·스킬 링크의 충돌 경로를 이동한 후 아래 설치 명령을 실행하십시오. 원본은 별도 백업 위치에 보존하십시오.')
}

function Install-KarpathyGuidelines
{
    param([string]$Repository)

    $Installer = Join-Path $CodexHome "skills/.system/skill-installer/scripts/install-skill-from-github.py"
    $SkillsRoot = Join-Path $CodexHome "skills"
    if (-not (Test-AgentToolingConfinedChildPath -Path $SkillsRoot -Root $CodexHome))
    {
        Throw-AgentToolingInstallFailure -Message "CODEX_HOME 밖으로 연결된 skills 경로에는 설치할 수 없습니다."
    }
    if ($null -eq (Get-Command -Name python3 -ErrorAction SilentlyContinue) -or -not (Test-Path -LiteralPath $Installer -PathType Leaf))
    {
        Throw-AgentToolingInstallFailure -Message "Codex 시스템 skill-installer를 찾을 수 없습니다."
    }
    & python3 $Installer --repo $Repository --path "skills/karpathy-guidelines"
    if ($LASTEXITCODE -ne 0)
    {
        Throw-AgentToolingInstallFailure -Message "Karpathy Guidelines 설치에 실패했습니다."
    }
    if (-not (Test-Path -LiteralPath (Join-Path $CodexHome "skills/karpathy-guidelines/SKILL.md") -PathType Leaf))
    {
        Throw-AgentToolingInstallFailure -Message "Karpathy Guidelines 설치 결과를 확인할 수 없습니다."
    }
}

function Install-Superpowers
{
    param([string]$Repository)

    if ($null -eq (Get-Command -Name git -ErrorAction SilentlyContinue))
    {
        Throw-AgentToolingInstallFailure -Message "Superpowers 설치에 필요한 git을 찾을 수 없습니다."
    }
    $RepoRoot = Join-Path $CodexHome "superpowers"
    $SkillsParent = Join-Path $UserHome ".agents/skills"
    $LinkPath = Join-Path $SkillsParent "superpowers"
    if (-not (Test-AgentToolingConfinedChildPath -Path $SkillsParent -Root $UserHome))
    {
        Throw-AgentToolingInstallFailure -Message "사용자 홈 밖으로 연결된 .agents/skills 경로에는 설치할 수 없습니다."
    }
    if ((Test-Path -LiteralPath $RepoRoot) -or (Test-Path -LiteralPath $LinkPath))
    {
        Throw-AgentToolingInstallFailure -Message "기존 Superpowers 저장소 또는 스킬 경로가 있어 자동 설치를 중단합니다."
    }
    New-Item -ItemType Directory -Path $CodexHome -Force | Out-Null
    $StagingRoot = Join-Path $CodexHome ".superpowers.install-$([Guid]::NewGuid().ToString('N'))"
    $MovedRepository = $false
    try
    {
        & git clone "https://github.com/$Repository.git" $StagingRoot
        if ($LASTEXITCODE -ne 0)
        {
            Throw-AgentToolingInstallFailure -Message "Superpowers 저장소 복제에 실패했습니다."
        }
        if (-not (Test-Path -LiteralPath (Join-Path $StagingRoot "skills/using-superpowers/SKILL.md") -PathType Leaf))
        {
            Throw-AgentToolingInstallFailure -Message "Superpowers 필수 스킬을 확인할 수 없습니다."
        }
        Move-Item -LiteralPath $StagingRoot -Destination $RepoRoot
        $MovedRepository = $true
        New-Item -ItemType Directory -Path $SkillsParent -Force | Out-Null
        $LinkType = if ($env:OS -eq "Windows_NT") { "Junction" } else { "SymbolicLink" }
        New-Item -ItemType $LinkType -Path $LinkPath -Target (Join-Path $RepoRoot "skills") | Out-Null
        if (-not (Test-SuperpowersRepoLink))
        {
            Throw-AgentToolingInstallFailure -Message "Superpowers 스킬 링크를 확인할 수 없습니다."
        }
    }
    catch
    {
        if (Test-Path -LiteralPath $StagingRoot) { Remove-Item -LiteralPath $StagingRoot -Recurse -Force -ErrorAction SilentlyContinue }
        if (Test-Path -LiteralPath $LinkPath) { Remove-Item -LiteralPath $LinkPath -Force -ErrorAction SilentlyContinue }
        if ($MovedRepository -and (Test-Path -LiteralPath $RepoRoot)) { Remove-Item -LiteralPath $RepoRoot -Recurse -Force -ErrorAction SilentlyContinue }
        if ($_.Exception.Data.Contains("AgentToolingExitCode")) { throw }
        Throw-AgentToolingInstallFailure -Message $_.Exception.Message
    }
}

function Install-UnderstandAnything
{
    param([string]$Repository)

    $RepoRoot = Join-Path $UserHome ".understand-anything/repo"
    $LinkPath = Join-Path $UserHome ".agents/skills/understand"
    $RepoParent = Split-Path -Parent $RepoRoot
    $SkillsParent = Join-Path $UserHome ".agents/skills"
    if (-not (Test-AgentToolingConfinedChildPath -Path $RepoParent -Root $UserHome) -or
        -not (Test-AgentToolingConfinedChildPath -Path $SkillsParent -Root $UserHome))
    {
        Throw-AgentToolingInstallFailure -Message "사용자 홈 밖으로 연결된 Understand 저장소 또는 스킬 경로에는 설치할 수 없습니다."
    }
    if ((Test-AgentToolingPathEntry -Path $RepoRoot) -or (Test-AgentToolingPathEntry -Path $LinkPath))
    {
        Throw-AgentToolingInstallFailure -Message "기존 Understand-Anything 저장소 또는 스킬 경로가 있어 자동 설치를 중단합니다."
    }
    if ($null -eq (Get-Command -Name git -ErrorAction SilentlyContinue))
    {
        Throw-AgentToolingInstallFailure -Message "Understand-Anything 설치에 필요한 git을 찾을 수 없습니다."
    }
    New-Item -ItemType Directory -Path $RepoParent -Force | Out-Null
    $StagingRoot = "$RepoRoot.staging-$([Guid]::NewGuid().ToString('N'))"
    try
    {
        & git clone "https://github.com/$Repository.git" $StagingRoot
        if ($LASTEXITCODE -ne 0)
        {
            Throw-AgentToolingInstallFailure -Message "Understand-Anything 저장소 복제에 실패했습니다."
        }
        $StagingInstaller = Join-Path $StagingRoot "install.ps1"
        if (-not (Test-Path -LiteralPath $StagingInstaller -PathType Leaf))
        {
            Throw-AgentToolingInstallFailure -Message "로컬 install.ps1을 찾을 수 없습니다."
        }
        Move-Item -LiteralPath $StagingRoot -Destination $RepoRoot
        $Installer = Join-Path $RepoRoot "install.ps1"
        $PowerShellHost = (Get-Process -Id $PID).Path
        & $PowerShellHost -NoProfile -ExecutionPolicy Bypass -File $Installer codex
        if ($LASTEXITCODE -ne 0 -or -not (Test-UnderstandRepoLink))
        {
            Throw-AgentToolingInstallFailure -Message "Understand-Anything 설치 또는 전역 링크 확인에 실패했습니다."
        }
    }
    catch
    {
        if (Test-Path -LiteralPath $StagingRoot) { Remove-Item -LiteralPath $StagingRoot -Recurse -Force -ErrorAction SilentlyContinue }
        $LinkItem = Get-Item -LiteralPath $LinkPath -Force -ErrorAction SilentlyContinue
        if ($null -ne $LinkItem -and ($LinkItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)
        {
            Remove-Item -LiteralPath $LinkPath -Force -ErrorAction SilentlyContinue
        }
        if (Test-Path -LiteralPath $RepoRoot) { Remove-Item -LiteralPath $RepoRoot -Recurse -Force -ErrorAction SilentlyContinue }
        if ($_.Exception.Data.Contains("AgentToolingExitCode")) { throw }
        Throw-AgentToolingInstallFailure -Message $_.Exception.Message
    }
}

function Invoke-AgentToolingMain
{
    try
    {
        Initialize-AgentToolingRoots
        $Tools = Read-AgentToolingConfig
        $States = Get-AgentToolStates -Tools $Tools
        if ($null -eq (Get-Command -Name codex -ErrorAction SilentlyContinue))
        {
            [Console]::Error.WriteLine("[에이전트 도구] Codex CLI를 찾을 수 없습니다.")
            Write-AgentToolStates -States $States
            return 1
        }

        if (-not $InstallMissing)
        {
            Write-CodexSandboxWarning
            Write-AgentToolStates -States $States
            if (Test-AllToolsInstalled -States $States) { return 0 } else { return 1 }
        }

        $HasNonMissingFailure = @($States.Values | Where-Object { $_ -in @("disabled", "broken") }).Count -gt 0
        if ($HasNonMissingFailure)
        {
            Write-RecoveryGuidance -States $States
            Write-AgentToolStates -States $States
            return 1
        }
        if ($States.karpathy_guidelines -eq "missing")
        {
            Install-KarpathyGuidelines -Repository $Tools.karpathy_guidelines.Repository
        }
        if ($States.superpowers -eq "missing")
        {
            Install-Superpowers -Repository $Tools.superpowers.Repository
        }
        if ($States.understand_anything -eq "missing")
        {
            Install-UnderstandAnything -Repository $Tools.understand_anything.Repository
        }
        $States = Get-AgentToolStates -Tools $Tools
        Write-AgentToolStates -States $States
        if (Test-AllToolsInstalled -States $States) { return 0 }
        Throw-AgentToolingInstallFailure -Message "설치 후 필수 도구 상태를 확인할 수 없습니다."
    }
    catch
    {
        [Console]::Error.WriteLine("[에이전트 도구] $($_.Exception.Message)")
        if ($_.Exception.Data.Contains("AgentToolingExitCode"))
        {
            return [int]$_.Exception.Data["AgentToolingExitCode"]
        }
        return 2
    }
}

exit (Invoke-AgentToolingMain)
