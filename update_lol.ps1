# League of Legends Universal Multi-Threaded Updater & Full Downloader
$ErrorActionPreference = "Stop"

# Ensure no zombie processes are running
Get-Process -Name ManifestDownloader -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 300

$toolDir = $PSScriptRoot
$tool = Join-Path $toolDir "ManifestDownloader.exe"
$configFile = Join-Path $toolDir "config.json"

# Load or initialize config
$defaultLoL = "D:\Games\Riot Games\League of Legends"
if (-not (Test-Path $defaultLoL)) {
    $defaultLoL = "C:\Riot Games\League of Legends"
}

$config = @{
    Region = "SG2"
    InstallDir = $defaultLoL
    Threads = 16
    Language = "en_US"
}

if (Test-Path $configFile) {
    try {
        $loaded = Get-Content $configFile -Raw | ConvertFrom-Json
        if ($loaded.Region) { $config.Region = $loaded.Region }
        if ($loaded.InstallDir) { $config.InstallDir = $loaded.InstallDir }
        if ($loaded.Threads) { $config.Threads = $loaded.Threads }
        if ($loaded.Language) { $config.Language = $loaded.Language }
    } catch {}
}

function Save-Config {
    $config | ConvertTo-Json | Set-Content -Path $configFile -Force
}

function Get-LatestManifestInfo([string]$region) {
    Write-Host ">>> Querying Riot API for $region live manifest..." -ForegroundColor Cyan
    $sieve = Invoke-RestMethod -Uri "https://sieve.services.riotcdn.net/api/v1/products/lol/version-sets/$region`?q[platform]=windows"
    $gameRel = $sieve.releases | Where-Object { $_.release.labels.'riot:artifact_type_id'.values -eq 'lol-game-client' } | Select-Object -First 1
    return @{
        ManifestUrl = $gameRel.download.url
        ManifestId = $gameRel.release.id
        Version = $gameRel.compat_version.id.Split('+')[0]
    }
}

function Ensure-ManifestDownloaded([hashtable]$info) {
    $manifestPath = Join-Path $toolDir "$($info.ManifestId).manifest"
    $jsonPath = Join-Path $toolDir "$($info.ManifestId).json"

    if (-not (Test-Path $manifestPath)) {
        Write-Host ">>> Downloading manifest ($($info.ManifestId))..." -ForegroundColor Cyan
        Invoke-WebRequest -Uri $info.ManifestUrl -OutFile $manifestPath
    }
    if (-not (Test-Path $jsonPath)) {
        Write-Host ">>> Generating manifest index..." -ForegroundColor Cyan
        & $tool $manifestPath --print-manifest $jsonPath | Out-Null
    }
    return @{ Manifest = $manifestPath; Json = $jsonPath }
}

function Run-DownloadStream {
    param(
        [string]$Title,
        [string]$ManifestFile,
        [string]$TargetDir,
        [string]$FilterArgs,
        [int64]$TotalExpectedBytes = 0
    )

    $adapter = (Get-NetAdapter | Where-Object { $_.Status -eq 'Up' } | Select-Object -First 1).Name
    $startBytes = (Get-NetAdapterStatistics -Name $adapter -ErrorAction SilentlyContinue).ReceivedBytes
    $lastBytes = $startBytes
    $lastTime = [DateTime]::UtcNow
    $speedMB = 0.0

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $tool
    $psi.Arguments = "`"$ManifestFile`" -o `"$TargetDir`" -l $($config.Language) -n -t $($config.Threads) $FilterArgs -v"
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true

    $proc = [System.Diagnostics.Process]::Start($psi)
    $currentFile = "Connecting to CDN..."

    try {
        while (-not $proc.HasExited) {
            Start-Sleep -Milliseconds 250

            # Drain stdout without blocking so the loop never freezes
            while ($proc.StandardOutput.Peek() -ge 0) {
                $line = $proc.StandardOutput.ReadLine()
                if ($line -match "(Downloading file|Fixing up file|Verifying file)\s+(.+?)(\.\.\.|$)") {
                    $currentFile = $matches[2]
                }
            }

            $now = [DateTime]::UtcNow
            $diff = ($now - $lastTime).TotalSeconds
            $currNetBytes = (Get-NetAdapterStatistics -Name $adapter -ErrorAction SilentlyContinue).ReceivedBytes

            if ($diff -ge 0.5 -and $currNetBytes -gt $lastBytes) {
                $speedMB = [math]::Round((($currNetBytes - $lastBytes) / $diff) / 1MB, 1)
                $lastBytes = $currNetBytes
                $lastTime = $now
            }

            $downBytes = [math]::Max(0, $currNetBytes - $startBytes)
            if ($TotalExpectedBytes -gt 0) {
                $pct = [math]::Min(99, [math]::Max(1, [math]::Round(($downBytes / $TotalExpectedBytes) * 100)))
                $mbDown = [math]::Round($downBytes / 1MB, 1)
                $mbTot = [math]::Round($TotalExpectedBytes / 1MB, 1)
                $status = "$pct% | $speedMB MB/s ($mbDown / $mbTot MB)"

                Write-Progress -Activity $Title -Status $status -PercentComplete $pct -CurrentOperation $currentFile
                $disp = if ($currentFile.Length -gt 38) { "..." + $currentFile.Substring($currentFile.Length - 35) } else { $currentFile }
                Write-Host ("`r[Downloading] [{0,5} MB/s] [{1,3}%] ({2,6}/{3} MB) {4,-38}" -f $speedMB, $pct, $mbDown, $mbTot, $disp) -NoNewline
            } else {
                $mbDown = [math]::Round($downBytes / 1MB, 1)
                Write-Progress -Activity $Title -Status "$speedMB MB/s ($mbDown MB downloaded)" -PercentComplete 50 -CurrentOperation $currentFile
                $disp = if ($currentFile.Length -gt 45) { "..." + $currentFile.Substring($currentFile.Length - 42) } else { $currentFile }
                Write-Host ("`r[Downloading] [{0,5} MB/s] ({1,6} MB) {2,-45}" -f $speedMB, $mbDown, $disp) -NoNewline
            }
        }
        $proc.WaitForExit()
    } finally {
        if (-not $proc.HasExited) { $proc.Kill() }
    }
    Write-Progress -Activity $Title -Completed
    Write-Host ""
}

# Interactive Menu
while ($true) {
    Clear-Host
    Write-Host "==========================================================" -ForegroundColor Cyan
    Write-Host "     League of Legends - Fast Multi-Threaded Tool        " -ForegroundColor Cyan
    Write-Host "==========================================================" -ForegroundColor Cyan
    Write-Host "  Server Region : $($config.Region)" -ForegroundColor Green
    Write-Host "  Install Path  : $($config.InstallDir)" -ForegroundColor Green
    Write-Host "  Threads       : $($config.Threads)" -ForegroundColor Green
    Write-Host "----------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host "  [1] Fast Patch / Update Existing Game    (Recommended)" -ForegroundColor White
    Write-Host "  [2] Full / Clean Game Download           (For new users)" -ForegroundColor White
    Write-Host "  [3] Change Server Region                 (NA, EUW, KR, etc.)" -ForegroundColor White
    Write-Host "  [4] Change Installation Directory" -ForegroundColor White
    Write-Host "  [5] Exit" -ForegroundColor DarkGray
    Write-Host "==========================================================" -ForegroundColor Cyan
    $choice = Read-Host "Select an option [1-5] (Press Enter for 1)"
    if ([string]::IsNullOrWhiteSpace($choice)) { $choice = "1" }

    switch ($choice) {
        "1" {
            # Fast Update
            Clear-Host
            $gameDir = Join-Path $config.InstallDir "Game"
            $backupDir = Join-Path $config.InstallDir "Old_Files_Backup"

            $info = Get-LatestManifestInfo -region $config.Region
            $files = Ensure-ManifestDownloaded -info $info

            Write-Host ">>> Checking files for Patch $($info.Version)..." -ForegroundColor Cyan
            $m = Get-Content $files.Json -Raw | ConvertFrom-Json
            $diffList = [System.Collections.Generic.List[string]]::new()
            $totalBytes = [int64]0

            foreach ($f in $m.files) {
                if ($f.languages.Count -gt 0 -and ($f.languages -notcontains 10)) { continue }
                $p = Join-Path $gameDir $f.path
                $exp = [int64]($f.file_size -replace '[^\d]')
                if (-not (Test-Path $p) -or ((Get-Item $p).Length -ne $exp)) {
                    $diffList.Add($f.path)
                    $totalBytes += $exp
                }
            }

            $count = $diffList.Count
            if ($count -eq 0) {
                Write-Host ">>> All files are already 100% up to date!" -ForegroundColor Green
                pause
                break
            }

            # Close Riot Client if running to release file locks
            $riotProcs = Get-Process -Name *RiotClient*, *LeagueClient* -ErrorAction SilentlyContinue
            if ($riotProcs) {
                Write-Host ">>> Closing Riot Client to release file locks..." -ForegroundColor Yellow
                $riotProcs | Stop-Process -Force -ErrorAction SilentlyContinue
                Start-Sleep -Milliseconds 500
            }

            Write-Host ">>> Found $count outdated files ($([math]::Round($totalBytes / 1MB, 1)) MB). Clearing old versions..." -ForegroundColor Yellow
            if (-not (Test-Path $backupDir)) { New-Item -ItemType Directory -Path $backupDir -Force | Out-Null }
            foreach ($rel in $diffList) {
                $target = Join-Path $gameDir $rel
                if (Test-Path $target) {
                    Move-Item -Path $target -Destination (Join-Path $backupDir ([System.IO.Path]::GetFileName($rel))) -Force -ErrorAction SilentlyContinue
                }
            }

            # Build targeted filter so ManifestDownloader touches ONLY these specific files
            $escapedNames = $diffList | ForEach-Object { [regex]::Escape([System.IO.Path]::GetFileName($_)) }
            $filterRegex = "(" + ($escapedNames -join "|") + ")$"

            Write-Host ">>> Streaming updated files directly from CDN..." -ForegroundColor Cyan
            Run-DownloadStream -Title "Patching League $($info.Version)" -ManifestFile $files.Manifest -TargetDir $gameDir -FilterArgs "-f `"$filterRegex`"" -TotalExpectedBytes $totalBytes

            if (Test-Path $backupDir) { Remove-Item -Recurse -Force $backupDir -ErrorAction SilentlyContinue }
            Write-Host ">>> Patch $($info.Version) successfully applied! Launch Riot Client to play." -ForegroundColor Green
            pause
            break
        }

        "2" {
            # Full Download for new users
            Clear-Host
            Write-Host "=== Fresh / Full Game Download ===" -ForegroundColor Yellow
            Write-Host "Target: $($config.InstallDir)" -ForegroundColor White
            $confirm = Read-Host "Proceed with full download (~25 GB)? (Y/N)"
            if ($confirm -notmatch "^[Yy]") { break }

            $gameDir = Join-Path $config.InstallDir "Game"
            if (-not (Test-Path $gameDir)) { New-Item -ItemType Directory -Path $gameDir -Force | Out-Null }

            $info = Get-LatestManifestInfo -region $config.Region
            $files = Ensure-ManifestDownloaded -info $info

            # Calculate total expected size for clean install
            $mFull = Get-Content $files.Json -Raw | ConvertFrom-Json
            $fullBytes = [int64]0
            foreach ($f in $mFull.files) {
                if ($f.languages.Count -gt 0 -and ($f.languages -notcontains 10)) { continue }
                $fullBytes += [int64]($f.file_size -replace '[^\d]')
            }

            Write-Host ">>> Downloading full clean game client ($($info.Version)) with $($config.Threads) threads..." -ForegroundColor Cyan
            Run-DownloadStream -Title "Full LoL Download ($($info.Version))" -ManifestFile $files.Manifest -TargetDir $gameDir -FilterArgs "--skip-existing" -TotalExpectedBytes $fullBytes

            Write-Host ">>> Full game downloaded! Open Riot Client -> 'Already installed? Locate game' -> select folder." -ForegroundColor Green
            pause
            break
        }

        "3" {
            # Server Selection
            Clear-Host
            Write-Host "=== Select Riot Region / Server ===" -ForegroundColor Cyan
            Write-Host "  1. SG2  - Singapore, Thailand, Philippines, Malaysia, Indonesia (Default)"
            Write-Host "  2. NA1  - North America"
            Write-Host "  3. EUW1 - Europe West"
            Write-Host "  4. EUN1 - Europe Nordic & East"
            Write-Host "  5. KR   - Korea"
            Write-Host "  6. JP1  - Japan"
            Write-Host "  7. TW2  - Taiwan, Hong Kong, Macau"
            Write-Host "  8. VN2  - Vietnam"
            Write-Host "  9. OC1  - Oceania"
            Write-Host " 10. BR1  - Brazil"
            Write-Host " 11. Custom Code"
            Write-Host ""
            $regChoice = Read-Host "Enter selection [1-11]"
            $map = @{
                "1"="SG2"; "2"="NA1"; "3"="EUW1"; "4"="EUN1"; "5"="KR";
                "6"="JP1"; "7"="TW2"; "8"="VN2"; "9"="OC1"; "10"="BR1"
            }
            if ($map.ContainsKey($regChoice)) {
                $config.Region = $map[$regChoice]
            } elseif ($regChoice -eq "11") {
                $custom = Read-Host "Enter Riot region code (e.g. TR1, LA1)"
                if (-not [string]::IsNullOrWhiteSpace($custom)) { $config.Region = $custom.ToUpper() }
            }
            Save-Config
            Write-Host "Region set to: $($config.Region)" -ForegroundColor Green
            Start-Sleep -Seconds 1
        }

        "4" {
            # Change Install Path
            Clear-Host
            Write-Host "=== Change Installation Directory ===" -ForegroundColor Cyan
            Write-Host "Current: $($config.InstallDir)" -ForegroundColor White
            $newPath = Read-Host "Enter new folder path (e.g. C:\Riot Games\League of Legends)"
            if (-not [string]::IsNullOrWhiteSpace($newPath)) {
                $config.InstallDir = $newPath.Trim()
                Save-Config
                Write-Host "Installation path updated." -ForegroundColor Green
            }
            Start-Sleep -Seconds 1
        }

        "5" {
            exit 0
        }
    }
}
