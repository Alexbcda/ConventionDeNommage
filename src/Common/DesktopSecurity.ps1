# DesktopSecurity.ps1 — rate limiting (anti-abus), rotation des journaux (DoS / volumétrie)

if (-not (Get-Variable -Name CN_RequestCount -Scope Script -ErrorAction SilentlyContinue)) {
    $script:CN_RequestCount = 0
    $script:CN_WindowStart = Get-Date
}

function Test-CNRateLimit {
    $now = Get-Date

    if (($now - $script:CN_WindowStart).TotalSeconds -gt 60) {
        $script:CN_RequestCount = 0
        $script:CN_WindowStart = $now
    }

    $script:CN_RequestCount++

    if ($script:CN_RequestCount -gt 50) {
        throw "Trop d'actions. Veuillez patienter."
    }
}

function Rotate-LogIfNeeded {
    param([string]$LogFile)

    if ([string]::IsNullOrWhiteSpace($LogFile)) { return }
    if (-not (Test-Path -LiteralPath $LogFile)) { return }

    $maxSize = 10MB

    if ((Get-Item -LiteralPath $LogFile).Length -gt $maxSize) {
        $backup = "$LogFile.old"
        Move-Item -LiteralPath $LogFile -Destination $backup -Force -ErrorAction SilentlyContinue
    }
}

function Reset-CNRateLimitForTests {
    $script:CN_RequestCount = 0
    $script:CN_WindowStart = Get-Date
}
