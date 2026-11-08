# ==============================================================================
# [기능]: Unity 하네스 프로필에 따라 C# 소스를 읽기 전용으로 검사합니다.
# [작성자]: 윤승종
# ==============================================================================

Set-StrictMode -Version Latest

$script:HarnessDefaultExcludeRoots = @(
    "Library", "Temp", "Logs", "obj", "UserSettings", "Packages", ".git", ".agents", ".agents-backup",
    "Assets/Plugins", "Assets/ThirdParty"
)
$script:HarnessLintFileReader = $null
$script:HarnessLintInternalFailure = $false

# 기계 출력 계약: RULE_ID|severity|path|line|message
$script:HarnessLintRuleIds = @(
    "CONFIG001", "PATH001", "SOLID001", "PERF001", "PERF002", "UNITYNULL001", "MVVM001", "MVP001",
    "MVC001", "LAYER001", "VCONTAINER001", "UNITASK001", "DOTWEEN001", "STYLE001", "DOC001"
)
$script:HarnessLinqInUpdatePattern = '\.(?:Where|Select|SelectMany|Distinct|OrderBy|OrderByDescending|ThenBy|GroupBy|ToList|ToArray|Any|All|First|FirstOrDefault|Single|SingleOrDefault|Count)\s*\(|(?:^|[^A-Za-z0-9_])Enumerable\.'
$script:HarnessAllocationInUpdatePattern = '(?:^|[^A-Za-z0-9_])new(?:\s*\(|\s+(?!(?:Vector2|Vector3|Vector4|Quaternion|Color|Color32|Rect|Bounds|Ray|Plane|Matrix4x4)\s*\()[A-Za-z_][A-Za-z0-9_.<>]*)'

function New-HarnessLintResult
{
    param(
        [int]$ExitCode,
        [string[]]$Output
    )

    return [PSCustomObject]@{
        ExitCode = $ExitCode
        Output = @($Output)
    }
}

function ConvertTo-HarnessMachineField
{
    param([object]$Value)

    $Text = [string]$Value
    $Text = $Text.Replace("%", "%25")
    $Text = $Text.Replace("|", "%7C")
    $Text = $Text.Replace([string][char]13, "%0D")
    $Text = $Text.Replace([string][char]10, "%0A")
    return $Text
}

function Add-HarnessLintDiagnostic
{
    param(
        [System.Collections.Generic.List[string]]$Diagnostics,
        [string]$RuleId,
        [string]$Severity,
        [string]$Path,
        [int]$Line,
        [string]$Message
    )

    if ($script:HarnessLintRuleIds -notcontains $RuleId)
    {
        throw "등록되지 않은 린트 규칙 ID입니다: $RuleId"
    }
    $Fields = @(
        (ConvertTo-HarnessMachineField -Value $RuleId),
        (ConvertTo-HarnessMachineField -Value $Severity),
        (ConvertTo-HarnessMachineField -Value $Path),
        (ConvertTo-HarnessMachineField -Value $Line),
        (ConvertTo-HarnessMachineField -Value $Message)
    )
    [void]$Diagnostics.Add([string]::Join("|", $Fields))
}

function Get-HarnessLintSeverity
{
    param(
        [string]$ConfirmationStatus,
        [string]$DefaultSeverity,
        [bool]$IsProfileRule
    )

    if ($IsProfileRule -and $ConfirmationStatus -eq "pending" -and $DefaultSeverity -eq "error")
    {
        return "warning"
    }
    return $DefaultSeverity
}

function Get-HarnessLintPathComparison
{
    if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT)
    {
        return [System.StringComparison]::OrdinalIgnoreCase
    }

    return [System.StringComparison]::Ordinal
}

function Get-HarnessLintPathComparer
{
    if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT)
    {
        return [System.StringComparer]::OrdinalIgnoreCase
    }

    return [System.StringComparer]::Ordinal
}

function Get-HarnessLintCanonicalPath
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

function Test-HarnessLintPathBelow
{
    param(
        [string]$Root,
        [string]$Path
    )

    $FullRoot = (Get-HarnessLintCanonicalPath -Path $Root).TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar)
    $FullPath = Get-HarnessLintCanonicalPath -Path $Path
    $Comparison = Get-HarnessLintPathComparison
    if ($FullPath.Equals($FullRoot, $Comparison))
    {
        return $true
    }
    return $FullPath.StartsWith($FullRoot + [System.IO.Path]::DirectorySeparatorChar, $Comparison)
}

function Get-HarnessLintRelativePath
{
    param(
        [string]$ProjectRoot,
        [string]$Path
    )

    $FullRoot = (Get-HarnessLintCanonicalPath -Path $ProjectRoot).TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar)
    $FullPath = Get-HarnessLintCanonicalPath -Path $Path
    if (-not (Test-HarnessLintPathBelow -Root $FullRoot -Path $FullPath))
    {
        throw "프로젝트 경계 밖의 경로입니다: $Path"
    }
    if ($FullPath.Length -eq $FullRoot.Length)
    {
        return "."
    }
    return $FullPath.Substring($FullRoot.Length + 1).Replace([System.IO.Path]::DirectorySeparatorChar, [char]'/')
}

function Get-HarnessLintBoundary
{
    param(
        [string]$ProjectRoot,
        [string]$ConfiguredPath
    )

    $FullRoot = (Get-HarnessLintCanonicalPath -Path $ProjectRoot).TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar)
    $Candidate = if ([System.IO.Path]::IsPathRooted($ConfiguredPath)) {
        Get-HarnessLintCanonicalPath -Path $ConfiguredPath
    } else {
        Get-HarnessLintCanonicalPath -Path (Join-Path $FullRoot $ConfiguredPath)
    }
    if (-not (Test-HarnessLintPathBelow -Root $FullRoot -Path $Candidate))
    {
        return $null
    }
    return $Candidate
}

function Test-HarnessLintExcluded
{
    param(
        [string]$FilePath,
        [string[]]$ExcludePaths
    )

    foreach ($ExcludePath in $ExcludePaths)
    {
        if (Test-HarnessLintPathBelow -Root $ExcludePath -Path $FilePath)
        {
            return $true
        }
    }
    return $false
}

function Get-HarnessLintFiles
{
    param(
        [string]$SourcePath,
        [string[]]$ExcludePaths,
        [ValidateSet('*.cs', '*.asmdef')]
        [string]$Pattern = '*.cs'
    )

    $Comparer = Get-HarnessLintPathComparer
    $VisitedDirectories = New-Object 'System.Collections.Generic.HashSet[string]' -ArgumentList (, $Comparer)
    $VisitedFiles = New-Object 'System.Collections.Generic.HashSet[string]' -ArgumentList (, $Comparer)
    $PendingDirectories = New-Object 'System.Collections.Generic.Stack[string]'
    $Files = New-Object 'System.Collections.Generic.List[System.IO.FileInfo]'
    $PendingDirectories.Push((Get-HarnessLintCanonicalPath -Path $SourcePath))
    while ($PendingDirectories.Count -gt 0)
    {
        $DirectoryPath = $PendingDirectories.Pop()
        if (-not $VisitedDirectories.Add($DirectoryPath) -or (Test-HarnessLintExcluded -FilePath $DirectoryPath -ExcludePaths $ExcludePaths))
        {
            continue
        }

        foreach ($ChildDirectoryPath in [System.IO.Directory]::EnumerateDirectories($DirectoryPath))
        {
            $ChildItem = Get-Item -LiteralPath $ChildDirectoryPath -Force -ErrorAction Stop
            if (($ChildItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)
            {
                continue
            }

            $CanonicalChildPath = Get-HarnessLintCanonicalPath -Path $ChildItem.FullName
            if (-not (Test-HarnessLintExcluded -FilePath $CanonicalChildPath -ExcludePaths $ExcludePaths))
            {
                $PendingDirectories.Push($CanonicalChildPath)
            }
        }

        foreach ($FilePath in [System.IO.Directory]::EnumerateFiles($DirectoryPath, $Pattern))
        {
            $FileItem = Get-Item -LiteralPath $FilePath -Force -ErrorAction Stop
            if (($FileItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)
            {
                continue
            }
            $CanonicalFilePath = Get-HarnessLintCanonicalPath -Path $FileItem.FullName
            if (-not (Test-HarnessLintExcluded -FilePath $CanonicalFilePath -ExcludePaths $ExcludePaths) -and
                $VisitedFiles.Add($CanonicalFilePath))
            {
                [void]$Files.Add((Get-Item -LiteralPath $CanonicalFilePath -Force -ErrorAction Stop))
            }
        }
    }

    return @($Files | Sort-Object FullName)
}

function Get-HarnessLintLineNumber
{
    param(
        [string[]]$Lines,
        [string]$Pattern
    )

    for ($Index = 0; $Index -lt $Lines.Length; $Index++)
    {
        if ($Lines[$Index] -match $Pattern)
        {
            return $Index + 1
        }
    }
    return 1
}

function ConvertTo-HarnessSanitizedCSharp
{
    param([string]$Content)

    $Builder = New-Object System.Text.StringBuilder -ArgumentList $Content.Length
    $Contexts = New-Object 'System.Collections.Generic.Stack[object]'
    $Mode = "code"
    $StringKind = ""
    $IsInterpolated = $false
    $RawQuoteCount = 0
    $RawBraceCount = 0
    $Index = 0
    while ($Index -lt $Content.Length)
    {
        $Character = $Content[$Index]
        $NextCharacter = if ($Index + 1 -lt $Content.Length) { $Content[$Index + 1] } else { [char]0 }
        $IsLineBreak = $Character -eq [char]10 -or $Character -eq [char]13

        if ($Mode -eq "line_comment")
        {
            if ($IsLineBreak)
            {
                [void]$Builder.Append($Character)
                $Mode = "code"
            }
            else
            {
                [void]$Builder.Append(' ')
            }
            $Index++
            continue
        }
        if ($Mode -eq "block_comment")
        {
            if ($Character -eq '*' -and $NextCharacter -eq '/')
            {
                [void]$Builder.Append("  ")
                $Index += 2
                $Mode = "code"
            }
            else
            {
                [void]$Builder.Append($(if ($IsLineBreak) { $Character } else { ' ' }))
                $Index++
            }
            continue
        }
        if ($Mode -eq "character")
        {
            if ($Character -eq [char]92 -and $Index + 1 -lt $Content.Length)
            {
                [void]$Builder.Append("  ")
                $Index += 2
            }
            else
            {
                [void]$Builder.Append($(if ($IsLineBreak) { $Character } else { ' ' }))
                $Index++
                if ($Character -eq "'")
                {
                    $Mode = "code"
                }
            }
            continue
        }
        if ($Mode -eq "string")
        {
            if ($StringKind -eq "raw")
            {
                if ($Character -eq '"')
                {
                    $QuoteRun = 0
                    while ($Index + $QuoteRun -lt $Content.Length -and $Content[$Index + $QuoteRun] -eq '"')
                    {
                        $QuoteRun++
                    }
                    if ($QuoteRun -ge $RawQuoteCount)
                    {
                        [void]$Builder.Append(''.PadRight($QuoteRun))
                        $Index += $QuoteRun
                        $Mode = "code"
                        continue
                    }
                }
                if ($IsInterpolated -and $Character -eq '{')
                {
                    $BraceRun = 0
                    while ($Index + $BraceRun -lt $Content.Length -and $Content[$Index + $BraceRun] -eq '{')
                    {
                        $BraceRun++
                    }
                    if ($BraceRun -ge $RawBraceCount)
                    {
                        $Contexts.Push([PSCustomObject]@{
                            Kind = $StringKind
                            IsInterpolated = $IsInterpolated
                            RawQuoteCount = $RawQuoteCount
                            RawBraceCount = $RawBraceCount
                            Depth = 1
                            CloseBraces = $RawBraceCount
                            ParenthesisDepth = 0
                            BracketDepth = 0
                            TernaryDepth = 0
                            InClause = $false
                        })
                        [void]$Builder.Append(''.PadRight($RawBraceCount))
                        $Index += $RawBraceCount
                        $Mode = "code"
                        continue
                    }
                }

                [void]$Builder.Append($(if ($IsLineBreak) { $Character } else { ' ' }))
                $Index++
                continue
            }

            if ($IsInterpolated -and
                (($Character -eq '{' -and $NextCharacter -eq '{') -or ($Character -eq '}' -and $NextCharacter -eq '}')))
            {
                [void]$Builder.Append("  ")
                $Index += 2
                continue
            }
            if ($IsInterpolated -and $Character -eq '{')
            {
                $Contexts.Push([PSCustomObject]@{
                    Kind = $StringKind
                    IsInterpolated = $IsInterpolated
                    RawQuoteCount = 0
                    RawBraceCount = 1
                    Depth = 1
                    CloseBraces = 1
                    ParenthesisDepth = 0
                    BracketDepth = 0
                    TernaryDepth = 0
                    InClause = $false
                })
                [void]$Builder.Append(' ')
                $Index++
                $Mode = "code"
                continue
            }
            if ($StringKind -eq "verbatim" -and $Character -eq '"' -and $NextCharacter -eq '"')
            {
                [void]$Builder.Append("  ")
                $Index += 2
                continue
            }
            if ($StringKind -eq "regular" -and $Character -eq [char]92 -and $Index + 1 -lt $Content.Length)
            {
                [void]$Builder.Append("  ")
                $Index += 2
                continue
            }
            if ($Character -eq '"')
            {
                [void]$Builder.Append(' ')
                $Index++
                $Mode = "code"
                continue
            }

            [void]$Builder.Append($(if ($IsLineBreak) { $Character } else { ' ' }))
            $Index++
            continue
        }

        if ($Contexts.Count -gt 0)
        {
            $Context = $Contexts.Peek()
            if ([bool]$Context.InClause)
            {
                $ClosingRun = 0
                if ($Character -eq '}')
                {
                    while ($Index + $ClosingRun -lt $Content.Length -and $Content[$Index + $ClosingRun] -eq '}')
                    {
                        $ClosingRun++
                    }
                }
                if ($ClosingRun -ge [int]$Context.CloseBraces)
                {
                    [void]$Builder.Append(''.PadRight([int]$Context.CloseBraces))
                    $Index += [int]$Context.CloseBraces
                    $Restored = $Contexts.Pop()
                    $StringKind = [string]$Restored.Kind
                    $IsInterpolated = [bool]$Restored.IsInterpolated
                    $RawQuoteCount = [int]$Restored.RawQuoteCount
                    $RawBraceCount = [int]$Restored.RawBraceCount
                    $Mode = "string"
                }
                else
                {
                    [void]$Builder.Append($(if ($IsLineBreak) { $Character } else { ' ' }))
                    $Index++
                }
                continue
            }
            if ($Character -eq '{')
            {
                $Context.Depth = [int]$Context.Depth + 1
                [void]$Builder.Append($Character)
                $Index++
                continue
            }
            if ($Character -eq '}')
            {
                if ([int]$Context.Depth -gt 1)
                {
                    $Context.Depth = [int]$Context.Depth - 1
                    [void]$Builder.Append($Character)
                    $Index++
                    continue
                }

                $ClosingRun = 0
                while ($Index + $ClosingRun -lt $Content.Length -and $Content[$Index + $ClosingRun] -eq '}')
                {
                    $ClosingRun++
                }
                if ($ClosingRun -ge [int]$Context.CloseBraces)
                {
                    [void]$Builder.Append(''.PadRight([int]$Context.CloseBraces))
                    $Index += [int]$Context.CloseBraces
                    $Restored = $Contexts.Pop()
                    $StringKind = [string]$Restored.Kind
                    $IsInterpolated = [bool]$Restored.IsInterpolated
                    $RawQuoteCount = [int]$Restored.RawQuoteCount
                    $RawBraceCount = [int]$Restored.RawBraceCount
                    $Mode = "string"
                    continue
                }
            }

            if ($Character -eq '(')
            {
                $Context.ParenthesisDepth = [int]$Context.ParenthesisDepth + 1
            }
            elseif ($Character -eq ')' -and [int]$Context.ParenthesisDepth -gt 0)
            {
                $Context.ParenthesisDepth = [int]$Context.ParenthesisDepth - 1
            }
            elseif ($Character -eq '[')
            {
                $Context.BracketDepth = [int]$Context.BracketDepth + 1
            }
            elseif ($Character -eq ']' -and [int]$Context.BracketDepth -gt 0)
            {
                $Context.BracketDepth = [int]$Context.BracketDepth - 1
            }
            elseif ([int]$Context.Depth -eq 1 -and [int]$Context.ParenthesisDepth -eq 0 -and [int]$Context.BracketDepth -eq 0)
            {
                if ($Character -eq '?' -and $NextCharacter -ne '?' -and $NextCharacter -ne '.' -and $NextCharacter -ne '[')
                {
                    $Context.TernaryDepth = [int]$Context.TernaryDepth + 1
                }
                elseif ($Character -eq ':' -and
                    ($Index -eq 0 -or $Content[$Index - 1] -ne ':') -and $NextCharacter -ne ':')
                {
                    if ([int]$Context.TernaryDepth -gt 0)
                    {
                        $Context.TernaryDepth = [int]$Context.TernaryDepth - 1
                    }
                    else
                    {
                        $Context.InClause = $true
                        [void]$Builder.Append(' ')
                        $Index++
                        continue
                    }
                }
                elseif ($Character -eq ',' -and [int]$Context.TernaryDepth -eq 0)
                {
                    $Context.InClause = $true
                    [void]$Builder.Append(' ')
                    $Index++
                    continue
                }
            }
        }

        if ($Character -eq '/' -and $NextCharacter -eq '/')
        {
            [void]$Builder.Append("  ")
            $Index += 2
            $Mode = "line_comment"
            continue
        }
        if ($Character -eq '/' -and $NextCharacter -eq '*')
        {
            [void]$Builder.Append("  ")
            $Index += 2
            $Mode = "block_comment"
            continue
        }
        if ($Character -eq "'")
        {
            [void]$Builder.Append(' ')
            $Index++
            $Mode = "character"
            continue
        }

        if ($Character -eq '$')
        {
            $DollarRun = 0
            while ($Index + $DollarRun -lt $Content.Length -and $Content[$Index + $DollarRun] -eq '$')
            {
                $DollarRun++
            }
            $QuoteRun = 0
            while ($Index + $DollarRun + $QuoteRun -lt $Content.Length -and $Content[$Index + $DollarRun + $QuoteRun] -eq '"')
            {
                $QuoteRun++
            }
            if ($QuoteRun -ge 3)
            {
                [void]$Builder.Append(''.PadRight(($DollarRun + $QuoteRun)))
                $Index += $DollarRun + $QuoteRun
                $Mode = "string"
                $StringKind = "raw"
                $IsInterpolated = $true
                $RawQuoteCount = $QuoteRun
                $RawBraceCount = $DollarRun
                continue
            }
        }
        if ($Character -eq '"')
        {
            $QuoteRun = 0
            while ($Index + $QuoteRun -lt $Content.Length -and $Content[$Index + $QuoteRun] -eq '"')
            {
                $QuoteRun++
            }
            if ($QuoteRun -ge 3)
            {
                [void]$Builder.Append(''.PadRight($QuoteRun))
                $Index += $QuoteRun
                $Mode = "string"
                $StringKind = "raw"
                $IsInterpolated = $false
                $RawQuoteCount = $QuoteRun
                $RawBraceCount = 0
                continue
            }
        }
        if ($Index + 2 -lt $Content.Length -and
            (($Content.Substring($Index, 3) -eq '$@"') -or ($Content.Substring($Index, 3) -eq '@$"')))
        {
            [void]$Builder.Append("   ")
            $Index += 3
            $Mode = "string"
            $StringKind = "verbatim"
            $IsInterpolated = $true
            continue
        }
        if ($Index + 1 -lt $Content.Length -and $Content.Substring($Index, 2) -eq '@"')
        {
            [void]$Builder.Append("  ")
            $Index += 2
            $Mode = "string"
            $StringKind = "verbatim"
            $IsInterpolated = $false
            continue
        }
        if ($Index + 1 -lt $Content.Length -and $Content.Substring($Index, 2) -eq '$"')
        {
            [void]$Builder.Append("  ")
            $Index += 2
            $Mode = "string"
            $StringKind = "regular"
            $IsInterpolated = $true
            continue
        }
        if ($Character -eq '"')
        {
            [void]$Builder.Append(' ')
            $Index++
            $Mode = "string"
            $StringKind = "regular"
            $IsInterpolated = $false
            continue
        }

        [void]$Builder.Append($Character)
        $Index++
    }

    return $Builder.ToString()
}

function Get-HarnessUpdateRanges
{
    param([string]$Content)

    $Ranges = New-Object 'System.Collections.Generic.List[object]'
    $DeclarationPattern = '\b(?:(?:public|private|protected|internal|static|virtual|override|abstract|sealed|async|extern|new|unsafe|partial)\s+)*void\s+(?:Update|LateUpdate|FixedUpdate)\s*\([^)]*\)\s*'
    foreach ($Match in [regex]::Matches($Content, $DeclarationPattern))
    {
        $BodyStart = $Match.Index + $Match.Length
        while ($BodyStart -lt $Content.Length -and [char]::IsWhiteSpace($Content[$BodyStart]))
        {
            $BodyStart++
        }
        if ($BodyStart + 1 -lt $Content.Length -and $Content.Substring($BodyStart, 2) -eq '=>')
        {
            $End = $Content.IndexOf([char]';', $BodyStart + 2)
            if ($End -ge 0)
            {
                [void]$Ranges.Add([PSCustomObject]@{ Start = $BodyStart + 2; End = $End })
            }
            continue
        }
        if ($BodyStart -ge $Content.Length -or $Content[$BodyStart] -ne '{')
        {
            continue
        }

        $Depth = 1
        $Cursor = $BodyStart + 1
        while ($Cursor -lt $Content.Length -and $Depth -gt 0)
        {
            if ($Content[$Cursor] -eq '{')
            {
                $Depth++
            }
            elseif ($Content[$Cursor] -eq '}')
            {
                $Depth--
            }
            $Cursor++
        }
        if ($Depth -eq 0)
        {
            [void]$Ranges.Add([PSCustomObject]@{ Start = $BodyStart + 1; End = $Cursor - 1 })
        }
    }

    return $Ranges
}

function Test-HarnessUpdateContains
{
    param(
        [string]$Content,
        [string]$Pattern
    )

    foreach ($Range in (Get-HarnessUpdateRanges -Content $Content))
    {
        $Length = [int]$Range.End - [int]$Range.Start
        if ($Length -gt 0 -and [regex]::IsMatch($Content.Substring([int]$Range.Start, $Length), $Pattern))
        {
            return $true
        }
    }
    return $false
}

function Get-HarnessUpdateMatchLineNumber
{
    param(
        [string]$Content,
        [string]$Pattern
    )

    foreach ($Range in (Get-HarnessUpdateRanges -Content $Content))
    {
        $Length = [int]$Range.End - [int]$Range.Start
        if ($Length -le 0)
        {
            continue
        }
        $Match = [regex]::Match($Content.Substring([int]$Range.Start, $Length), $Pattern)
        if ($Match.Success)
        {
            $AbsoluteIndex = [int]$Range.Start + $Match.Index
            return [regex]::Matches($Content.Substring(0, $AbsoluteIndex), "`n").Count + 1
        }
    }
    return 1
}

function Add-HarnessFileDiagnostics
{
    param(
        [System.Collections.Generic.List[string]]$Diagnostics,
        [System.IO.FileInfo]$File,
        [string]$ProjectRoot,
        [System.Collections.IDictionary]$Profile
    )

    $RelativePath = Get-HarnessLintRelativePath -ProjectRoot $ProjectRoot -Path $File.FullName
    try
    {
        if ($null -ne $script:HarnessLintFileReader)
        {
            $RawLines = @(& $script:HarnessLintFileReader $File.FullName)
        }
        else
        {
            $RawLines = [System.IO.File]::ReadAllLines($File.FullName, (Get-HarnessUtf8Encoding))
        }
    }
    catch
    {
        $script:HarnessLintInternalFailure = $true
        Add-HarnessLintDiagnostic -Diagnostics $Diagnostics -RuleId "PATH001" -Severity "error" -Path $RelativePath -Line 0 -Message "C# 파일을 읽을 수 없습니다"
        return
    }
    $RawContent = [string]::Join([Environment]::NewLine, $RawLines)
    $Content = ConvertTo-HarnessSanitizedCSharp -Content $RawContent
    $Lines = @($Content -split '\r?\n')
    $ConfirmationStatus = [string]$Profile["confirmation_status"]
    $Architecture = [string]$Profile["architecture"]

    if ($Content -match '\bpublic\s+static\s+[A-Za-z_][A-Za-z0-9_<>,.\[\]?]*\s+Instance\b')
    {
        $Line = Get-HarnessLintLineNumber -Lines $Lines -Pattern '\bpublic\s+static\s+.*\s+Instance\b'
        Add-HarnessLintDiagnostic -Diagnostics $Diagnostics -RuleId "SOLID001" -Severity "error" -Path $RelativePath -Line $Line -Message "public static Instance 싱글톤 사용이 의심됩니다"
    }
    if (Test-HarnessUpdateContains -Content $Content -Pattern $script:HarnessLinqInUpdatePattern)
    {
        $Line = Get-HarnessUpdateMatchLineNumber -Content $Content -Pattern $script:HarnessLinqInUpdatePattern
        Add-HarnessLintDiagnostic -Diagnostics $Diagnostics -RuleId "PERF001" -Severity "warning" -Path $RelativePath -Line $Line -Message "매 프레임 메서드에서 LINQ 사용이 감지되었습니다"
    }
    if (Test-HarnessUpdateContains -Content $Content -Pattern $script:HarnessAllocationInUpdatePattern)
    {
        $Line = Get-HarnessUpdateMatchLineNumber -Content $Content -Pattern $script:HarnessAllocationInUpdatePattern
        Add-HarnessLintDiagnostic -Diagnostics $Diagnostics -RuleId "PERF002" -Severity "warning" -Path $RelativePath -Line $Line -Message "매 프레임 메서드에서 참조 타입 할당이 의심됩니다"
    }
    if ($Content -match '\b(?:GameObject|Transform|Component|MonoBehaviour|ScriptableObject)\b[^;\r\n]*\?\.')
    {
        $Line = Get-HarnessLintLineNumber -Lines $Lines -Pattern '\?\.'
        Add-HarnessLintDiagnostic -Diagnostics $Diagnostics -RuleId "UNITYNULL001" -Severity "warning" -Path $RelativePath -Line $Line -Message "Unity Object Fake Null 오용이 의심됩니다"
    }

    $PrivatePrefix = [regex]::Escape([string]$Profile["private_field_prefix"])
    for ($Index = 0; $Index -lt $Lines.Length; $Index++)
    {
        if ($Lines[$Index] -match '^\s*private\s+(?:readonly\s+|static\s+|const\s+)*[A-Za-z_][A-Za-z0-9_<>,.\[\]?]*\s+([A-Za-z_][A-Za-z0-9_]*)\s*(?:[;=,])' -and $Matches[1] -notmatch ("^" + $PrivatePrefix))
        {
            Add-HarnessLintDiagnostic -Diagnostics $Diagnostics -RuleId "STYLE001" -Severity "warning" -Path $RelativePath -Line ($Index + 1) -Message "private 필드 접두사 규칙을 확인하십시오"
        }
    }

    if ([string]$Profile["xml_documentation_policy"] -eq "all_methods")
    {
        for ($Index = 0; $Index -lt $Lines.Length; $Index++)
        {
            if ($Lines[$Index] -match '^\s*(?:(?:public|private|protected|internal|static|async|virtual|override|abstract|sealed|extern|new|unsafe|partial)\s+)*[A-Za-z_][A-Za-z0-9_<>,.\[\]?]*\s+[A-Za-z_][A-Za-z0-9_]*(?:\s*<[^(){};]+>)?\s*\(')
            {
                $Previous = $Index - 1
                while ($Previous -ge 0 -and [string]::IsNullOrWhiteSpace($RawLines[$Previous]))
                {
                    $Previous--
                }
                if ($Previous -lt 0 -or -not $RawLines[$Previous].TrimStart().StartsWith("///"))
                {
                    Add-HarnessLintDiagnostic -Diagnostics $Diagnostics -RuleId "DOC001" -Severity "warning" -Path $RelativePath -Line ($Index + 1) -Message "프로필 XML 문서화 정책 위반이 의심됩니다"
                }
            }
        }
    }

    $IsView = $RelativePath -match '(?:^|/)Views?(?:/|$)' -or $Content -match '\bclass\s+\w*View\b'
    if ($Architecture -eq "mvvm" -and $IsView -and $Content -match '\b(?:using\s+[^;]*Models?|\w*Model\b)')
    {
        $Severity = Get-HarnessLintSeverity -ConfirmationStatus $ConfirmationStatus -DefaultSeverity "error" -IsProfileRule $true
        $Line = Get-HarnessLintLineNumber -Lines $Lines -Pattern '\b(?:Models?|Model)\b'
        Add-HarnessLintDiagnostic -Diagnostics $Diagnostics -RuleId "MVVM001" -Severity $Severity -Path $RelativePath -Line $Line -Message "View에서 Model을 직접 참조하고 있습니다"
    }
    if ($Architecture -eq "mvp" -and $IsView -and $Content -match '\b(?:using\s+[^;]*Models?|\w*Model\b)')
    {
        $Severity = Get-HarnessLintSeverity -ConfirmationStatus $ConfirmationStatus -DefaultSeverity "error" -IsProfileRule $true
        $Line = Get-HarnessLintLineNumber -Lines $Lines -Pattern '\b(?:Models?|Model)\b'
        Add-HarnessLintDiagnostic -Diagnostics $Diagnostics -RuleId "MVP001" -Severity $Severity -Path $RelativePath -Line $Line -Message "View에서 Model을 직접 참조하고 있습니다"
    }
    if ($Architecture -eq "mvc" -and $IsView -and $Content -match '\b\w*Model\.\w+\s*=')
    {
        $Line = Get-HarnessLintLineNumber -Lines $Lines -Pattern '\b\w*Model\.\w+\s*='
        Add-HarnessLintDiagnostic -Diagnostics $Diagnostics -RuleId "MVC001" -Severity "warning" -Path $RelativePath -Line $Line -Message "View에서 Model 상태를 직접 변경하는 코드가 의심됩니다"
    }
    if ($Architecture -eq "layered_clean" -and $RelativePath -match '(?:^|/)Domain(?:/|$)' -and $Content -match '\b(?:UnityEngine|Infrastructure|Presentation)\b')
    {
        $Severity = Get-HarnessLintSeverity -ConfirmationStatus $ConfirmationStatus -DefaultSeverity "error" -IsProfileRule $true
        $Line = Get-HarnessLintLineNumber -Lines $Lines -Pattern '\b(?:UnityEngine|Infrastructure|Presentation)\b'
        Add-HarnessLintDiagnostic -Diagnostics $Diagnostics -RuleId "LAYER001" -Severity $Severity -Path $RelativePath -Line $Line -Message "Domain이 바깥 계층을 참조하고 있습니다"
    }

    if ([string]$Profile["dependency_injection"] -eq "vcontainer" -and $Content -match '(?s)\[SerializeField\].*?\b\w*View\b.*?RegisterInstance\s*\(')
    {
        $Line = Get-HarnessLintLineNumber -Lines $Lines -Pattern 'RegisterInstance\s*\('
        Add-HarnessLintDiagnostic -Diagnostics $Diagnostics -RuleId "VCONTAINER001" -Severity "warning" -Path $RelativePath -Line $Line -Message "직렬화 View를 RegisterInstance로 등록한 코드가 의심됩니다"
    }
    if ([string]$Profile["async_backend"] -eq "unitask" -and $Content -match '\b(?:StartCoroutine|IEnumerator)\b')
    {
        $Severity = Get-HarnessLintSeverity -ConfirmationStatus $ConfirmationStatus -DefaultSeverity "error" -IsProfileRule $true
        $Line = Get-HarnessLintLineNumber -Lines $Lines -Pattern '\b(?:StartCoroutine|IEnumerator)\b'
        Add-HarnessLintDiagnostic -Diagnostics $Diagnostics -RuleId "UNITASK001" -Severity $Severity -Path $RelativePath -Line $Line -Message "UniTask 프로젝트에서 Coroutine 사용이 감지되었습니다"
    }
    if ([string]$Profile["tween_backend"] -eq "dotween" -and (Test-HarnessUpdateContains -Content $Content -Pattern '\b(?:DOTween|DO[A-Z]\w*)\s*\('))
    {
        $Line = Get-HarnessUpdateMatchLineNumber -Content $Content -Pattern '\b(?:DOTween|DO[A-Z]\w*)\s*\('
        Add-HarnessLintDiagnostic -Diagnostics $Diagnostics -RuleId "DOTWEEN001" -Severity "warning" -Path $RelativePath -Line $Line -Message "Update 계열 메서드에서 Tween 생성이 감지되었습니다"
    }
}

function Invoke-HarnessLint
{
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectRoot,

        [Parameter(Mandatory = $true)]
        [string]$ProfilePath,

        [Parameter(Mandatory = $true)]
        [string]$SchemaPath
    )

    $Diagnostics = New-Object 'System.Collections.Generic.List[string]'
    $script:HarnessLintInternalFailure = $false
    try
    {
        if (-not (Test-Path -LiteralPath $ProjectRoot -PathType Container))
        {
            Add-HarnessLintDiagnostic -Diagnostics $Diagnostics -RuleId "PATH001" -Severity "error" -Path "." -Line 0 -Message "프로젝트 루트를 찾을 수 없습니다"
            return New-HarnessLintResult -ExitCode 4 -Output $Diagnostics
        }
        $FullProjectRoot = Get-HarnessLintCanonicalPath -Path $ProjectRoot
        try
        {
            $Profile = Read-HarnessProfile -ProfilePath $ProfilePath -SchemaPath $SchemaPath
        }
        catch
        {
            Add-HarnessLintDiagnostic -Diagnostics $Diagnostics -RuleId "CONFIG001" -Severity "error" -Path $ProfilePath -Line 0 -Message "프로필을 읽거나 검증할 수 없습니다"
            return New-HarnessLintResult -ExitCode 3 -Output $Diagnostics
        }

        $ExcludePaths = New-Object 'System.Collections.Generic.List[string]'
        $ConfiguredExcludes = @($script:HarnessDefaultExcludeRoots) + @($Profile["exclude_root"])
        foreach ($ExcludeRoot in $ConfiguredExcludes)
        {
            $Boundary = Get-HarnessLintBoundary -ProjectRoot $FullProjectRoot -ConfiguredPath ([string]$ExcludeRoot)
            if ($null -eq $Boundary)
            {
                Add-HarnessLintDiagnostic -Diagnostics $Diagnostics -RuleId "CONFIG001" -Severity "error" -Path ([string]$ExcludeRoot) -Line 0 -Message "제외 루트가 프로젝트 경계 밖을 가리킵니다"
                continue
            }
            if (-not $ExcludePaths.Contains($Boundary))
            {
                [void]$ExcludePaths.Add($Boundary)
            }
        }

        $Files = New-Object 'System.Collections.Generic.List[System.IO.FileInfo]'
        $FilePaths = New-Object 'System.Collections.Generic.HashSet[string]' -ArgumentList (, (Get-HarnessLintPathComparer))
        $AssetsGamePath = Get-HarnessLintBoundary -ProjectRoot $FullProjectRoot -ConfiguredPath "Assets/_Game"
        foreach ($SourceRoot in @($Profile["source_root"]))
        {
            $SourcePath = Get-HarnessLintBoundary -ProjectRoot $FullProjectRoot -ConfiguredPath ([string]$SourceRoot)
            if ($null -eq $SourcePath -or $null -eq $AssetsGamePath -or
                -not (Test-HarnessLintPathBelow -Root $AssetsGamePath -Path $SourcePath))
            {
                Add-HarnessLintDiagnostic -Diagnostics $Diagnostics -RuleId "CONFIG001" -Severity "error" -Path ([string]$SourceRoot) -Line 0 -Message "소스 루트는 Assets/_Game 또는 그 하위 경로여야 합니다"
                continue
            }
            if ($null -eq $SourcePath -or -not (Test-Path -LiteralPath $SourcePath -PathType Container))
            {
                Add-HarnessLintDiagnostic -Diagnostics $Diagnostics -RuleId "PATH001" -Severity "error" -Path ([string]$SourceRoot) -Line 0 -Message "소스 루트를 찾거나 읽을 수 없습니다"
                continue
            }
            foreach ($File in @(Get-HarnessLintFiles -SourcePath $SourcePath -ExcludePaths $ExcludePaths -Pattern '*.cs'))
            {
                if ($FilePaths.Add((Get-HarnessLintCanonicalPath -Path $File.FullName)))
                {
                    [void]$Files.Add($File)
                }
            }
        }

        foreach ($File in $Files)
        {
            Add-HarnessFileDiagnostics -Diagnostics $Diagnostics -File $File -ProjectRoot $FullProjectRoot -Profile $Profile
        }
    }
    catch
    {
        Add-HarnessLintDiagnostic -Diagnostics $Diagnostics -RuleId "CONFIG001" -Severity "error" -Path "." -Line 0 -Message "C# 파일 분석기를 실행할 수 없습니다: $($_.Exception.Message)"
        return New-HarnessLintResult -ExitCode 4 -Output $Diagnostics
    }

    if ($script:HarnessLintInternalFailure)
    {
        return New-HarnessLintResult -ExitCode 4 -Output $Diagnostics
    }
    $ErrorCount = @($Diagnostics | Where-Object { $_ -match '^[^|]+\|error\|' }).Count
    return New-HarnessLintResult -ExitCode $(if ($ErrorCount -gt 0) { 1 } else { 0 }) -Output $Diagnostics
}
