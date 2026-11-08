# ==============================================================================
# [기능]: Unity 프로젝트를 읽기 전용으로 감지하고 하네스 프로필 후보를 생성합니다.
# [작성자]: 윤승종
# ==============================================================================

Set-StrictMode -Version Latest

$script:HarnessDetectionReportWriter = $null

function New-DetectionResult
{
    param(
        [int]$ExitCode,
        [string]$Output
    )

    return [PSCustomObject]@{
        ExitCode = $ExitCode
        Output = $Output
    }
}

function Get-HarnessPathComparison
{
    if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT)
    {
        return [System.StringComparison]::OrdinalIgnoreCase
    }

    return [System.StringComparison]::Ordinal
}

function Get-HarnessPathComparer
{
    if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT)
    {
        return [System.StringComparer]::OrdinalIgnoreCase
    }

    return [System.StringComparer]::Ordinal
}

function Get-HarnessCanonicalPath
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

function Test-HarnessPathBelow
{
    param(
        [string]$Root,
        [string]$Path
    )

    $FullRoot = (Get-HarnessCanonicalPath -Path $Root).TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar)
    $FullPath = Get-HarnessCanonicalPath -Path $Path
    $Comparison = Get-HarnessPathComparison
    if ($FullPath.Equals($FullRoot, $Comparison))
    {
        return $true
    }

    $Prefix = $FullRoot + [System.IO.Path]::DirectorySeparatorChar
    return $FullPath.StartsWith($Prefix, $Comparison)
}

function Get-HarnessRelativePath
{
    param(
        [string]$ProjectRoot,
        [string]$Path
    )

    $FullRoot = (Get-HarnessCanonicalPath -Path $ProjectRoot).TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar)
    $FullPath = Get-HarnessCanonicalPath -Path $Path
    if (-not (Test-HarnessPathBelow -Root $FullRoot -Path $FullPath))
    {
        throw "프로젝트 경계 밖의 경로입니다: $Path"
    }

    if ($FullPath.Length -eq $FullRoot.Length)
    {
        return "."
    }

    return $FullPath.Substring($FullRoot.Length + 1).Replace([System.IO.Path]::DirectorySeparatorChar, [char]'/')
}

function Test-HarnessExcludedCodePath
{
    param([string]$RelativePath)

    $Normalized = $RelativePath.Replace([char]'\', [char]'/')
    $ExcludedRoots = @(
        "Library", "Temp", "Logs", "obj", "UserSettings", "Packages", ".git", ".agents", ".agents-backup",
        "Assets/Plugins", "Assets/ThirdParty"
    )
    foreach ($ExcludedRoot in $ExcludedRoots)
    {
        $Comparison = Get-HarnessPathComparison
        if ($Normalized.Equals($ExcludedRoot, $Comparison) -or $Normalized.StartsWith($ExcludedRoot + "/", $Comparison))
        {
            return $true
        }
    }

    return $false
}

function Get-HarnessCodeFiles
{
    param([string]$ProjectRoot)

    $CodeRoot = Join-Path $ProjectRoot "Assets/_Game"
    if (-not (Test-Path -LiteralPath $CodeRoot -PathType Container))
    {
        throw "프로젝트 소유 코드 루트를 읽을 수 없습니다: $CodeRoot"
    }

    $CanonicalRoot = Get-HarnessCanonicalPath -Path $CodeRoot
    $Comparer = Get-HarnessPathComparer
    $VisitedDirectories = New-Object 'System.Collections.Generic.HashSet[string]' -ArgumentList (, $Comparer)
    $VisitedFiles = New-Object 'System.Collections.Generic.HashSet[string]' -ArgumentList (, $Comparer)
    $PendingDirectories = New-Object 'System.Collections.Generic.Stack[string]'
    $Files = New-Object 'System.Collections.Generic.List[System.IO.FileInfo]'
    $PendingDirectories.Push($CanonicalRoot)
    while ($PendingDirectories.Count -gt 0)
    {
        $DirectoryPath = $PendingDirectories.Pop()
        if (-not $VisitedDirectories.Add($DirectoryPath))
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

            $CanonicalChildPath = Get-HarnessCanonicalPath -Path $ChildItem.FullName
            $PendingDirectories.Push($CanonicalChildPath)
        }

        foreach ($FilePath in [System.IO.Directory]::EnumerateFiles($DirectoryPath))
        {
            $Extension = [System.IO.Path]::GetExtension($FilePath)
            if ($Extension -ne ".cs" -and $Extension -ne ".asmdef")
            {
                continue
            }

            $FileItem = Get-Item -LiteralPath $FilePath -Force -ErrorAction Stop
            if (($FileItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)
            {
                continue
            }
            $CanonicalFilePath = Get-HarnessCanonicalPath -Path $FileItem.FullName
            if ($VisitedFiles.Add($CanonicalFilePath))
            {
                [void]$Files.Add((Get-Item -LiteralPath $CanonicalFilePath -Force -ErrorAction Stop))
            }
        }
    }

    return @($Files | Sort-Object FullName)
}

function ConvertTo-HarnessDetectionSanitizedCSharp
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

function Get-HarnessSanitizedCode
{
    param([System.IO.FileInfo[]]$Files)

    $Builder = New-Object System.Text.StringBuilder
    foreach ($File in $Files)
    {
        if ($File.Extension -ne ".cs")
        {
            continue
        }

        $Text = [System.IO.File]::ReadAllText($File.FullName)
        [void]$Builder.AppendLine((ConvertTo-HarnessDetectionSanitizedCSharp -Content $Text))
    }

    return $Builder.ToString()
}

function Read-HarnessManifestDependencies
{
    param([string]$ManifestPath)

    $ManifestFileName = [System.IO.Path]::GetFileName($ManifestPath)
    try
    {
        $JsonText = [System.IO.File]::ReadAllText($ManifestPath, (Get-HarnessUtf8Encoding))
    }
    catch
    {
        throw "$ManifestFileName 파일을 읽을 수 없습니다: $ManifestPath"
    }
    $Root = $null
    try
    {
        Add-Type -AssemblyName System.Web.Extensions -ErrorAction Stop
        $Serializer = New-Object System.Web.Script.Serialization.JavaScriptSerializer
        $Root = $Serializer.DeserializeObject($JsonText)
    }
    catch
    {
        try
        {
            $Root = ConvertFrom-Json -InputObject $JsonText -ErrorAction Stop
        }
        catch
        {
            throw "$ManifestFileName의 JSON 문법이 올바르지 않습니다: $ManifestPath"
        }
    }

    if ($null -eq $Root -or ($Root -isnot [System.Collections.IDictionary] -and $Root -isnot [PSCustomObject]))
    {
        throw "$ManifestFileName의 최상위 형식은 JSON 객체여야 합니다: $ManifestPath"
    }

    $Dependencies = New-Object 'System.Collections.Generic.List[string]'
    if ($Root -is [System.Collections.IDictionary])
    {
        if (-not $Root.Contains("dependencies") -or $Root["dependencies"] -isnot [System.Collections.IDictionary])
        {
            throw "$ManifestFileName의 dependencies 형식이 올바르지 않습니다: $ManifestPath"
        }
        foreach ($Key in $Root["dependencies"].Keys)
        {
            [void]$Dependencies.Add([string]$Key)
        }
    }
    else
    {
        $Property = $Root.PSObject.Properties["dependencies"]
        if ($null -eq $Property -or $null -eq $Property.Value -or
            ($Property.Value -isnot [System.Collections.IDictionary] -and $Property.Value -isnot [PSCustomObject]))
        {
            throw "$ManifestFileName의 dependencies 형식이 올바르지 않습니다: $ManifestPath"
        }
        if ($Property.Value -is [System.Collections.IDictionary])
        {
            foreach ($Key in $Property.Value.Keys)
            {
                [void]$Dependencies.Add([string]$Key)
            }
        }
        else
        {
            foreach ($DependencyProperty in $Property.Value.PSObject.Properties)
            {
                [void]$Dependencies.Add([string]$DependencyProperty.Name)
            }
        }
    }

    return $Dependencies
}

function Find-UnityProjectRoot
{
    param(
        [Parameter(Mandatory = $true)]
        [string]$StartPath
    )

    if (-not (Test-Path -LiteralPath $StartPath))
    {
        throw "Unity 프로젝트 시작 경로를 찾을 수 없습니다: $StartPath"
    }

    try
    {
        $Item = Get-Item -LiteralPath $StartPath -Force -ErrorAction Stop
    }
    catch
    {
        throw "Unity 프로젝트 시작 경로를 읽을 수 없습니다: $StartPath"
    }
    $Candidate = if ($Item.PSIsContainer) { $Item.FullName } else { $Item.Directory.FullName }
    while (-not [string]::IsNullOrEmpty($Candidate))
    {
        $VersionPath = Join-Path $Candidate "ProjectSettings/ProjectVersion.txt"
        $ManifestPath = Join-Path $Candidate "Packages/manifest.json"
        if ((Test-Path -LiteralPath $VersionPath) -or (Test-Path -LiteralPath $ManifestPath))
        {
            if (-not (Test-Path -LiteralPath $VersionPath -PathType Leaf) -or -not (Test-Path -LiteralPath $ManifestPath -PathType Leaf))
            {
                throw "Unity 프로젝트 필수 파일을 읽을 수 없습니다: $Candidate"
            }
            return Get-HarnessCanonicalPath -Path $Candidate
        }

        $Parent = [System.IO.Directory]::GetParent($Candidate)
        if ($null -eq $Parent)
        {
            break
        }
        $Candidate = $Parent.FullName
    }

    return $null
}

function Get-HarnessSourceRoots
{
    param(
        [string]$ProjectRoot,
        [System.IO.FileInfo[]]$CodeFiles
    )

    $CodeRoot = Join-Path $ProjectRoot "Assets/_Game"
    if (-not (Test-Path -LiteralPath $CodeRoot -PathType Container))
    {
        throw "프로젝트 소유 코드 루트를 읽을 수 없습니다: $CodeRoot"
    }

    return @("Assets/_Game")
}

function Get-HarnessTestRoots
{
    param(
        [string]$ProjectRoot,
        [System.IO.FileInfo[]]$CodeFiles
    )

    $Roots = New-Object 'System.Collections.Generic.List[string]'
    foreach ($File in $CodeFiles)
    {
        if ($File.Extension -ne ".cs")
        {
            continue
        }
        $RelativePath = Get-HarnessRelativePath -ProjectRoot $ProjectRoot -Path $File.FullName
        if ($RelativePath -match '^(.+?/Tests)(?:/|$)')
        {
            if (-not $Roots.Contains($Matches[1]))
            {
                [void]$Roots.Add($Matches[1])
            }
        }
    }
    return @($Roots | Sort-Object -Unique)
}

function Get-HarnessArchitecture
{
    param(
        [string]$ProjectRoot,
        [string]$SignaturesPath,
        [System.IO.FileInfo[]]$CodeFiles,
        [string]$SanitizedCode
    )

    $Scores = [ordered]@{ mvvm = 0; mvp = 0; mvc = 0; layered_clean = 0 }
    $Evidence = New-Object 'System.Collections.Generic.List[string]'
    $RelativePaths = [string]::Join([Environment]::NewLine, @($CodeFiles | ForEach-Object {
        Get-HarnessRelativePath -ProjectRoot $ProjectRoot -Path $_.FullName
    }))
    foreach ($Line in (Read-HarnessUtf8Lines -Path $SignaturesPath))
    {
        if (Test-HarnessIgnoredLine -Line $Line)
        {
            continue
        }
        $Parts = $Line.Split([char]'|')
        if ($Parts.Length -ne 3 -or -not $Scores.Contains($Parts[0]))
        {
            throw "감지 시그니처 형식이 올바르지 않습니다: $Line"
        }
        $Weight = 0
        if (-not [int]::TryParse($Parts[2], [ref]$Weight) -or $Weight -lt 0)
        {
            throw "감지 시그니처 가중치가 올바르지 않습니다: $Line"
        }
        try
        {
            $Matched = if ($Parts[1].Contains("/")) {
                [regex]::IsMatch($RelativePaths, $Parts[1])
            } else {
                [regex]::IsMatch($SanitizedCode, $Parts[1])
            }
        }
        catch
        {
            throw "감지 시그니처 정규식이 올바르지 않습니다: $($Parts[1])"
        }
        if ($Matched)
        {
            $Scores[$Parts[0]] = [int]$Scores[$Parts[0]] + $Weight
            [void]$Evidence.Add("$($Parts[0]):$($Parts[1])(+${Weight})")
        }
    }

    $Maximum = 0
    foreach ($Key in $Scores.Keys)
    {
        if ([int]$Scores[$Key] -gt $Maximum)
        {
            $Maximum = [int]$Scores[$Key]
        }
    }
    $Winners = @($Scores.Keys | Where-Object { [int]$Scores[$_] -eq $Maximum -and $Maximum -gt 0 })
    $Architecture = if ($Maximum -ge 4 -and $Winners.Count -eq 1) { [string]$Winners[0] } else { "custom" }
    $Confidence = if ($Maximum -ge 4) { "high" } elseif ($Maximum -gt 0) { "low" } else { "unknown" }
    return [PSCustomObject]@{
        Value = $Architecture
        Confidence = $Confidence
        Conflict = ($Maximum -ge 4 -and $Winners.Count -gt 1)
        Evidence = "mvvm=$($Scores['mvvm']), mvp=$($Scores['mvp']), mvc=$($Scores['mvc']), layered_clean=$($Scores['layered_clean']); $([string]::Join(', ', $Evidence))"
    }
}

function Test-HarnessDependency
{
    param(
        [string[]]$Dependencies,
        [string]$Name
    )
    return (@($Dependencies) -contains $Name)
}

function Get-HarnessBackend
{
    param(
        [string]$Kind,
        [string]$SanitizedCode
    )

    if ($Kind -eq "di")
    {
        $VContainer = $SanitizedCode -match '\bVContainer\b'
        $Zenject = $SanitizedCode -match '\b(?:Zenject|Extenject)\b'
        if ($VContainer -and $Zenject) { return "custom" }
        if ($VContainer) { return "vcontainer" }
        if ($Zenject) { return "zenject" }
        return "unknown"
    }
    if ($Kind -eq "async")
    {
        $UniTask = $SanitizedCode -match '\b(?:UniTask|Cysharp\.Threading\.Tasks)\b'
        $Coroutine = $SanitizedCode -match '\b(?:IEnumerator|StartCoroutine)\b'
        $Task = $SanitizedCode -match '\b(?:System\.Threading\.Tasks|Task(?:CompletionSource)?\s*[<(])'
        $EvidenceCount = 0
        if ($UniTask) { $EvidenceCount++ }
        if ($Coroutine) { $EvidenceCount++ }
        if ($Task) { $EvidenceCount++ }
        if ($EvidenceCount -gt 1) { return "mixed" }
        if ($UniTask) { return "unitask" }
        if ($Coroutine) { return "coroutine" }
        if ($Task) { return "task" }
        return "unknown"
    }

    $Dotween = $SanitizedCode -match '\b(?:DG\.Tweening|DOTween)\b'
    $LeanTween = $SanitizedCode -match '\bLeanTween\b'
    if ($Dotween -and $LeanTween) { return "custom" }
    if ($Dotween) { return "dotween" }
    if ($LeanTween) { return "leantween" }
    return "unknown"
}

function Test-HarnessDependencyPattern
{
    param(
        [string[]]$Dependencies,
        [string]$Pattern
    )

    foreach ($Dependency in @($Dependencies))
    {
        if ([regex]::IsMatch([string]$Dependency, $Pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase))
        {
            return $true
        }
    }

    return $false
}

function Get-HarnessBackendDetection
{
    param(
        [string]$Kind,
        [string]$SanitizedCode,
        [string[]]$Dependencies
    )

    $Value = Get-HarnessBackend -Kind $Kind -SanitizedCode $SanitizedCode
    $Confidence = if ($Value -eq "unknown") { "unknown" } else { "high" }
    $Evidence = "확정할 코드 사용 근거 없음"

    if ($Kind -eq "di")
    {
        $HasVContainerPackage = Test-HarnessDependencyPattern -Dependencies $Dependencies -Pattern '(^|[.])vcontainer$'
        $HasZenjectPackage = Test-HarnessDependencyPattern -Dependencies $Dependencies -Pattern '(^|[.])(zenject|extenject)$'
        if ($Value -eq "custom") { $Evidence = "코드 사용 근거 확인: VContainer, Zenject" }
        elseif ($Value -eq "vcontainer") { $Evidence = "코드 사용 근거 확인: VContainer" }
        elseif ($Value -eq "zenject") { $Evidence = "코드 사용 근거 확인: Zenject" }
        elseif ($HasVContainerPackage -or $HasZenjectPackage)
        {
            $Installed = New-Object 'System.Collections.Generic.List[string]'
            if ($HasVContainerPackage) { [void]$Installed.Add("VContainer") }
            if ($HasZenjectPackage) { [void]$Installed.Add("Zenject") }
            $Confidence = "low"
            $Evidence = [string]::Join(", ", $Installed) + " 패키지 설치만 확인, 코드 사용 미확정"
        }
    }
    elseif ($Kind -eq "async")
    {
        $HasUniTaskPackage = Test-HarnessDependencyPattern -Dependencies $Dependencies -Pattern '(^|[.])unitask$'
        if ($Value -eq "mixed") { $Evidence = "복수 비동기 코드 사용 근거 확인" }
        elseif ($Value -eq "unitask") { $Evidence = "코드 사용 근거 확인: UniTask" }
        elseif ($Value -eq "coroutine") { $Evidence = "코드 사용 근거 확인: Coroutine" }
        elseif ($Value -eq "task") { $Evidence = "코드 사용 근거 확인: Task" }

        if ($HasUniTaskPackage -and $Value -eq "unknown")
        {
            $Confidence = "low"
            $Evidence = "UniTask 패키지 설치만 확인, 코드 사용 미확정"
        }
        elseif ($HasUniTaskPackage -and $Value -ne "unitask" -and $Value -ne "unknown")
        {
            $Evidence += "; UniTask 패키지 설치만 확인, 코드 사용 미확정"
        }
    }
    else
    {
        $HasDotweenPackage = Test-HarnessDependencyPattern -Dependencies $Dependencies -Pattern '(^|[.])dotween$'
        $HasLeanTweenPackage = Test-HarnessDependencyPattern -Dependencies $Dependencies -Pattern '(^|[.])leantween$'
        if ($Value -eq "custom") { $Evidence = "코드 사용 근거 확인: DOTween, LeanTween" }
        elseif ($Value -eq "dotween") { $Evidence = "코드 사용 근거 확인: DOTween" }
        elseif ($Value -eq "leantween") { $Evidence = "코드 사용 근거 확인: LeanTween" }
        elseif ($HasDotweenPackage -or $HasLeanTweenPackage)
        {
            $Installed = New-Object 'System.Collections.Generic.List[string]'
            if ($HasDotweenPackage) { [void]$Installed.Add("DOTween") }
            if ($HasLeanTweenPackage) { [void]$Installed.Add("LeanTween") }
            $Confidence = "low"
            $Evidence = [string]::Join(", ", $Installed) + " 패키지 설치만 확인, 코드 사용 미확정"
        }
    }

    return [PSCustomObject]@{
        Value = $Value
        Confidence = $Confidence
        Evidence = $Evidence
    }
}

function Get-HarnessOptimizationStates
{
    param(
        [string]$UnityVersion,
        [string]$RenderPipeline
    )

    $VersionParts = $UnityVersion.Split([char]'.')
    $VersionMajor = 0
    $VersionMinor = 0
    if ($VersionParts.Count -gt 0) { [void][int]::TryParse($VersionParts[0], [ref]$VersionMajor) }
    if ($VersionParts.Count -gt 1) { [void][int]::TryParse($VersionParts[1], [ref]$VersionMinor) }
    $IsUnity6 = $VersionMajor -ge 6000
    $IsUnity62 = $VersionMajor -gt 6000 -or ($VersionMajor -eq 6000 -and $VersionMinor -ge 2)

    $GpuResidentDrawer = "unknown"
    $GpuOcclusionCulling = "unknown"
    if ($RenderPipeline -eq "urp" -or $RenderPipeline -eq "hdrp")
    {
        if ($IsUnity6)
        {
            $GpuResidentDrawer = "applicable"
        }
        else
        {
            $GpuResidentDrawer = "not_applicable"
            $GpuOcclusionCulling = "not_applicable"
        }
    }
    elseif ($RenderPipeline -eq "builtin")
    {
        $GpuResidentDrawer = "not_applicable"
        $GpuOcclusionCulling = "not_applicable"
    }

    if ($RenderPipeline -eq "urp" -and $IsUnity6)
    {
        $Stp = "applicable"
    }
    elseif ($RenderPipeline -eq "custom" -or $RenderPipeline -eq "unknown")
    {
        $Stp = "unknown"
    }
    else
    {
        $Stp = "not_applicable"
    }

    $MeshLod = if (-not $IsUnity62 -or $RenderPipeline -eq "builtin") { "not_applicable" } else { "unknown" }
    return [PSCustomObject]@{
        GpuResidentDrawer = $GpuResidentDrawer
        GpuOcclusionCulling = $GpuOcclusionCulling
        Stp = $Stp
        MeshLod = $MeshLod
    }
}

function New-HarnessDetectionProfile
{
    param([System.Collections.IDictionary]$Values)

    $Profile = [ordered]@{}
    foreach ($Key in $Values.Keys)
    {
        if (@("source_root", "test_root", "target_platform", "exclude_root") -contains $Key)
        {
            $List = New-Object 'System.Collections.Generic.List[string]'
            foreach ($Value in @($Values[$Key]))
            {
                [void]$List.Add([string]$Value)
            }
            $Profile[$Key] = $List
        }
        else
        {
            $Profile[$Key] = [string]$Values[$Key]
        }
    }
    return $Profile
}

function Write-DetectionReport
{
    param(
        [Parameter(Mandatory = $true)]
        [string]$ReportPath,

        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Context
    )

    $Lines = New-Object 'System.Collections.Generic.List[string]'
    [void]$Lines.Add("# Unity 하네스 감지 보고서")
    [void]$Lines.Add("")
    [void]$Lines.Add("## 요약")
    [void]$Lines.Add("")
    [void]$Lines.Add("- 프로젝트: ``$($Context['project_name'])`` (신뢰도: high, 근거 파일: 프로젝트 루트 디렉터리명)")
    [void]$Lines.Add("- Unity: ``$($Context['unity_version'])`` (신뢰도: high, 근거 파일: ``ProjectSettings/ProjectVersion.txt``)")
    [void]$Lines.Add("- 렌더 파이프라인: ``$($Context['render_pipeline'])`` (신뢰도: medium, 근거 파일: $($Context['package_evidence']), ``ProjectSettings/GraphicsSettings.asset``)")
    [void]$Lines.Add("- 아키텍처: ``$($Context['architecture'])`` (신뢰도: $($Context['architecture_confidence']), 근거 파일: ``.agents/config/detection-signatures.conf``, 제외 경계 밖 .cs)")
    [void]$Lines.Add("- 프로필 상태: ``pending`` (신뢰도: high, 근거 파일: 생성된 프로필 후보)")
    [void]$Lines.Add("")
    [void]$Lines.Add("## 감지 근거와 신뢰도")
    [void]$Lines.Add("")
    [void]$Lines.Add("| 항목 | 값 | 신뢰도 | 근거 파일 및 증거 |")
    [void]$Lines.Add("|---|---|---|---|")
    [void]$Lines.Add("| unity_version | ``$($Context['unity_version'])`` | high | ``ProjectSettings/ProjectVersion.txt`` |")
    [void]$Lines.Add("| render_pipeline | ``$($Context['render_pipeline'])`` | medium | $($Context['package_evidence']); ``ProjectSettings/GraphicsSettings.asset`` |")
    [void]$Lines.Add("| architecture | ``$($Context['architecture'])`` | $($Context['architecture_confidence']) | $($Context['architecture_evidence']) |")
    [void]$Lines.Add("| dependency_injection | ``$($Context['dependency_injection'])`` | $($Context['di_confidence']) | $($Context['di_evidence']) |")
    [void]$Lines.Add("| async_backend | ``$($Context['async_backend'])`` | $($Context['async_confidence']) | $($Context['async_evidence']) |")
    [void]$Lines.Add("| tween_backend | ``$($Context['tween_backend'])`` | $($Context['tween_confidence']) | $($Context['tween_evidence']) |")
    [void]$Lines.Add("| target_platform | ``unknown`` | unknown | 정적 프로젝트 파일만으로 활성 빌드 타겟 확정 불가 |")
    [void]$Lines.Add("")
    [void]$Lines.Add("## 소스 및 테스트 루트")
    [void]$Lines.Add("")
    foreach ($SourceRoot in @($Context["source_roots"]))
    {
        [void]$Lines.Add("- source_root: ``$SourceRoot`` (신뢰도: medium, 근거: asmdef/Scripts/.cs)")
    }
    if (@($Context["test_roots"]).Count -eq 0)
    {
        [void]$Lines.Add("- test_root: 감지되지 않음 (신뢰도: unknown)")
    }
    else
    {
        foreach ($TestRoot in @($Context["test_roots"]))
        {
            [void]$Lines.Add("- test_root: ``$TestRoot`` (신뢰도: medium, 근거: 테스트 명명 폴더와 실제 .cs)")
        }
    }
    [void]$Lines.Add("")
    [void]$Lines.Add("## 조건부 최적화 적용 가능성")
    [void]$Lines.Add("")
    [void]$Lines.Add("- gpu_resident_drawer: ``$($Context['gpu_resident_drawer'])`` — Unity 버전과 렌더 파이프라인 전제만 판정")
    [void]$Lines.Add("- gpu_occlusion_culling: ``$($Context['gpu_occlusion_culling'])`` — 씬 가림 구조와 GPU 프로파일링 확인 필요")
    [void]$Lines.Add("- stp: ``$($Context['stp'])`` — TAA, Render Scale, Motion Vector 활성 상태 확인 필요")
    [void]$Lines.Add("- mesh_lod: ``$($Context['mesh_lod'])`` — 현재 Unity 버전의 기본 Mesh LOD 지원 확인 필요; 6000.3 cross-fade는 GPU Resident Drawer 활성화 필요, 다른 버전 미확인은 unknown")
    [void]$Lines.Add("")
    [void]$Lines.Add("## 충돌 및 미확정 항목")
    [void]$Lines.Add("")
    if ([bool]$Context["architecture_conflict"])
    {
        [void]$Lines.Add("- 아키텍처 강한 시그니처 점수가 충돌하여 custom으로 처리했습니다.")
    }
    elseif ($Context["architecture"] -eq "custom")
    {
        [void]$Lines.Add("- 아키텍처 최고 점수가 유일하지 않거나 4 미만이므로 custom으로 처리했습니다.")
    }
    [void]$Lines.Add("- target_platform은 unknown이며 Unity Editor에서 사용자가 확인해야 합니다.")
    [void]$Lines.Add("- 패키지 설치 증거는 실제 씬/에셋 활성화와 동일하지 않습니다.")
    if (-not [string]::IsNullOrEmpty([string]$Context["comparison_profile_path"]))
    {
        [void]$Lines.Add("")
        [void]$Lines.Add("**기존 프로필 비교**")
        [void]$Lines.Add("")
        [void]$Lines.Add("- 기존 프로필: ``$($Context['comparison_profile_path'])``")
        [void]$Lines.Add("- 재감지 후보: ``$($Context['candidate_profile_path'])``")
        [void]$Lines.Add("- 기존 확정 프로필은 변경하지 않았습니다.")
        $ExistingLines = Read-HarnessUtf8Lines -Path ([string]$Context["comparison_profile_path"])
        $CandidateLines = Read-HarnessUtf8Lines -Path ([string]$Context["candidate_profile_path"])
        foreach ($SchemaLine in (Read-HarnessUtf8Lines -Path ([string]$Context["schema_path"])))
        {
            if (Test-HarnessIgnoredLine -Line $SchemaLine)
            {
                continue
            }
            $Key = $SchemaLine.Split([char]'|')[0]
            $Before = [string]::Join(", ", @($ExistingLines | Where-Object { $_.StartsWith($Key + "=") } | ForEach-Object { $_.Substring($Key.Length + 1) }))
            $After = [string]::Join(", ", @($CandidateLines | Where-Object { $_.StartsWith($Key + "=") } | ForEach-Object { $_.Substring($Key.Length + 1) }))
            if ($Before -ne $After)
            {
                [void]$Lines.Add("- ``$Key``: 기존 ``$Before`` → 후보 ``$After``")
            }
        }
    }
    [void]$Lines.Add("")
    [void]$Lines.Add("## 사용자 확인 절차")
    [void]$Lines.Add("")
    [void]$Lines.Add("1. 감지 프로필과 위 근거 파일을 검토합니다.")
    [void]$Lines.Add("2. Unity Editor에서 활성 Render Pipeline Asset과 Build Target을 확인합니다.")
    [void]$Lines.Add("3. 조건부 최적화는 씬·GPU·플랫폼 프로파일링 후 적용합니다.")
    [void]$Lines.Add('4. 값이 올바르면 초기화 스크립트의 `--confirm`으로 상태만 confirmed로 전환합니다.')

    $LexicalReportPath = [System.IO.Path]::GetFullPath($ReportPath)
    if (Test-HarnessReparsePoint -Path $LexicalReportPath)
    {
        throw "보고서 출력 엔트리로 재파싱 지점을 사용할 수 없습니다: $ReportPath"
    }
    $FullReportPath = Get-HarnessProfileCanonicalPath -Path $LexicalReportPath
    $DirectoryPath = Split-Path -Parent $FullReportPath
    if (-not (Test-Path -LiteralPath $DirectoryPath -PathType Container))
    {
        throw "보고서 출력 경로를 안전하게 사용할 수 없습니다: $ReportPath"
    }
    $TemporaryPath = Join-Path $DirectoryPath ("." + [System.IO.Path]::GetFileName($FullReportPath) + ".tmp." + [Guid]::NewGuid().ToString("N"))
    try
    {
        [System.IO.File]::WriteAllLines($TemporaryPath, [string[]]$Lines, (Get-HarnessUtf8Encoding))
        if (Test-Path -LiteralPath $FullReportPath -PathType Leaf)
        {
            [System.IO.File]::Replace($TemporaryPath, $FullReportPath, $null, $true)
        }
        else
        {
            [System.IO.File]::Move($TemporaryPath, $FullReportPath)
        }
    }
    finally
    {
        if (Test-Path -LiteralPath $TemporaryPath)
        {
            Remove-Item -LiteralPath $TemporaryPath -Force -ErrorAction SilentlyContinue
        }
    }
}

function Invoke-ProjectDetection
{
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectRoot,

        [Parameter(Mandatory = $true)]
        [string]$ProfilePath,

        [Parameter(Mandatory = $true)]
        [string]$ReportPath,

        [Parameter(Mandatory = $true)]
        [string]$SchemaPath,

        [Parameter(Mandatory = $true)]
        [string]$SignaturesPath,

        [string]$ComparisonProfilePath = ""
    )

    try
    {
        try
        {
            $UnityRoot = Find-UnityProjectRoot -StartPath $ProjectRoot
        }
        catch
        {
            if ($_.Exception.Message.Contains("찾을 수 없습니다"))
            {
                return New-DetectionResult -ExitCode 2 -Output "[PowerShell 감지] $($_.Exception.Message)"
            }
            return New-DetectionResult -ExitCode 4 -Output "[PowerShell 감지] $($_.Exception.Message)"
        }
        if ([string]::IsNullOrEmpty($UnityRoot))
        {
            return New-DetectionResult -ExitCode 2 -Output "[PowerShell 감지] Unity 프로젝트 루트를 찾을 수 없습니다: $ProjectRoot"
        }
        if (-not (Test-Path -LiteralPath $SchemaPath -PathType Leaf) -or -not (Test-Path -LiteralPath $SignaturesPath -PathType Leaf))
        {
            return New-DetectionResult -ExitCode 4 -Output "[PowerShell 감지] 스키마 또는 감지 시그니처를 읽을 수 없습니다."
        }

        $VersionPath = Join-Path $UnityRoot "ProjectSettings/ProjectVersion.txt"
        $ManifestPath = Join-Path $UnityRoot "Packages/manifest.json"
        $LockPath = Join-Path $UnityRoot "Packages/packages-lock.json"
        $VersionLine = [System.IO.File]::ReadAllLines($VersionPath, (Get-HarnessUtf8Encoding)) | Where-Object { $_ -match '^m_EditorVersion:\s*(\S+)' } | Select-Object -First 1
        if ([string]::IsNullOrEmpty($VersionLine) -or $VersionLine -notmatch '^m_EditorVersion:\s*(\S+)')
        {
            return New-DetectionResult -ExitCode 4 -Output "[PowerShell 감지] ProjectVersion.txt에서 Unity 버전을 읽을 수 없습니다."
        }
        $UnityVersion = $Matches[1]
        $Dependencies = New-Object 'System.Collections.Generic.List[string]'
        foreach ($Dependency in @(Read-HarnessManifestDependencies -ManifestPath $ManifestPath))
        {
            if ($Dependencies -notcontains $Dependency)
            {
                [void]$Dependencies.Add($Dependency)
            }
        }
        $PackageEvidence = "``Packages/manifest.json``"
        if (Test-Path -LiteralPath $LockPath)
        {
            if (-not (Test-Path -LiteralPath $LockPath -PathType Leaf))
            {
                return New-DetectionResult -ExitCode 4 -Output "[PowerShell 감지] packages-lock.json 파일을 읽을 수 없습니다."
            }
            foreach ($Dependency in @(Read-HarnessManifestDependencies -ManifestPath $LockPath))
            {
                if ($Dependencies -notcontains $Dependency)
                {
                    [void]$Dependencies.Add($Dependency)
                }
            }
            $PackageEvidence += "; ``Packages/packages-lock.json``"
        }
        $CodeFiles = @(Get-HarnessCodeFiles -ProjectRoot $UnityRoot)
        $SanitizedCode = Get-HarnessSanitizedCode -Files $CodeFiles
        $SourceRoots = @(Get-HarnessSourceRoots -ProjectRoot $UnityRoot -CodeFiles $CodeFiles)
        $TestRoots = @(Get-HarnessTestRoots -ProjectRoot $UnityRoot -CodeFiles $CodeFiles)
        $Architecture = Get-HarnessArchitecture -ProjectRoot $UnityRoot -SignaturesPath $SignaturesPath -CodeFiles $CodeFiles -SanitizedCode $SanitizedCode

        $HasUrp = Test-HarnessDependency -Dependencies $Dependencies -Name "com.unity.render-pipelines.universal"
        $HasHdrp = Test-HarnessDependency -Dependencies $Dependencies -Name "com.unity.render-pipelines.high-definition"
        $GraphicsPath = Join-Path $UnityRoot "ProjectSettings/GraphicsSettings.asset"
        $GraphicsText = if (Test-Path -LiteralPath $GraphicsPath -PathType Leaf) { [System.IO.File]::ReadAllText($GraphicsPath, (Get-HarnessUtf8Encoding)) } else { "" }
        $RenderPipeline = if ($HasUrp -and $HasHdrp) {
            "custom"
        } elseif ($HasUrp) {
            "urp"
        } elseif ($HasHdrp) {
            "hdrp"
        } elseif (-not [string]::IsNullOrEmpty($GraphicsText) -and $GraphicsText -match 'm_CustomRenderPipeline:\s*\{fileID:\s*0\}') {
            "builtin"
        } else {
            "unknown"
        }
        $DependencyArray = @($Dependencies | ForEach-Object { [string]$_ })
        $DependencyInjectionDetection = Get-HarnessBackendDetection -Kind "di" -SanitizedCode $SanitizedCode -Dependencies $DependencyArray
        $AsyncBackendDetection = Get-HarnessBackendDetection -Kind "async" -SanitizedCode $SanitizedCode -Dependencies $DependencyArray
        $TweenBackendDetection = Get-HarnessBackendDetection -Kind "tween" -SanitizedCode $SanitizedCode -Dependencies $DependencyArray
        $DependencyInjection = $DependencyInjectionDetection.Value
        $AsyncBackend = $AsyncBackendDetection.Value
        $TweenBackend = $TweenBackendDetection.Value
        $OptimizationStates = Get-HarnessOptimizationStates -UnityVersion $UnityVersion -RenderPipeline $RenderPipeline

        $Values = [ordered]@{
            profile_version = "1"
            confirmation_status = "pending"
            project_name = (Split-Path -Leaf $UnityRoot)
            unity_version = $UnityVersion
            render_pipeline = $RenderPipeline
            architecture = $Architecture.Value
            source_root = $SourceRoots
            dependency_injection = $DependencyInjection
            async_backend = $AsyncBackend
            tween_backend = $TweenBackend
            target_platform = @("unknown")
            response_language = "ko"
            log_language = "ko"
            author_name = "윤승종"
            private_field_prefix = "m_"
            ui_callback_prefix = "func_"
            region_policy = "encouraged"
            xml_documentation_policy = "all_methods"
            gpu_resident_drawer = $OptimizationStates.GpuResidentDrawer
            gpu_occlusion_culling = $OptimizationStates.GpuOcclusionCulling
            stp = $OptimizationStates.Stp
            mesh_lod = $OptimizationStates.MeshLod
            exclude_root = @("Library", "Temp", "Logs", "obj", "UserSettings", "Packages", ".git", ".agents", ".agents-backup", "Assets/Plugins", "Assets/ThirdParty")
        }
        if ($TestRoots.Count -gt 0)
        {
            $Values.Insert(7, "test_root", $TestRoots)
        }
        $Profile = New-HarnessDetectionProfile -Values $Values
        [void](Test-HarnessProfile -Profile $Profile -SchemaPath $SchemaPath)

        $LexicalProfilePath = [System.IO.Path]::GetFullPath($ProfilePath)
        $LexicalReportPath = [System.IO.Path]::GetFullPath($ReportPath)
        if ((Test-HarnessReparsePoint -Path $LexicalProfilePath) -or (Test-HarnessReparsePoint -Path $LexicalReportPath))
        {
            return New-DetectionResult -ExitCode 2 -Output "[PowerShell 감지] 출력 대상 엔트리로 재파싱 지점을 사용할 수 없습니다."
        }
        $FullProfilePath = Get-HarnessProfileCanonicalPath -Path $LexicalProfilePath
        $FullReportPath = Get-HarnessProfileCanonicalPath -Path $LexicalReportPath
        if ([string]::Equals($FullProfilePath, $FullReportPath, (Get-HarnessPathComparison)))
        {
            return New-DetectionResult -ExitCode 2 -Output "[PowerShell 감지] 프로필과 보고서 출력 경로를 분리해야 합니다."
        }
        if ((Test-Path -LiteralPath $FullProfilePath -PathType Container) -or (Test-Path -LiteralPath $FullReportPath -PathType Container))
        {
            return New-DetectionResult -ExitCode 2 -Output "[PowerShell 감지] 프로필 또는 보고서 출력 경로로 디렉터리를 사용할 수 없습니다."
        }
        $ProfileExisted = Test-Path -LiteralPath $FullProfilePath -PathType Leaf
        $OriginalProfileBytes = if ($ProfileExisted) { [System.IO.File]::ReadAllBytes($FullProfilePath) } else { $null }
        $ReportExisted = Test-Path -LiteralPath $FullReportPath -PathType Leaf
        $OriginalReportBytes = if ($ReportExisted) { [System.IO.File]::ReadAllBytes($FullReportPath) } else { $null }

        $Context = [ordered]@{
            project_name = $Values["project_name"]
            unity_version = $UnityVersion
            render_pipeline = $RenderPipeline
            package_evidence = $PackageEvidence
            architecture = $Architecture.Value
            architecture_confidence = $Architecture.Confidence
            architecture_evidence = $Architecture.Evidence
            architecture_conflict = $Architecture.Conflict
            dependency_injection = $DependencyInjection
            di_confidence = $DependencyInjectionDetection.Confidence
            di_evidence = $DependencyInjectionDetection.Evidence
            async_backend = $AsyncBackend
            async_confidence = $AsyncBackendDetection.Confidence
            async_evidence = $AsyncBackendDetection.Evidence
            tween_backend = $TweenBackend
            tween_confidence = $TweenBackendDetection.Confidence
            tween_evidence = $TweenBackendDetection.Evidence
            source_roots = $SourceRoots
            test_roots = $TestRoots
            gpu_resident_drawer = $OptimizationStates.GpuResidentDrawer
            gpu_occlusion_culling = $OptimizationStates.GpuOcclusionCulling
            stp = $OptimizationStates.Stp
            mesh_lod = $OptimizationStates.MeshLod
            comparison_profile_path = $ComparisonProfilePath
            candidate_profile_path = $FullProfilePath
            schema_path = $SchemaPath
        }
        try
        {
            Write-HarnessProfile -Profile $Profile -SchemaPath $SchemaPath -OutputPath $FullProfilePath
            if ($null -ne $script:HarnessDetectionReportWriter)
            {
                & $script:HarnessDetectionReportWriter $FullReportPath $Context
            }
            else
            {
                Write-DetectionReport -ReportPath $FullReportPath -Context $Context
            }
        }
        catch
        {
            $WriteDiagnostic = $_.Exception.Message
            $RecoveryErrors = New-Object 'System.Collections.Generic.List[string]'
            try
            {
                if ($ProfileExisted)
                {
                    [System.IO.File]::WriteAllBytes($FullProfilePath, $OriginalProfileBytes)
                }
                elseif (Test-Path -LiteralPath $FullProfilePath -PathType Leaf)
                {
                    Remove-Item -LiteralPath $FullProfilePath -Force
                }
            }
            catch
            {
                [void]$RecoveryErrors.Add("프로필: $($_.Exception.Message)")
            }
            try
            {
                if ($ReportExisted)
                {
                    [System.IO.File]::WriteAllBytes($FullReportPath, $OriginalReportBytes)
                }
                elseif (Test-Path -LiteralPath $FullReportPath -PathType Leaf)
                {
                    Remove-Item -LiteralPath $FullReportPath -Force
                }
            }
            catch
            {
                [void]$RecoveryErrors.Add("보고서: $($_.Exception.Message)")
            }
            if ($RecoveryErrors.Count -gt 0)
            {
                return New-DetectionResult -ExitCode 4 -Output ("[PowerShell 감지] 출력 실패 후 기존 프로필/보고서 복구에 실패했습니다: " + [string]::Join("; ", $RecoveryErrors))
            }
            return New-DetectionResult -ExitCode 2 -Output "[PowerShell 감지] 프로필과 보고서를 원자적으로 기록할 수 없습니다: $WriteDiagnostic"
        }
        return New-DetectionResult -ExitCode 0 -Output "[PowerShell 감지] pending 프로필과 감지 보고서를 생성했습니다."
    }
    catch
    {
        return New-DetectionResult -ExitCode 4 -Output "[PowerShell 감지] $($_.Exception.Message)"
    }
}
