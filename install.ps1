#Requires -Version 5.1

<#
.SYNOPSIS
    Installs the FK (Fix Command) tool to PowerShell profile
.DESCRIPTION
    This script installs the FK command-line fixer by:
    1. Prompting for Gemini API key and setting it as environment variable
    2. Adding FK functions to PowerShell profile
    3. Setting up the executable path
#>

param(
    [string]$ExePath,
    [switch]$Force
)

# Colors for output
$colors = @{
    Success = "Green"
    Warning = "Yellow" 
    Error = "Red"
    Info = "Cyan"
}

function Write-ColoredOutput {
    param([string]$Message, [string]$Color = "White")
    Write-Host $Message -ForegroundColor $colors[$Color]
}

function Test-Administrator {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-GeminiApiKey {
    $existingKey = [Environment]::GetEnvironmentVariable("GEMINI_API_KEY", "User")
    
    if ($existingKey -and -not $Force) {
        Write-ColoredOutput "Gemini API key is already set." "Info"
        $response = Read-Host "Do you want to update it? [y/N]"
        if ($response -notin @('y', 'Y')) {
            return $existingKey
        }
    }
    
    Write-ColoredOutput "`nTo use FK, you need a Gemini API key from Google AI Studio:" "Info"
    Write-ColoredOutput "1. Go to https://aistudio.google.com/app/apikey" "Info"
    Write-ColoredOutput "2. Create a new API key" "Info"
    Write-ColoredOutput "3. Copy the key and paste it below" "Info"
    
    do {
        $apiKey = Read-Host "`nEnter your Gemini API key"
        if ([string]::IsNullOrWhiteSpace($apiKey)) {
            Write-ColoredOutput "API key cannot be empty. Please try again." "Warning"
        }
    } while ([string]::IsNullOrWhiteSpace($apiKey))
    
    return $apiKey.Trim()
}

function Set-EnvironmentVariable {
    param([string]$ApiKey)
    
    try {
        # Set for current session
        $env:GEMINI_API_KEY = $ApiKey
        
        # Set permanently for user
        [Environment]::SetEnvironmentVariable("GEMINI_API_KEY", $ApiKey, "User")
        
        Write-ColoredOutput "✓ Gemini API key set successfully" "Success"
        return $true
    }
    catch {
        Write-ColoredOutput "✗ Failed to set environment variable: $($_.Exception.Message)" "Error"
        return $false
    }
}

function Get-ExecutablePath {
    if ($ExePath -and (Test-Path $ExePath)) {
        return $ExePath
    }
    
    # Look for fk.exe in common locations
    $searchPaths = @(
        ".\fk.exe",
        ".\dist\fk.exe", 
        "D:\fk\dist\fk.exe",
        "C:\tools\fk\fk.exe"
    )
    
    foreach ($path in $searchPaths) {
        if (Test-Path $path) {
            return (Resolve-Path $path).Path
        }
    }
    
    # Look for fk.py if exe not found
    $pySearchPaths = @(
        ".\fk.py",
        "D:\fk\fk.py",
        "C:\tools\fk\fk.py"
    )
    
    foreach ($path in $pySearchPaths) {
        if (Test-Path $path) {
            Write-ColoredOutput "Found fk.py at: $path" "Info"
            Write-ColoredOutput "Note: You'll need Python installed to use fk.py" "Warning"
            return (Resolve-Path $path).Path
        }
    }
    
    Write-ColoredOutput "FK executable not found automatically." "Warning"
    do {
        $userPath = Read-Host "Please enter the full path to fk.exe or fk.py"
        if (Test-Path $userPath) {
            return (Resolve-Path $userPath).Path
        } else {
            Write-ColoredOutput "File not found: $userPath" "Error"
        }
    } while ($true)
}

function Install-FKFunctions {
    param([string]$ExePath)
    
    # Determine if using Python or executable
    $isPython = $ExePath -match '\.py$'
    
    # Create the FK function code
    $fkFunctions = @"
# FK (Fix Command) Tool - Auto-installed $(Get-Date)
`$Error.Clear()
`$FKExePath = `"$ExePath`"

function fk {
    param(
        [Parameter(Position=0)]
        [string]`$Subcommand,
        [Parameter(Position=1)]
        [string]`$Key,
        [Parameter(Position=2)]
        [string]`$Value,
        [switch]`$y
    )
    
    # Handle config subcommand
    if (`$Subcommand -eq "config") {
        fk-config -Key `$Key -Value `$Value
        return
    }
    
    # Handle main fix command (original behavior)
    `$last = (Get-History -Count 1).CommandLine
    `$err = if (`$Error.Count -gt 0) { `$Error[0] | Out-String } else { "" }

    `$isExternalTool = `$false

    if (`$last -and `$err -eq "") {
        `$isExternalTool = `$true
    }

    if (`$isExternalTool -and `$LASTEXITCODE -ne 0) {
        `$formattedError = nativeOutput -Command `$last
        `$err = `$formattedError
    }

    `$cmdB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(`$last))
    `$errB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(`$err))

$(if ($isPython) {
"    `$json = & python `$FKExePath --shell `"powershell`" --cmd-b64 `$cmdB64 --err-b64 `$errB64"
} else {
"    `$json = & `$FKExePath --shell `"powershell`" --cmd-b64 `$cmdB64 --err-b64 `$errB64"
})

    if (`$LASTEXITCODE -ne 0) { 
        Write-Host `$json -ForegroundColor Red
        return 
    }

    `$obj = `$json | ConvertFrom-Json
    if (-not `$obj -or -not `$obj.command) {
        Write-Host "No fix available" -ForegroundColor Yellow
        return
    }

    Write-Host "→ `$(`$obj.command)" -ForegroundColor Green
    
    # Check if auto_confirm is enabled in config or if -y flag is used
    `$shouldAutoConfirm = `$y -or `$obj.auto_confirm
    
    if (-not `$shouldAutoConfirm) {
        `$ans = Read-Host "Run the command? [y/N]"
        if (`$ans -notin @('y', 'Y')) { return }
    }

    Invoke-Expression `$obj.command

    Clear-Variable -Name last, err -ErrorAction SilentlyContinue
    `$Error.Clear()
}

function fk-config {
    param(
        [string]`$Key,
        [string]`$Value
    )
    
    if (-not `$Key) {
        # Show all configuration
        Write-Host "Current configuration:" -ForegroundColor Cyan
$(if ($isPython) {
"        & python `$FKExePath config"
} else {
"        & `$FKExePath config"
})
        return
    }
    
    if (-not `$Value) {
        # Show specific key
$(if ($isPython) {
"        & `$FKExePath config `$Key"
} else {
"        & `$FKExePath config `$Key"
})
        return
    }
    
    # Set configuration value
$(if ($isPython) {
"    & python `$FKExePath config `$Key `$Value"
} else {
"    & `$FKExePath config `$Key `$Value"
})
}

function nativeOutput {
    param([string]`$Command)
    
    if (-not `$Command -and (Get-History -Count 1)) {
        `$Command = (Get-History -Count 1).CommandLine
    }
    
    if (-not `$Command) {
        return "No command to re-run"
    }
    
    `$commandParts = `$Command -split '\s+', 0, 'RegexMatch'
    `$nativeAppFilePath = `$commandParts[0]
    `$nativeAppParam = `$commandParts[1..(`$commandParts.Length - 1)]
    
    try {
        `$nativeCmdResult = & `$nativeAppFilePath `$nativeAppParam 2>&1
        `$errorMessage = @()
        
        if (`$LASTEXITCODE -ne 0) {
            `$errorMessage += `$nativeCmdResult
        } else {
            `$errorMessage += `$nativeCmdResult
        }
        
        return (`$errorMessage)
    }
    catch {
        return "Failed to re-run command: `$Command``nError: `$(`$_.Exception.Message)"
    }
}

# FK Tool installed and ready to use!
# Use 'fk' after any failed command to get AI-powered fixes
# Use 'fk config' to manage configuration settings
# Examples:
#   fk config                    # Show all config
#   fk config temperature        # Show temperature setting
#   fk config temperature 1.5    # Set temperature to 1.5
"@

    try {
        # Get PowerShell profile path - specifically target Microsoft.PowerShell_profile.ps1
        $profileDir = Split-Path $PROFILE.CurrentUserCurrentHost -Parent
        $profilePath = Join-Path $profileDir "Microsoft.PowerShell_profile.ps1"
        
        # Create profile directory if it doesn't exist
        if (-not (Test-Path $profileDir)) {
            New-Item -Path $profileDir -ItemType Directory -Force | Out-Null
            Write-ColoredOutput "✓ Created PowerShell profile directory: $profileDir" "Success"
        }
        
        # Check if FK functions already exist
        $existingContent = ""
        if (Test-Path $profilePath) {
            $existingContent = Get-Content $profilePath -Raw
        }
        
        if ($existingContent -match "FK \(Fix Command\) Tool" -and -not $Force) {
            Write-ColoredOutput "FK functions already exist in profile." "Info"
            $response = Read-Host "Do you want to update them? [y/N]"
            if ($response -notin @('y', 'Y')) {
                Write-ColoredOutput "Skipping profile update." "Info"
                return $true
            }
        }
        
        # Remove existing FK functions if present
        if ($existingContent -match "FK \(Fix Command\) Tool") {
            $lines = $existingContent -split "`n"
            $newLines = @()
            $skipMode = $false
            
            foreach ($line in $lines) {
                if ($line -match "# FK \(Fix Command\) Tool") {
                    $skipMode = $true
                    continue
                }
                if ($skipMode -and $line -match "^# FK Tool installed and ready") {
                    $skipMode = $false
                    continue
                }
                if (-not $skipMode) {
                    $newLines += $line
                }
            }
            $existingContent = $newLines -join "`n"
        }
        
        # Add FK functions to profile
        $newContent = if ($existingContent.Trim()) { 
            $existingContent.TrimEnd() + "`n`n" + $fkFunctions 
        } else { 
            $fkFunctions 
        }
        
        $newContent | Set-Content -Path $profilePath -Encoding UTF8
        Write-ColoredOutput "✓ FK functions added to PowerShell profile: $profilePath" "Success"
        
        # Return the profile path so it can be used by the calling function
        return @{ Success = $true; ProfilePath = $profilePath }
    }
    catch {
        Write-ColoredOutput "✗ Failed to update PowerShell profile: $($_.Exception.Message)" "Error"
        return @{ Success = $false; ProfilePath = $null }
    }
}

function Test-FKInstallation {
    param([string]$ProfilePath)
    
    try {
        Write-ColoredOutput "`nTesting FK installation..." "Info"
        
        # Source the profile to test
        if (Test-Path $ProfilePath) {
            . $ProfilePath
        }
        
        # Test if fk command exists
        $fkCommand = Get-Command fk -ErrorAction SilentlyContinue
        if ($fkCommand) {
            Write-ColoredOutput "✓ FK command is available" "Success"
            return $true
        } else {
            Write-ColoredOutput "✗ FK command not found" "Error"
            return $false
        }
    }
    catch {
        Write-ColoredOutput "✗ Error testing installation: $($_.Exception.Message)" "Error"
        return $false
    }
}

# Main installation process
function Start-Installation {
    Write-ColoredOutput "=== FK (Fix Command) Tool Installer ===" "Info"
    Write-ColoredOutput "This will install the AI-powered command fixer to your PowerShell profile.`n" "Info"
    
    # Step 1: Get and set Gemini API key
    Write-ColoredOutput "Step 1: Setting up Gemini API key..." "Info"
    $apiKey = Get-GeminiApiKey
    if (-not (Set-EnvironmentVariable -ApiKey $apiKey)) {
        Write-ColoredOutput "Failed to set API key. Installation aborted." "Error"
        exit 1
    }
    
    # Step 2: Find FK executable
    Write-ColoredOutput "`nStep 2: Locating FK executable..." "Info"
    $exePath = Get-ExecutablePath
    Write-ColoredOutput "✓ Using FK executable: $exePath" "Success"
    
    # Step 3: Install FK functions
    Write-ColoredOutput "`nStep 3: Installing FK functions to PowerShell profile..." "Info"
    $installResult = Install-FKFunctions -ExePath $exePath
    if (-not $installResult.Success) {
        Write-ColoredOutput "Failed to install FK functions. Installation aborted." "Error"
        exit 1
    }
    $profilePath = $installResult.ProfilePath
    
    # Step 4: Test installation
    Write-ColoredOutput "`nStep 4: Testing installation..." "Info"
    Test-FKInstallation -ProfilePath $profilePath | Out-Null
    
    # Installation complete
    Write-ColoredOutput "`n=== Installation Complete! ===" "Success"
    Write-ColoredOutput "FK (Fix Command) tool has been successfully installed!" "Success"
    Write-ColoredOutput "`nUsage:" "Info"
    Write-ColoredOutput "  1. Run any command that fails" "Info"
    Write-ColoredOutput "  2. Type 'fk' to get an AI-powered fix suggestion" "Info" 
    Write-ColoredOutput "  3. Press 'y' to accept the fix, or 'N' to cancel" "Info"
    Write-ColoredOutput "  4. Use 'fk -y' to auto-accept fixes without prompting" "Info"
    Write-ColoredOutput "`nConfiguration Management:" "Info"
    Write-ColoredOutput "  fk config                    # Show all configuration" "Info"
    Write-ColoredOutput "  fk config temperature        # Show specific setting" "Info"
    Write-ColoredOutput "  fk config auto_confirm true  # Enable auto-confirm" "Info"
    Write-ColoredOutput "  fk config model gemini-2.5-flash  # Change AI model" "Info"
    Write-ColoredOutput "`nRestart PowerShell or run '. `$PROFILE' to use FK immediately!" "Warning"
    Write-ColoredOutput "Profile location: $profilePath" "Info"
}

# Run installation
try {
    Start-Installation
}
catch {
    Write-ColoredOutput "Installation failed with error: $($_.Exception.Message)" "Error"
    exit 1
}