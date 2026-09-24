param(
    [string]$ProjectsRoot = (Join-Path $PSScriptRoot "projects"),
    [switch]$Quiet
)

$ErrorActionPreference = "Continue"
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Write-NormalizeLog([string]$Message) {
    if (-not $Quiet) {
        Write-Host "[ClaudeSessions] $Message"
    }
}

function Get-ClaudeFolderName([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) { return $null }

    try {
        $full = [System.IO.Path]::GetFullPath($Path.TrimEnd('\', '/'))
    }
    catch {
        return $null
    }

    # Claude Code currently creates a lowercase drive letter on Windows.
    if ($full -match '^[A-Z]:') {
        $full = $full.Substring(0, 1).ToLowerInvariant() + $full.Substring(1)
    }

    return [regex]::Replace($full, '[^A-Za-z0-9]', '-')
}

function Get-CwdFromJsonl([string]$Path) {
    try {
        $match = Select-String -LiteralPath $Path -Pattern '"cwd"\s*:' -ErrorAction SilentlyContinue |
            Select-Object -First 1

        if ($match) {
            $obj = $match.Line | ConvertFrom-Json
            if ($obj.cwd) {
                return [string]$obj.cwd
            }
        }
    }
    catch {}

    return $null
}

function Get-SessionVersion([string]$Path) {
    try {
        $lines = @(Get-Content -LiteralPath $Path -Tail 120 -ErrorAction SilentlyContinue)

        for ($i = $lines.Count - 1; $i -ge 0; $i--) {
            try {
                $obj = $lines[$i] | ConvertFrom-Json
                if ($obj.timestamp) {
                    $dto = [DateTimeOffset]::Parse([string]$obj.timestamp)
                    return $dto.UtcTicks
                }
            }
            catch {}
        }

        return (Get-Item -LiteralPath $Path).LastWriteTimeUtc.Ticks
    }
    catch {
        return 0
    }
}

function Write-JsonlForCwd(
    [string]$SourcePath,
    [string]$TargetPath,
    [string]$TargetCwd
) {
    $raw = [System.IO.File]::ReadAllText($SourcePath)
    $jsonCwd = ConvertTo-Json -InputObject $TargetCwd -Compress

    # Only rewrite the JSON "cwd" property. Paths mentioned by the user or Claude
    # inside conversation text are deliberately left untouched.
    $pattern = '"cwd"\s*:\s*"(?:\\.|[^"\\])*"'
    $replacement = '"cwd":' + $jsonCwd
    $rewritten = [regex]::Replace(
        $raw,
        $pattern,
        [System.Text.RegularExpressions.MatchEvaluator]{
            param($m)
            return $replacement
        }
    )

    [System.IO.File]::WriteAllText($TargetPath, $rewritten, $Utf8NoBom)
}

function Copy-SessionAuxiliaryData(
    [string]$SourceAliasDir,
    [string]$TargetAliasDir,
    [string]$SessionId,
    [string]$TargetCwd
) {
    $sourceAux = Join-Path $SourceAliasDir $SessionId
    if (-not (Test-Path -LiteralPath $sourceAux -PathType Container)) {
        return
    }

    $targetAux = Join-Path $TargetAliasDir $SessionId
    New-Item -ItemType Directory -Force -Path $targetAux | Out-Null

    Copy-Item -Path (Join-Path $sourceAux '*') -Destination $targetAux -Recurse -Force -ErrorAction SilentlyContinue

    # Subagent transcripts can also carry cwd.
    Get-ChildItem -LiteralPath $targetAux -Recurse -File -Filter *.jsonl -ErrorAction SilentlyContinue |
        ForEach-Object {
            try {
                $raw = [System.IO.File]::ReadAllText($_.FullName)
                $jsonCwd = ConvertTo-Json -InputObject $TargetCwd -Compress
                $pattern = '"cwd"\s*:\s*"(?:\\.|[^"\\])*"'
                $replacement = '"cwd":' + $jsonCwd
                $rewritten = [regex]::Replace(
                    $raw,
                    $pattern,
                    [System.Text.RegularExpressions.MatchEvaluator]{
                        param($m)
                        return $replacement
                    }
                )
                [System.IO.File]::WriteAllText($_.FullName, $rewritten, $Utf8NoBom)
            }
            catch {}
        }
}

function Get-LocalProjectCandidates(
    [string]$ProjectName,
    [string[]]$KnownCwds
) {
    $found = New-Object System.Collections.Generic.List[string]

    foreach ($cwd in @($KnownCwds)) {
        if (-not [string]::IsNullOrWhiteSpace($cwd) -and
            (Test-Path -LiteralPath $cwd -PathType Container)) {
            if (-not $found.Contains($cwd)) {
                $found.Add((Get-Item -LiteralPath $cwd).FullName)
            }
        }
    }

    $roots = @(
        'C:\dev',
        (Join-Path $env:USERPROFILE 'Documents\test'),
        (Join-Path $env:USERPROFILE 'Documents'),
        (Join-Path $env:USERPROFILE 'source\repos'),
        (Join-Path $env:USERPROFILE 'Projects'),
        (Join-Path $env:USERPROFILE 'Desktop')
    )

    if (-not [string]::IsNullOrWhiteSpace($env:CLAUDE_PROJECT_ROOTS)) {
        $roots += @($env:CLAUDE_PROJECT_ROOTS -split ';')
    }

    foreach ($root in @($roots | Select-Object -Unique)) {
        if ([string]::IsNullOrWhiteSpace($root) -or
            -not (Test-Path -LiteralPath $root -PathType Container)) {
            continue
        }

        # Direct child: C:\dev\DCO
        $direct = Join-Path $root $ProjectName
        if (Test-Path -LiteralPath $direct -PathType Container) {
            $full = (Get-Item -LiteralPath $direct).FullName
            if (-not $found.Contains($full)) {
                $found.Add($full)
            }
        }

        # One grouping level: C:\dev\group\DCO
        Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue |
            ForEach-Object {
                $nested = Join-Path $_.FullName $ProjectName
                if (Test-Path -LiteralPath $nested -PathType Container) {
                    $full = (Get-Item -LiteralPath $nested).FullName
                    if (-not $found.Contains($full)) {
                        $found.Add($full)
                    }
                }
            }
    }

    return @($found)
}

function Get-TextFromMessage($Message) {
    if ($null -eq $Message) { return $null }

    if ($Message -is [string]) {
        return $Message
    }

    if ($Message.PSObject.Properties.Name -contains 'content') {
        $content = $Message.content

        if ($content -is [string]) {
            return $content
        }

        foreach ($block in @($content)) {
            if ($null -ne $block -and
                ($block.PSObject.Properties.Name -contains 'text') -and
                -not [string]::IsNullOrWhiteSpace([string]$block.text)) {
                return [string]$block.text
            }
        }
    }

    return $null
}

function Get-SessionMetadata(
    [System.IO.FileInfo]$File,
    [string]$ProjectPath
) {
    $sessionId = $File.BaseName
    $firstPrompt = $null
    $summary = $null
    $customTitle = $null
    $gitBranch = ''
    $messageCount = 0
    $created = $null
    $modified = $null
    $isSidechain = $false

    try {
        foreach ($line in [System.IO.File]::ReadLines($File.FullName)) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }

            try {
                $obj = $line | ConvertFrom-Json
            }
            catch {
                continue
            }

            if (($obj.PSObject.Properties.Name -contains 'sessionId') -and $obj.sessionId) {
                $sessionId = [string]$obj.sessionId
            }

            if (($obj.PSObject.Properties.Name -contains 'gitBranch') -and $obj.gitBranch) {
                $gitBranch = [string]$obj.gitBranch
            }

            if (($obj.PSObject.Properties.Name -contains 'isSidechain') -and $obj.isSidechain) {
                $isSidechain = [bool]$obj.isSidechain
            }

            if ($obj.timestamp) {
                try {
                    $dto = [DateTimeOffset]::Parse([string]$obj.timestamp)
                    if (($null -eq $created) -or ($dto -lt $created)) { $created = $dto }
                    if (($null -eq $modified) -or ($dto -gt $modified)) { $modified = $dto }
                }
                catch {}
            }

            $type = [string]$obj.type

            if ($type -eq 'user' -or $type -eq 'assistant') {
                $messageCount++
            }

            if (($type -eq 'user') -and [string]::IsNullOrWhiteSpace($firstPrompt)) {
                $text = Get-TextFromMessage $obj.message
                if (-not [string]::IsNullOrWhiteSpace($text)) {
                    $firstPrompt = $text
                }
            }

            if (($type -eq 'summary') -and $obj.summary) {
                $summary = [string]$obj.summary
            }

            if ($type -eq 'custom-title') {
                if ($obj.customTitle) {
                    $customTitle = [string]$obj.customTitle
                }
                elseif ($obj.title) {
                    $customTitle = [string]$obj.title
                }
            }
        }
    }
    catch {}

    if ([string]::IsNullOrWhiteSpace($firstPrompt)) {
        $firstPrompt = "Session $sessionId"
    }

    if ($firstPrompt.Length -gt 500) {
        $firstPrompt = $firstPrompt.Substring(0, 500)
    }

    # A non-empty summary makes the picker more robust across Claude Code
    # versions that have had sessions-index regressions.
    if ([string]::IsNullOrWhiteSpace($summary)) {
        $summary = $firstPrompt
    }

    if ($summary.Length -gt 500) {
        $summary = $summary.Substring(0, 500)
    }

    if ($null -eq $created) {
        $created = [DateTimeOffset]$File.CreationTimeUtc
    }

    if ($null -eq $modified) {
        $modified = [DateTimeOffset]$File.LastWriteTimeUtc
    }

    $unixEpoch = [DateTime]::SpecifyKind(
        [DateTime]::Parse('1970-01-01T00:00:00'),
        [DateTimeKind]::Utc
    )
    $fileMtime = [int64](($File.LastWriteTimeUtc - $unixEpoch).TotalMilliseconds)

    $entry = [ordered]@{
        sessionId   = $sessionId
        fullPath    = $File.FullName
        fileMtime   = $fileMtime
        firstPrompt = $firstPrompt
        summary     = $summary
        messageCount = $messageCount
        created     = $created.UtcDateTime.ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
        modified    = $modified.UtcDateTime.ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
        gitBranch   = $gitBranch
        projectPath = $ProjectPath
        isSidechain = $isSidechain
    }

    if (-not [string]::IsNullOrWhiteSpace($customTitle)) {
        $entry['customTitle'] = $customTitle
    }

    return [PSCustomObject]$entry
}

function Rebuild-SessionsIndex([object]$Alias) {
    try {
        $entries = @()

        foreach ($file in @(
            Get-ChildItem -LiteralPath $Alias.Dir -File -Filter *.jsonl -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTimeUtc
        )) {
            $entries += Get-SessionMetadata -File $file -ProjectPath $Alias.Cwd
        }

        $index = [ordered]@{
            version      = 1
            entries      = $entries
            originalPath = $Alias.Cwd
        }

        $json = $index | ConvertTo-Json -Depth 50
        [System.IO.File]::WriteAllText(
            (Join-Path $Alias.Dir 'sessions-index.json'),
            $json,
            $Utf8NoBom
        )
    }
    catch {
        Write-NormalizeLog "Impossible de reconstruire sessions-index.json pour $($Alias.Cwd)"
    }
}

if (-not (Test-Path -LiteralPath $ProjectsRoot -PathType Container)) {
    exit 0
}

$aliasRecords = @()

foreach ($dir in @(Get-ChildItem -LiteralPath $ProjectsRoot -Directory -ErrorAction SilentlyContinue)) {
    $cwd = $null

    $candidateFiles = @(
        Get-ChildItem -LiteralPath $dir.FullName -File -Filter *.jsonl -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 10
    )

    foreach ($file in $candidateFiles) {
        $cwd = Get-CwdFromJsonl $file.FullName
        if ($cwd) { break }
    }

    if (-not $cwd) { continue }

    try {
        $cleanCwd = $cwd.TrimEnd('\', '/')
        $projectName = Split-Path -Path $cleanCwd -Leaf
    }
    catch {
        continue
    }

    if ([string]::IsNullOrWhiteSpace($projectName)) { continue }

    $aliasRecords += [PSCustomObject]@{
        ProjectName = $projectName
        Cwd         = $cwd
        Dir         = $dir.FullName
        Key         = $dir.Name
    }
}

if ($aliasRecords.Count -eq 0) {
    exit 0
}

$changed = 0
$groups = $aliasRecords | Group-Object { $_.ProjectName.ToLowerInvariant() }

foreach ($group in $groups) {
    $groupChangedStart = $changed
    $aliases = @($group.Group)
    $projectName = $aliases[0].ProjectName

    # Discover the same project on this machine (for example C:\dev\DCO)
    # without requiring a per-PC mapping file.
    $localCandidates = Get-LocalProjectCandidates `
        -ProjectName $projectName `
        -KnownCwds @($aliases | ForEach-Object { $_.Cwd })

    foreach ($localPath in $localCandidates) {
        $alreadyKnown = $false

        foreach ($alias in $aliases) {
            if ([string]::Equals(
                [System.IO.Path]::GetFullPath($alias.Cwd.TrimEnd('\', '/')),
                [System.IO.Path]::GetFullPath($localPath.TrimEnd('\', '/')),
                [System.StringComparison]::OrdinalIgnoreCase
            )) {
                $alreadyKnown = $true
                break
            }
        }

        if ($alreadyKnown) { continue }

        $key = Get-ClaudeFolderName $localPath
        if (-not $key) { continue }

        $targetDir = Join-Path $ProjectsRoot $key
        New-Item -ItemType Directory -Force -Path $targetDir | Out-Null

        $aliases += [PSCustomObject]@{
            ProjectName = $projectName
            Cwd         = $localPath
            Dir         = $targetDir
            Key         = $key
        }

        Write-NormalizeLog "Alias detecte pour $projectName : $localPath"
        $changed++
    }

    # Build one logical session set across every path alias for this project.
    $sessionRecords = @()

    foreach ($alias in $aliases) {
        Get-ChildItem -LiteralPath $alias.Dir -File -Filter *.jsonl -ErrorAction SilentlyContinue |
            ForEach-Object {
                $sessionRecords += [PSCustomObject]@{
                    Id      = $_.BaseName
                    File    = $_.FullName
                    Alias   = $alias
                    Version = Get-SessionVersion $_.FullName
                }
            }
    }

    foreach ($sessionGroup in @($sessionRecords | Group-Object Id)) {
        $source = $null

        foreach ($record in $sessionGroup.Group) {
            if (($null -eq $source) -or ($record.Version -gt $source.Version)) {
                $source = $record
            }
        }

        if ($null -eq $source) { continue }

        foreach ($alias in $aliases) {
            $targetFile = Join-Path $alias.Dir ("{0}.jsonl" -f $sessionGroup.Name)
            $targetVersion = 0

            if (Test-Path -LiteralPath $targetFile -PathType Leaf) {
                $targetVersion = Get-SessionVersion $targetFile
            }

            if (($targetVersion -lt $source.Version) -or
                -not (Test-Path -LiteralPath $targetFile -PathType Leaf)) {
                try {
                    Write-JsonlForCwd `
                        -SourcePath $source.File `
                        -TargetPath $targetFile `
                        -TargetCwd $alias.Cwd

                    Copy-SessionAuxiliaryData `
                        -SourceAliasDir $source.Alias.Dir `
                        -TargetAliasDir $alias.Dir `
                        -SessionId $sessionGroup.Name `
                        -TargetCwd $alias.Cwd

                    $changed++
                }
                catch {
                    Write-NormalizeLog "Impossible de recopier $($sessionGroup.Name) vers $($alias.Cwd)"
                }
            }
        }
    }

    # Rebuild the picker index only when paths/sessions changed, or when the
    # index is missing/staler than its newest transcript. This avoids rescanning
    # large JSONL files every five minutes unnecessarily.
    $needIndexRebuild = ($changed -gt $groupChangedStart)

    if (-not $needIndexRebuild) {
        foreach ($alias in $aliases) {
            $indexPath = Join-Path $alias.Dir 'sessions-index.json'
            $newestSession = Get-ChildItem -LiteralPath $alias.Dir -File -Filter *.jsonl -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTimeUtc -Descending |
                Select-Object -First 1

            if ($null -eq $newestSession) {
                continue
            }

            if (-not (Test-Path -LiteralPath $indexPath -PathType Leaf)) {
                $needIndexRebuild = $true
                break
            }

            $indexItem = Get-Item -LiteralPath $indexPath
            if ($indexItem.LastWriteTimeUtc -lt $newestSession.LastWriteTimeUtc) {
                $needIndexRebuild = $true
                break
            }
        }
    }

    if ($needIndexRebuild) {
        foreach ($alias in $aliases) {
            Rebuild-SessionsIndex -Alias $alias
        }
    }
}

if ($changed -gt 0) {
    Write-NormalizeLog "$changed adaptation(s) de chemin/session effectuee(s)."
}

exit 0
