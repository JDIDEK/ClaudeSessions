param(
    [switch]$NoSchedule
)

$ErrorActionPreference = "Stop"

$Repo = $PSScriptRoot
$RepoProjects = Join-Path $Repo "projects"
$ClaudeRoot = Join-Path $env:USERPROFILE ".claude"
$ClaudeProjects = Join-Path $ClaudeRoot "projects"
$SyncScript = Join-Path $Repo "sync-windows.ps1"

function Has-Content([string]$Path) {
    if (-not (Test-Path $Path)) { return $false }
    return $null -ne (Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue | Select-Object -First 1)
}

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    throw "Git n'est pas installe ou n'est pas dans PATH."
}

if (-not (Test-Path (Join-Path $Repo ".git"))) {
    throw "Place setup-windows.ps1 a la racine du depot ClaudeSessions puis relance-le."
}

New-Item -ItemType Directory -Force -Path $ClaudeRoot | Out-Null

# Recuperer d'abord les scripts/donnees deja presents sur le remote.
Set-Location $Repo
$branch = (& git branch --show-current).Trim()
if ([string]::IsNullOrWhiteSpace($branch)) {
    $branch = "main"
    & git branch -M main
}

& git fetch origin $branch 2>$null
if ($LASTEXITCODE -eq 0) {
    & git rev-parse --verify "origin/$branch" 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) {
        & git pull --rebase origin $branch
        if ($LASTEXITCODE -ne 0) {
            throw "Impossible de mettre le depot a jour. Corrige l'etat Git avant de continuer."
        }
    }
}

$repoHasData = Has-Content $RepoProjects
$claudeExists = Test-Path $ClaudeProjects

# Si projects est deja une jonction/symlink, verifier si elle pointe deja vers le repo.
if ($claudeExists) {
    $item = Get-Item -LiteralPath $ClaudeProjects -Force
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        $targetText = ($item.Target -join ";")
        if ($targetText -like "*$RepoProjects*") {
            Write-Host "La jonction Claude -> repo est deja en place."
            $claudeExists = $false
        }
        else {
            throw "$ClaudeProjects est deja un lien vers un autre emplacement. Retire-le manuellement avant de continuer."
        }
    }
}

if ($claudeExists) {
    if (-not $repoHasData) {
        # Premier PC : importer les sessions existantes dans le repo.
        Write-Host "Premier PC detecte : import des sessions Claude actuelles."
        Move-Item -LiteralPath $ClaudeProjects -Destination $RepoProjects
    }
    else {
        # PC suivant : conserver une sauvegarde locale, puis utiliser les sessions du repo.
        $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
        $backup = Join-Path $ClaudeRoot "projects.backup-$stamp-$env:COMPUTERNAME"
        Write-Host "Sessions locales existantes sauvegardees dans : $backup"
        Move-Item -LiteralPath $ClaudeProjects -Destination $backup
    }
}

New-Item -ItemType Directory -Force -Path $RepoProjects | Out-Null

if (-not (Test-Path $ClaudeProjects)) {
    New-Item -ItemType Junction -Path $ClaudeProjects -Target $RepoProjects | Out-Null
    Write-Host "Jonction creee : $ClaudeProjects -> $RepoProjects"
}

# Premier commit/push : scripts + sessions.
& git add -- .gitignore README.md setup-windows.ps1 sync-windows.ps1 setup-linux.sh sync-linux.sh projects
& git diff --cached --quiet
if ($LASTEXITCODE -eq 1) {
    $stamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
    & git commit -m "Initialize ClaudeSessions - $env:COMPUTERNAME - $stamp"
    if ($LASTEXITCODE -ne 0) { throw "Le commit initial a echoue." }
}

& git push -u origin $branch
if ($LASTEXITCODE -ne 0) {
    Write-Warning "Le push a echoue. Authentifie Git/GitHub puis lance : .\sync-windows.ps1 -Mode full"
}

if (-not $NoSchedule) {
    $ps = (Get-Command powershell.exe).Source

    $pushCommand = "`"$ps`" -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$SyncScript`" -Mode push"
    $fullCommand = "`"$ps`" -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$SyncScript`" -Mode full"

    & schtasks.exe /Create /F /TN "ClaudeSessions-Push" /TR $pushCommand /SC MINUTE /MO 5 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Impossible de creer la tache periodique. Tu peux lancer sync-windows.ps1 manuellement."
    }

    & schtasks.exe /Create /F /TN "ClaudeSessions-FullSync-Logon" /TR $fullCommand /SC ONLOGON | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Impossible de creer la tache au logon. Tu peux lancer sync-windows.ps1 -Mode full manuellement apres connexion."
    }
}

Write-Host ""
Write-Host "=== TERMINE ==="
Write-Host "Claude utilise maintenant : $RepoProjects"
Write-Host "Sync automatique : push toutes les 5 min + full sync a l'ouverture de session."
Write-Host "Avant de changer de PC, tu peux forcer :"
Write-Host "  powershell -ExecutionPolicy Bypass -File `"$SyncScript`" -Mode full"
Write-Host ""
Write-Host "Log : $env:LOCALAPPDATA\ClaudeSessions\sync.log"
