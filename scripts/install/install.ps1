#!/usr/bin/env pwsh

$ErrorActionPreference = 'Stop'

if ($env:OS -ne "Windows_NT") {
  Write-Error "This script is only for Windows"
  Exit 1
}

if ($null -ne $env:RUSH_HOME) {
  $RushHome = $env:RUSH_HOME
}
else {
  if (Get-Command "rush.exe" -ErrorAction SilentlyContinue) {
    $RushHome = (Get-Item (Get-Command "rush.exe").Path).Directory.Parent.FullName
  }
  else {
    $RushHome = "$Home\.rush"
  }
}
New-Item $RushHome -ItemType Directory -Force | Out-Null

$BinDir = "$RushHome\bin"
$ZipUrl = "https://github.com/shreyashsaitwal/rush-cli/releases/latest/download/rush-x86_64-windows.zip"
$ZipLocation = "$RushHome\rush-x86_64-windows.zip"

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

Invoke-WebRequest -OutFile $ZipLocation $ZipUrl -UseBasicParsing

if (Get-Command Expand-Archive -ErrorAction SilentlyContinue) {
  Expand-Archive $ZipLocation -DestinationPath "$RushHome" -Force
}
else {
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  [IO.Compression.ZipFile]::ExtractToDirectory($ZipLocation, $RushHome)
}
Remove-Item $ZipLocation

Write-Output "Successfully downloaded the Rush CLI binary at $RushHome\bin\rush.exe"

$Yes = New-Object System.Management.Automation.Host.ChoiceDescription "&Yes"
$No = New-Object System.Management.Automation.Host.ChoiceDescription "&No"
$Options = [System.Management.Automation.Host.ChoiceDescription[]]($Yes, $No)

$Title = "Rush now needs the App Inventor runtime and build tools (about 140 MB)."
$Message = "Download them now?"
$Result = $host.ui.PromptForChoice($Title, $Message, $Options, 0)
if ($Result -eq 0) {
  Start-Process -NoNewWindow -FilePath "$BinDir\rush.exe" -ArgumentList "deps", "sync", "--dev-deps" -Wait
}

$User = [EnvironmentVariableTarget]::User
$Path = [Environment]::GetEnvironmentVariable('Path', $User)
if (!(";$Path;".ToLower() -like "*;$BinDir;*".ToLower())) {
  [Environment]::SetEnvironmentVariable('Path', "$Path;$BinDir", $User)
  $Env:Path += ";$BinDir"
}

if ($Result -eq 0) {
  Write-Output "`nSuccess! Installed Rush at $BinDir\rush.exe!"
  Write-Output "Run ``rush --help`` to get started."
}
else {
  Write-Output "`nRush has been partially installed at $BinDir\rush.exe!"
  Write-Output "Please run ``rush deps sync --dev-deps`` to download necessary Java libraries."
}
