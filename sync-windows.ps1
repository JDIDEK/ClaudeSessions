param(
    [ValidateSet("push", "full")]
    [string]$Mode = "push"
)

$ErrorActionPreference = "Continue"
$Repo = $PSScriptRoot
$Projects = Join-Path $Repo "projects"
$Normalizer = Join-Path $Repo "normalize-windows.ps1"
$StateDir = Join-Path $env:LOCALAPPDATA "ClaudeSessions"
$Log = Join-Path $StateDir "sync.log"

New-Item -ItemType Directory -Force -Path $StateDir | Out-Null

function Log([string]$Message) {
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [$env:COMPUTERNAME] [$Mode] $Message"
    Add-Content -Path $Log -Value $line
}

function Normalize-ProjectPaths {
    if (-not (Test-Path -LiteralPath $Normalizer -PathType Leaf)) {
        return
    }

    & $Normalizer -ProjectsRoot $Projects -Quiet

    if ($LASTEXITCODE -ne 0) {
        Log "ATTENTION : normalisation des chemins Claude en erreur."
    }
}

function Commit-ProjectChanges([string]$Reason) {
    & git add -- projects
    if ($LASTEXITCODE -ne 0) {
        throw "git add a echoue."
    }

    & git diff --cached --quiet -- projects

    if ($LASTEXITCODE -eq 1) {
        $stamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
        & git commit -m "Claude sync - $env:COMPUTERNAME - $stamp - $Reason" -- projects

        if ($LASTEXITCODE -ne 0) {
            throw "git commit a echoue."
        }

        Log "Modifications Claude committees ($Reason)."
    }
    elseif ($LASTEXITCODE -ne 0) {
        throw "Impossible de verifier les changements Git."
    }
}

$mutex = New-Object System.Threading.Mutex($false, "ClaudeSessionsGitSync")
$hasLock = $false

try {
    $hasLock = $mutex.WaitOne(0)

    if (-not $hasLock) {
        Log "Une synchronisation est deja en cours, sortie."
        exit 0
    }

    Set-Location $Repo

    if (-not (Test-Path (Join-Path $Repo ".git"))) {
        throw "Ce script doit etre execute depuis le depot ClaudeSessions."
    }

    New-Item -ItemType Directory -Force -Path $Projects | Out-Null

    $branch = (& git branch --show-current).Trim()

    if ([string]::IsNullOrWhiteSpace($branch)) {
        $branch = "main"
        & git branch -M main

        if ($LASTEXITCODE -ne 0) {
            throw "Impossible de definir la branche main."
        }
    }

    # Avant chaque push, synchroniser les alias de chemins locaux connus
    # (ex. PC boulot Documents\test\DCO <-> PC fixe C:\dev\DCO).
    Normalize-ProjectPaths
    Commit-ProjectChanges "local"

    if ($Mode -eq "full") {
        Log "Recherche de nouveautes distantes."

        & git fetch origin $branch
        $fetchCode = $LASTEXITCODE

        if ($fetchCode -eq 0) {
            & git rev-parse --verify "origin/$branch" 2>$null | Out-Null

            if ($LASTEXITCODE -eq 0) {
                & git rebase "origin/$branch"

                if ($LASTEXITCODE -ne 0) {
                    & git rebase --abort 2>$null
                    throw "Conflit Git pendant le rebase. Rien n'a ete ecrase : rebase annule."
                }

                Log "Nouveautes distantes integrees."

                # Le pull peut avoir apporte des sessions venant d'un chemin
                # utilise sur une autre machine. Les adapter pour ce PC.
                Normalize-ProjectPaths
                Commit-ProjectChanges "post-pull"
            }
        }
    }

    & git push -u origin $branch

    if ($LASTEXITCODE -ne 0) {
        if ($Mode -eq "push") {
            throw "Push refuse. Le depot distant a probablement avance depuis un autre PC. Lance sync-windows.ps1 -Mode full quand Claude est ferme."
        }

        throw "git push a echoue."
    }

    Log "Synchronisation terminee."
}
catch {
    Log "ERREUR : $($_.Exception.Message)"
    Write-Error $_.Exception.Message
    exit 1
}
finally {
    if ($hasLock) {
        try { $mutex.ReleaseMutex() } catch {}
    }

    $mutex.Dispose()
}
