# ==============================================================================
# [기능]: Unity 하네스 프로젝트 프로필을 안전하게 읽고 검증하며 기록합니다.
# [작성자]: 윤승종
# ==============================================================================

Set-StrictMode -Version Latest

$script:HarnessProfileCleanupAction = $null

function Get-HarnessUtf8Encoding
{
    return New-Object System.Text.UTF8Encoding($false, $true)
}

function Read-HarnessUtf8Lines
{
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf))
    {
        throw "파일을 읽을 수 없습니다: $Path"
    }

    $Bytes = [System.IO.File]::ReadAllBytes($Path)
    if ($Bytes.Length -ge 3 -and $Bytes[0] -eq 0xEF -and $Bytes[1] -eq 0xBB -and $Bytes[2] -eq 0xBF)
    {
        throw "설정 파일에 UTF-8 BOM을 사용할 수 없습니다: $Path"
    }

    try
    {
        return [System.IO.File]::ReadAllLines($Path, (Get-HarnessUtf8Encoding))
    }
    catch
    {
        throw "UTF-8 파일을 읽을 수 없습니다: $Path - $($_.Exception.Message)"
    }
}

function Test-HarnessIgnoredLine
{
    param([string]$Line)

    if ([string]::IsNullOrWhiteSpace($Line))
    {
        return $true
    }

    return $Line.TrimStart().StartsWith("#", [System.StringComparison]::Ordinal)
}

function Read-HarnessProfileSchema
{
    param(
        [Parameter(Mandatory = $true)]
        [string]$SchemaPath
    )

    $Schema = [ordered]@{}
    foreach ($Line in (Read-HarnessUtf8Lines -Path $SchemaPath))
    {
        if (Test-HarnessIgnoredLine -Line $Line)
        {
            continue
        }

        $Parts = $Line.Split([char]'|')
        if ($Parts.Length -ne 5)
        {
            throw "스키마 행 형식이 올바르지 않습니다: $Line"
        }

        $Key = $Parts[0]
        if ([string]::IsNullOrEmpty($Key) -or $Schema.Contains($Key))
        {
            throw "스키마 키가 비어 있거나 중복되었습니다: $Key"
        }
        if (@("required", "optional") -notcontains $Parts[1])
        {
            throw "스키마 필수 여부가 올바르지 않습니다: $Key"
        }
        if (@("single", "multiple") -notcontains $Parts[2])
        {
            throw "스키마 반복 여부가 올바르지 않습니다: $Key"
        }
        if (@("enum", "text", "path") -notcontains $Parts[3])
        {
            throw "스키마 값 형식이 올바르지 않습니다: $Key"
        }

        $AllowedValues = New-Object 'System.Collections.Generic.List[string]'
        if (-not [string]::IsNullOrEmpty($Parts[4]))
        {
            foreach ($AllowedValue in $Parts[4].Split([char]','))
            {
                [void]$AllowedValues.Add($AllowedValue)
            }
        }

        $Schema[$Key] = [PSCustomObject]@{
            Required = $Parts[1]
            Cardinality = $Parts[2]
            Type = $Parts[3]
            Allowed = $AllowedValues
        }
    }

    if ($Schema.Count -eq 0)
    {
        throw "스키마에 정의된 키가 없습니다: $SchemaPath"
    }

    return $Schema
}

function Test-HarnessProfile
{
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Profile,

        [Parameter(Mandatory = $true)]
        [string]$SchemaPath
    )

    $Schema = Read-HarnessProfileSchema -SchemaPath $SchemaPath
    foreach ($Key in $Profile.Keys)
    {
        if (-not $Schema.Contains($Key))
        {
            throw "스키마에 없는 키입니다: $Key"
        }

        $Definition = $Schema[$Key]
        $Values = @($Profile[$Key])
        if ($Definition.Cardinality -eq "single" -and $Values.Count -ne 1)
        {
            throw "한 번만 사용할 수 있는 키가 중복되었습니다: $Key"
        }
        if ($Definition.Cardinality -eq "multiple" -and $Profile[$Key] -isnot [System.Collections.Generic.List[string]])
        {
            throw "반복 키는 List[string]으로 보존되어야 합니다: $Key"
        }

        foreach ($ValueObject in $Values)
        {
            $Value = [string]$ValueObject
            if ($Value.IndexOf([char]13) -ge 0 -or $Value.IndexOf([char]10) -ge 0)
            {
                throw "프로필 값에는 줄바꿈을 사용할 수 없습니다: $Key"
            }
            if ($Definition.Type -eq "enum" -and -not $Definition.Allowed.Contains($Value))
            {
                throw "허용되지 않은 값입니다: $Key=$Value"
            }
        }
    }

    foreach ($Key in $Schema.Keys)
    {
        if ($Schema[$Key].Required -eq "required" -and -not $Profile.Contains($Key))
        {
            throw "필수 키가 누락되었습니다: $Key"
        }
    }

    return $true
}

function Read-HarnessProfile
{
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProfilePath,

        [Parameter(Mandatory = $true)]
        [string]$SchemaPath
    )

    $Schema = Read-HarnessProfileSchema -SchemaPath $SchemaPath
    $Profile = [ordered]@{}
    foreach ($Line in (Read-HarnessUtf8Lines -Path $ProfilePath))
    {
        if (Test-HarnessIgnoredLine -Line $Line)
        {
            continue
        }

        $SeparatorIndex = $Line.IndexOf([char]'=')
        if ($SeparatorIndex -lt 1)
        {
            throw "프로필 행에 등호가 없거나 키가 비어 있습니다: $Line"
        }

        $Key = $Line.Substring(0, $SeparatorIndex)
        $Value = $Line.Substring($SeparatorIndex + 1)
        if (-not $Schema.Contains($Key))
        {
            throw "스키마에 없는 키입니다: $Key"
        }

        if ($Schema[$Key].Cardinality -eq "multiple")
        {
            if (-not $Profile.Contains($Key))
            {
                $Profile[$Key] = New-Object 'System.Collections.Generic.List[string]'
            }
            [void]$Profile[$Key].Add($Value)
        }
        else
        {
            if ($Profile.Contains($Key))
            {
                throw "한 번만 사용할 수 있는 키가 중복되었습니다: $Key"
            }
            $Profile[$Key] = $Value
        }
    }

    [void](Test-HarnessProfile -Profile $Profile -SchemaPath $SchemaPath)
    return $Profile
}

function Get-HarnessProfileLines
{
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Profile,

        [Parameter(Mandatory = $true)]
        [string]$SchemaPath
    )

    [void](Test-HarnessProfile -Profile $Profile -SchemaPath $SchemaPath)
    $Schema = Read-HarnessProfileSchema -SchemaPath $SchemaPath
    $Lines = New-Object 'System.Collections.Generic.List[string]'
    foreach ($Key in $Schema.Keys)
    {
        if (-not $Profile.Contains($Key))
        {
            continue
        }

        foreach ($Value in @($Profile[$Key]))
        {
            [void]$Lines.Add("$Key=$([string]$Value)")
        }
    }
    return $Lines
}

function Test-HarnessReparsePoint
{
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path))
    {
        return $false
    }

    $Item = Get-Item -LiteralPath $Path -Force
    return (($Item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)
}

function Get-HarnessProfileCanonicalPath
{
    param([string]$Path)

    $FullPath = [System.IO.Path]::GetFullPath($Path)
    $Root = [System.IO.Path]::GetPathRoot($FullPath)
    $Current = [System.IO.Path]::GetFullPath($Root)
    $Remainder = $FullPath.Substring($Root.Length)
    [char[]]$Separators = @([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    foreach ($Segment in @($Remainder.Split($Separators, [System.StringSplitOptions]::RemoveEmptyEntries)))
    {
        $Candidate = Join-Path $Current $Segment
        if (-not (Test-Path -LiteralPath $Candidate))
        {
            $Current = [System.IO.Path]::GetFullPath($Candidate)
            continue
        }

        $Item = Get-Item -LiteralPath $Candidate -Force -ErrorAction Stop
        if (($Item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -eq 0)
        {
            $Current = [System.IO.Path]::GetFullPath($Item.FullName)
            continue
        }

        $TargetProperty = $Item.PSObject.Properties["Target"]
        if ($null -eq $TargetProperty)
        {
            $TargetProperty = $Item.PSObject.Properties["LinkTarget"]
        }
        $TargetValues = if ($null -eq $TargetProperty) { @() } else { @($TargetProperty.Value) }
        if ($TargetValues.Count -eq 0 -or [string]::IsNullOrEmpty([string]$TargetValues[0]))
        {
            throw "재파싱 지점의 실제 대상을 확인할 수 없습니다: $Candidate"
        }

        $Target = [string]$TargetValues[0]
        if (-not [System.IO.Path]::IsPathRooted($Target))
        {
            $Target = Join-Path (Split-Path -Parent $Candidate) $Target
        }
        $Current = [System.IO.Path]::GetFullPath($Target)
    }

    return [System.IO.Path]::GetFullPath($Current)
}

function Test-HarnessReparseAncestor
{
    param([string]$Path)

    # 조상 전체를 거부하지 않고 출력 엔트리 자체만 보호합니다.
    return Test-HarnessReparsePoint -Path $Path
}

function Get-HarnessProfilePathComparison
{
    if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT)
    {
        return [System.StringComparison]::OrdinalIgnoreCase
    }

    return [System.StringComparison]::Ordinal
}

function Write-HarnessProfile
{
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Profile,

        [Parameter(Mandatory = $true)]
        [string]$SchemaPath,

        [Parameter(Mandatory = $true)]
        [string]$OutputPath
    )

    $LexicalOutputPath = [System.IO.Path]::GetFullPath($OutputPath)
    if (Test-HarnessReparsePoint -Path $LexicalOutputPath)
    {
        throw "프로필 출력 엔트리로 재파싱 지점을 사용할 수 없습니다: $OutputPath"
    }
    $FullOutputPath = Get-HarnessProfileCanonicalPath -Path $LexicalOutputPath
    $FullSchemaPath = Get-HarnessProfileCanonicalPath -Path $SchemaPath
    if ([string]::Equals($FullOutputPath, $FullSchemaPath, (Get-HarnessProfilePathComparison)))
    {
        throw "스키마 파일을 프로필 출력 대상으로 사용할 수 없습니다: $OutputPath"
    }

    $DirectoryPath = Split-Path -Parent $FullOutputPath
    if ([string]::IsNullOrEmpty($DirectoryPath) -or -not (Test-Path -LiteralPath $DirectoryPath -PathType Container))
    {
        throw "프로필 출력 디렉터리를 찾을 수 없습니다: $DirectoryPath"
    }
    if (Test-Path -LiteralPath $FullOutputPath -PathType Container)
    {
        throw "프로필 출력 경로로 디렉터리를 사용할 수 없습니다: $OutputPath"
    }

    $Lines = Get-HarnessProfileLines -Profile $Profile -SchemaPath $SchemaPath
    $TemporaryPath = Join-Path $DirectoryPath ("." + [System.IO.Path]::GetFileName($FullOutputPath) + ".tmp." + [Guid]::NewGuid().ToString("N"))
    $BackupPath = $TemporaryPath + ".backup"
    $ExistingAcl = $null
    if (Test-Path -LiteralPath $FullOutputPath -PathType Leaf)
    {
        try
        {
            $ExistingAcl = Get-Acl -LiteralPath $FullOutputPath
        }
        catch
        {
            $ExistingAcl = $null
        }
    }

    try
    {
        [System.IO.File]::WriteAllLines($TemporaryPath, [string[]]$Lines, (Get-HarnessUtf8Encoding))
        if ($null -ne $ExistingAcl)
        {
            try
            {
                Set-Acl -LiteralPath $TemporaryPath -AclObject $ExistingAcl
            }
            catch
            {
                # 플랫폼이 ACL 복제를 지원하지 않으면 기본 권한을 유지합니다.
            }
        }

        if (Test-Path -LiteralPath $FullOutputPath -PathType Leaf)
        {
            [System.IO.File]::Replace($TemporaryPath, $FullOutputPath, $BackupPath, $true)
            if (Test-Path -LiteralPath $BackupPath)
            {
                try
                {
                    if ($null -ne $script:HarnessProfileCleanupAction)
                    {
                        & $script:HarnessProfileCleanupAction $BackupPath
                    }
                    else
                    {
                        Remove-Item -LiteralPath $BackupPath -Force -ErrorAction Stop
                    }
                }
                catch
                {
                    # 교체는 이미 커밋되었으므로 백업 정리 실패를 쓰기 실패로 되돌리지 않습니다.
                }
            }
        }
        else
        {
            [System.IO.File]::Move($TemporaryPath, $FullOutputPath)
        }
    }
    catch
    {
        throw "프로필을 원자적으로 기록할 수 없습니다: $OutputPath - $($_.Exception.Message)"
    }
    finally
    {
        if (Test-Path -LiteralPath $TemporaryPath)
        {
            Remove-Item -LiteralPath $TemporaryPath -Force -ErrorAction SilentlyContinue
        }
        if (Test-Path -LiteralPath $BackupPath)
        {
            Remove-Item -LiteralPath $BackupPath -Force -ErrorAction SilentlyContinue
        }
    }
}

function Confirm-HarnessProfile
{
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProfilePath,

        [Parameter(Mandatory = $true)]
        [string]$SchemaPath
    )

    $Profile = Read-HarnessProfile -ProfilePath $ProfilePath -SchemaPath $SchemaPath
    if ([string]$Profile["confirmation_status"] -eq "confirmed")
    {
        return $Profile
    }

    $Profile["confirmation_status"] = "confirmed"
    [void](Test-HarnessProfile -Profile $Profile -SchemaPath $SchemaPath)
    Write-HarnessProfile -Profile $Profile -SchemaPath $SchemaPath -OutputPath $ProfilePath
    return $Profile
}
