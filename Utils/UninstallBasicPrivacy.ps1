# Undoes Install.ps1 -Level BasicPrivacy for the current user, assuming no other level has been installed.
# Removes ALL local group policy, then reverts the settings that outlive it.

$IsAdmin = [bool](([System.Security.Principal.WindowsIdentity]::GetCurrent()).groups -match "S-1-5-32-544")
if (-not $IsAdmin){
    throw "Script is not running with administrative privileges"
}

# Only run this script interactively. In a non-interactive session (e.g. -NonInteractive, scheduled
# task, remoting), PromptForChoice throws, and the script continues without confirmation
$Msg = "This removes ALL local group policy, including any settings not made by BasicPrivacy.`r`n`r`n" `
+ "These settings are reset to Windows defaults for the current user, even if you set them differently:`r`n" `
+ " - Privacy & security > General > Let Windows improve Start and search results by tracking app launches (on)`r`n" `
+ " - Privacy & security > General > Let websites show me locally relevant content by accessing my language list (on)`r`n" `
+ " - Privacy & security > Inking & typing personalization > Custom inking and typing dictionary (on)`r`n" `
+ " - Windows Security > App & browser control > Reputation-based protection > SmartScreen for Microsoft Store apps (on)`r`n" `
+ "Note any custom values first, and set them again afterwards.`r`n`r`n" `
+ "Do you want to continue?"
if ($Host.UI.PromptForChoice("Warning",$Msg,@("&Yes","&No"),1) -eq 1){
    exit
}

$Failed = $false

# Group policy settings
Write-Host "Removing local group policy" -ForegroundColor Cyan
try {
    Remove-Item -Path "$env:WinDir\System32\GroupPolicyUsers\*" -Recurse -Force -ErrorAction Stop
    Remove-Item -Path "$env:WinDir\System32\GroupPolicy\*" -Recurse -Force -ErrorAction Stop
} catch {
    throw "Failed to remove local group policy: $_. Nothing else was changed. Fix the error and run the script again"
}
gpupdate /force
if ($LASTEXITCODE -ne 0){
    Write-Warning "gpupdate failed with exit code $LASTEXITCODE"
    $Failed = $true
}

# Earlier versions of BasicPrivacy disabled the License Manager service with a security template
# ("LicenseManager",4), which breaks the Windows Security app. LGPO applied it once, directly to the
# service, so wiping group policy does not undo it. Windows default is Manual
Write-Host "Resetting License Manager service" -ForegroundColor Cyan
try {
    Set-Service -Name LicenseManager -StartupType Manual -ErrorAction Stop
} catch {
    Write-Warning "Failed to set License Manager service to Manual: $_"
    $Failed = $true
}

# Registry values written outside the policy keys, which group policy does not clean up
Write-Host "Reverting computer registry values" -ForegroundColor Cyan
Remove-ItemProperty -Path "HKLM:\Software\Microsoft\OneDrive" -Name PreventNetworkTrafficPreUserSignIn -ErrorAction SilentlyContinue
# W32Time\Parameters\Type=NTP is the Windows default on non-domain computers, so it is left as is

# User values are only reverted for the current user. If the script is elevated with a different
# admin account, this is that account's registry, not the logged-in user's
Write-Host "Reverting user registry values" -ForegroundColor Cyan
Remove-ItemProperty -Path "HKCU:\Control Panel\International\User Profile" -Name HttpAcceptLanguageOptOut -ErrorAction SilentlyContinue
Remove-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Messaging" -Name CloudServiceSyncEnabled -ErrorAction SilentlyContinue
Remove-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppHost" -Name EnableWebContentEvaluation -ErrorAction SilentlyContinue
Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name Start_TrackProgs -Value 1 -Type DWord
if (Test-Path "HKCU:\SOFTWARE\Microsoft\InputPersonalization"){
    Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\InputPersonalization" -Name RestrictImplicitInkCollection -Value 0 -Type DWord
    Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\InputPersonalization" -Name RestrictImplicitTextCollection -Value 0 -Type DWord
}

Write-Host "Preinstalled apps removed by BasicPrivacy (Bing News/Weather/Finance/Sports, Twitter, Xbox, " `
    "Sway, OneNote, Office Hub, Skype, Sticky Notes) are not restored. Reinstall them from the Microsoft Store if needed." `
    -ForegroundColor Yellow
if ($Failed){
    Write-Warning "Done, with errors. See the warnings above. Please reboot your device to apply all settings"
} else {
    Write-Host "Done. Please reboot your device to apply all settings"
}
