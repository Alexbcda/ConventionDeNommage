# Journalisation des temps de chargement onglet planning (diagnostic postes lents).

function Write-PlanningLoadTiming {
    param(
        [Parameter(Mandatory = $true)][string]$Step,
        [string]$Detail = ''
    )
    $installRoot = $null
    try {
        if ($PSScriptRoot -match 'PdfPlanningOptimizer') {
            $installRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..\..') -ErrorAction Stop).Path
        }
    }
    catch { }

    if ([string]::IsNullOrWhiteSpace($installRoot)) {
        $installRoot = 'C:\ASSISTANT'
    }

    $logPath = Join-Path $installRoot 'planning_load.log'
    $ms = 0
    if ($null -ne $script:PlanningLoadTimingStopwatch) {
        $ms = $script:PlanningLoadTimingStopwatch.ElapsedMilliseconds
    }
    $line = '[{0}] +{1,7} ms  {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'), $ms, $Step
    if (-not [string]::IsNullOrWhiteSpace($Detail)) {
        $line += " | $Detail"
    }
    try {
        Add-Content -LiteralPath $logPath -Value $line -Encoding UTF8 -ErrorAction SilentlyContinue
    }
    catch { }
}

function Start-PlanningLoadTimingSession {
    $installRoot = 'C:\ASSISTANT'
    try {
        if ($PSScriptRoot -match 'PdfPlanningOptimizer') {
            $installRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..\..') -ErrorAction Stop).Path
        }
    }
    catch { }

    $logPath = Join-Path $installRoot 'planning_load.log'
    $header = @(
        '',
        ('========== SESSION {0} ==========' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')),
        "PID=$PID PS=$($PSVersionTable.PSVersion) User=$env:USERNAME Machine=$env:COMPUTERNAME"
    )
    try {
        Add-Content -LiteralPath $logPath -Value ($header -join [Environment]::NewLine) -Encoding UTF8
    }
    catch { }

    $script:PlanningLoadTimingStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    Write-PlanningLoadTiming -Step 'session_start'
}

function Write-PlanningLoadTime {
    param([string]$Step)
    Write-PlanningLoadTiming -Step $Step
}
