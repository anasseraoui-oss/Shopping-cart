<#
.SYNOPSIS
    Triggers a Jenkins pipeline from PowerShell and streams the full console output.

.DESCRIPTION
    Equivalent of trigger-jenkins-pipeline.sh for Windows users.
    Uses jenkins-cli.jar to trigger a build and print live logs in the terminal.

.PARAMETER JobName
    Jenkins pipeline job name (e.g. "Shopping-Cart").

.PARAMETER JenkinsUrl
    Jenkins base URL (default: http://localhost:8082).

.PARAMETER User
    Jenkins username (default: admin).

.PARAMETER Token
    Jenkins API token. If omitted, reads $env:JENKINS_TOKEN.

.PARAMETER CliJar
    Path to jenkins-cli.jar (default: .\jenkins-cli.jar).

.EXAMPLE
    # Step 1: Generate API token at:
    #   http://localhost:8082/user/admin/configure -> API Token -> Add new Token

    # Step 2: Set token and trigger:
    $env:JENKINS_TOKEN = "your-copied-token"
    .\scripts\trigger-jenkins-pipeline.ps1 -JobName "Shopping-Cart"

.EXAMPLE
    # Pass token directly:
    .\scripts\trigger-jenkins-pipeline.ps1 -JobName "Shopping-Cart" -Token "abc123"

.NOTES
    Requires Java installed and accessible in PATH.
    Jenkins must be running on port 8082.
#>

param(
    [Parameter(Mandatory = $false, Position = 0)]
    [string]$JobName = "pipeline",

    [string]$JenkinsUrl = "http://localhost:8082",
    [string]$User       = "admin",
    [string]$Token      = $env:JENKINS_TOKEN,
    [string]$CliJar      = ".\jenkins-cli.jar"
)

# Load local config if present (scripts\jenkins.local.env is gitignored)
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

# ---------------------------------------------------------------------------
# Validate API token
# ---------------------------------------------------------------------------
if (-not $Token) {
    Write-Host ""
    Write-Host "ERROR: Jenkins API token is required." -ForegroundColor Red
    Write-Host ""
    Write-Host "  How to generate an API token:" -ForegroundColor Yellow
    Write-Host "    1. Open  http://localhost:8082"
    Write-Host "    2. Log in as admin"
    Write-Host "    3. Click admin (top-right) -> Configure"
    Write-Host "    4. API Token -> Add new Token -> Generate -> Copy"
    Write-Host ""
    Write-Host "  Then run:" -ForegroundColor Yellow
    Write-Host '    $env:JENKINS_TOKEN = "your-token"'
    Write-Host "    .\scripts\trigger-jenkins-pipeline.ps1 -JobName `"Shopping-Cart`""
    Write-Host ""
    exit 1
}

# ---------------------------------------------------------------------------
# Download jenkins-cli.jar if not present
# ---------------------------------------------------------------------------
if (-not (Test-Path $CliJar)) {
    Write-Host ">>> Downloading jenkins-cli.jar from $JenkinsUrl ..."
    Invoke-WebRequest -Uri "$JenkinsUrl/jnlpJars/jenkins-cli.jar" -OutFile $CliJar
    Write-Host ">>> Saved to $CliJar"
}

# ---------------------------------------------------------------------------
# Trigger build and stream logs
# ---------------------------------------------------------------------------
$auth = "${User}:${Token}"

Write-Host ""
Write-Host "============================================================"
Write-Host "  Jenkins Pipeline Trigger"
Write-Host "  URL     : $JenkinsUrl"
Write-Host "  User    : $User"
Write-Host "  Job     : $JobName"
Write-Host "  Mode    : wait + stream logs (-f -s -v)"
Write-Host "============================================================"
Write-Host ""

& java -jar $CliJar `
    -s "$JenkinsUrl/" `
    -auth $auth `
    build $JobName `
    -f -s -v

$exitCode = $LASTEXITCODE

Write-Host ""
if ($exitCode -eq 0) {
    Write-Host ">>> BUILD SUCCESS: $JobName" -ForegroundColor Green
} else {
    Write-Host ">>> BUILD FAILED: $JobName (exit code $exitCode)" -ForegroundColor Red
    Write-Host ">>> Check diagnostics output above for docker logs."
}

exit $exitCode
