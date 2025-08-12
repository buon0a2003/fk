oh-my-posh init pwsh --config "C:\Users\PhanLys\Posh\1_shell.omp.json" | Invoke-Expression
cls
Function pa { php artisan $args }

# FK (Fix Command) Tool - Auto-installed 08/07/2025 11:03:38
$Error.Clear()
$FKExePath = "D:\fk\dist\fk.exe"

function fk {
    param([switch]$y)
    
    $last = (Get-History -Count 1).CommandLine
    $err = if ($Error.Count -gt 0) { $Error[0] | Out-String } else { "" }

    $isExternalTool = $false

    if ($last -and $err -eq "") {
        $isExternalTool = $true
    }

    if ($isExternalTool -and $LASTEXITCODE -ne 0) {
        $formattedError = nativeOutput -Command $last
        $err = $formattedError
    }

    $cmdB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($last))
    $errB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($err))

    $json = & $FKExePath --shell "powershell" --cmd-b64 $cmdB64 --err-b64 $errB64

    if ($LASTEXITCODE -ne 0) { 
        Write-Host $json -ForegroundColor Red
        return 
    }

    $obj = $json | ConvertFrom-Json
    if (-not $obj -or -not $obj.command) {
        Write-Host "No fix available" -ForegroundColor Yellow
        return
    }

    Write-Host "→ $($obj.command)" -ForegroundColor Green
    if (-not $y) {
        $ans = Read-Host "Run the command? [y/N]"
        if ($ans -notin @('y', 'Y')) { return }
    }
    Invoke-Expression $obj.command

    Clear-Variable -Name last, err -ErrorAction SilentlyContinue
    $Error.Clear()
}

function nativeOutput {
    param([string]$Command)
    
    if (-not $Command -and (Get-History -Count 1)) {
        $Command = (Get-History -Count 1).CommandLine
    }
    
    if (-not $Command) {
        return "No command to re-run"
    }
    
    $commandParts = $Command -split '\s+', 0, 'RegexMatch'
    $nativeAppFilePath = $commandParts[0]
    $nativeAppParam = $commandParts[1..($commandParts.Length - 1)]
    
    try {
        $nativeCmdResult = & $nativeAppFilePath $nativeAppParam 2>&1
        $errorMessage = @()
        
        if ($LASTEXITCODE -ne 0) {
            $errorMessage += $nativeCmdResult
        } else {
            $errorMessage += $nativeCmdResult
        }
        
        return ($errorMessage)
    }
    catch {
        return "Failed to re-run command: $Command`nError: $($_.Exception.Message)"
    }
}

# FK Tool installed and ready to use!
# Use 'fk' after any failed command to get AI-powered fixes
