# =============================================================================
# trigger-jenkins-pipeline.ps1
# =============================================================================
# Triggers the Jenkins pipeline from PowerShell and streams console output.
# Uses REST API (works on Windows; avoids Jenkins CLI WebSocket issues).
#
# Setup:
#   1. Copy scripts/jenkins.local.env.example -> scripts/jenkins.local.env
#   2. Set JENKINS_TOKEN (generate at http://localhost:8082/user/admin/configure)
#   3. Run: .\scripts\trigger-jenkins-pipeline.ps1
# =============================================================================

param(
    [Parameter(Mandatory = $false, Position = 0)]
    [string]$JobName = "pipeline",

    [string]$JenkinsUrl = "http://localhost:8082",
    [string]$User       = "admin",
    [string]$Token      = $env:JENKINS_TOKEN,
    [string]$PollSeconds = "10",
    [int]$MaxWaitMinutes = "30"
)

# Load local config (gitignored)
$localEnv = Join-Path $PSScriptRoot "jenkins.local.env"
if (Test-Path $localEnv) {
    Get-Content $localEnv | ForEach-Object {
        if ($_ -match '^\s*([^#=]+)=(.*)$') {
            $name  = $matches[1].Trim()
            $value = $matches[2].Trim().Trim('"')
            switch ($name) {
                "JENKINS_URL"   { if (-not $PSBoundParameters.ContainsKey("JenkinsUrl")) { $JenkinsUrl = $value } }
                "JENKINS_USER"  { if (-not $PSBoundParameters.ContainsKey("User")) { $User = $value } }
                "JENKINS_TOKEN" { if (-not $Token) { $Token = $value } }
                "JOB_NAME"      { if (-not $PSBoundParameters.ContainsKey("JobName")) { $JobName = $value } }
            }
        }
    }
}

if (-not $Token) {
    Write-Host "ERROR: Jenkins API token required." -ForegroundColor Red
    Write-Host "Generate at: $JenkinsUrl/user/$User/configure -> API Token -> Add new Token"
    Write-Host 'Then set: $env:JENKINS_TOKEN = "your-token"  OR edit scripts/jenkins.local.env'
    exit 1
}

$cred    = New-Object PSCredential($User, (ConvertTo-SecureString $Token -AsPlainText -Force))
$session = New-Object Microsoft.PowerShell.Commands.WebRequestSession

function Get-JenkinsCrumb {
    $resp = Invoke-WebRequest -Uri "$JenkinsUrl/crumbIssuer/api/json" -Credential $cred -WebSession $session -UseBasicParsing
    return ($resp.Content | ConvertFrom-Json)
}

function Start-JenkinsBuild {
    param([string]$Job)
    $crumb = Get-JenkinsCrumb
    $headers = @{ $crumb.crumbRequestField = $crumb.crumb }
    Invoke-WebRequest -Uri "$JenkinsUrl/job/$Job/build?delay=0sec" -Method Post `
        -Credential $cred -WebSession $session -Headers $headers -UseBasicParsing | Out-Null
}

function Get-LastBuild {
    param([string]$Job)
    $resp = Invoke-WebRequest -Uri "$JenkinsUrl/job/$Job/lastBuild/api/json" -Credential $cred -UseBasicParsing
    return ($resp.Content | ConvertFrom-Json)
}

function Get-BuildConsole {
    param([string]$Job, [int]$Number)
    $resp = Invoke-WebRequest -Uri "$JenkinsUrl/job/$Job/$Number/consoleText" -Credential $cred -UseBasicParsing
    return $resp.Content
}

Write-Host ""
Write-Host "============================================================"
Write-Host "  Jenkins Pipeline Trigger (REST API)"
Write-Host "  URL  : $JenkinsUrl"
Write-Host "  User : $User"
Write-Host "  Job  : $JobName"
Write-Host "============================================================"
Write-Host ""

$before = Get-LastBuild -Job $JobName
$beforeNum = if ($before.number) { [int]$before.number } else { 0 }

Write-Host ">>> Triggering build..."
Start-JenkinsBuild -Job $JobName

# Wait for new build number
$newBuildNum = $null
for ($i = 0; $i -lt 30; $i++) {
    Start-Sleep -Seconds 2
    $last = Get-LastBuild -Job $JobName
    if ($last.number -gt $beforeNum) {
        $newBuildNum = [int]$last.number
        break
    }
}

if (-not $newBuildNum) {
    Write-Host "ERROR: Build was not queued." -ForegroundColor Red
    exit 1
}

Write-Host ">>> Build #$newBuildNum started. Streaming console..."
Write-Host ""

$maxLoops = ($MaxWaitMinutes * 60) / [int]$PollSeconds
$lastPrinted = 0

for ($loop = 1; $loop -le $maxLoops; $loop++) {
    $build = Invoke-WebRequest -Uri "$JenkinsUrl/job/$JobName/$newBuildNum/api/json" -Credential $cred -UseBasicParsing
    $info  = ($build.Content | ConvertFrom-Json)
    $console = Get-BuildConsole -Job $JobName -Number $newBuildNum
    $lines = $console -split "`n"

    if ($lines.Count -gt $lastPrinted) {
        $lines[$lastPrinted..($lines.Count - 1)] | ForEach-Object { Write-Host $_ }
        $lastPrinted = $lines.Count
    }

    if (-not $info.building) {
        Write-Host ""
        if ($info.result -eq "SUCCESS") {
            Write-Host ">>> BUILD SUCCESS: $JobName #$newBuildNum" -ForegroundColor Green
            exit 0
        } else {
            Write-Host ">>> BUILD FAILED: $JobName #$newBuildNum (result: $($info.result))" -ForegroundColor Red
            exit 1
        }
    }

    Start-Sleep -Seconds ([int]$PollSeconds)
}

Write-Host ">>> TIMEOUT waiting for build #$newBuildNum" -ForegroundColor Yellow
exit 2
