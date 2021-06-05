#!/usr/bin/env pwsh

$ErrorActionPreference = 'Stop'

# Check if Rush is already installed; if it is, use the old
# path for storing rush.exe
if (Get-Command "rush.exe" -ErrorAction SilentlyContinue) {
  $BinDir = (Get-Item (Get-Command "rush.exe").Path).DirectoryName
}
else {
  $BinDir = "$Home/.rush/bin"
  if (!(Test-Path $BinDir)) {
    New-Item $BinDir -ItemType Directory | Out-Null
  }
}

$ZipUrl = "https://github.com/shreyashsaitwal/rush-pack/releases/latest/download/rush-win64.zip"

# GitHub requires TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Download rush-win.zip
Invoke-WebRequest -OutFile "$BinDir/rush-win.zip" $ZipUrl -UseBasicParsing

# Extract it
if (Get-Command Expand-Archive -ErrorAction SilentlyContinue) {
  Expand-Archive "$BinDir/rush-win.zip" -DestinationPath "$BinDir" -Force
}
else {
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  [IO.Compression.ZipFile]::ExtractToDirectory("$BinDir/rush-win.zip", $BinDir)
}
Remove-Item "$BinDir/rush-win.zip"

$AppDataDir = "$env:APPDATA/rush"

# Delete the AppDataDir if it already exists
if (Test-Path $AppDataDir) {
  Remove-Item -Recurse $AppDataDir
}

# Then (re-)create it
New-Item -ItemType Directory $AppDataDir | Out-Null

# Delete old exes
Remove-Item "$BinDir/rush.exe" -ErrorAction SilentlyContinue
Remove-Item "$BinDir/swap.exe" -ErrorAction SilentlyContinue

# Move files
Move-Item "$BinDir/exe/win/*.exe" -Destination "$BinDir" -Force
Remove-Item -Recurse "$BinDir/exe"

# Pipe the output of [Get-ChildItem] to [Move-Item]
Get-ChildItem "$BinDir" -Directory | Move-Item -Destination "$AppDataDir" -Force

# Update PATH
$User = [EnvironmentVariableTarget]::User
$Path = [Environment]::GetEnvironmentVariable('Path', $User)
if (!(";$Path;".ToLower() -like "*;$BinDir;*".ToLower())) {
  [Environment]::SetEnvironmentVariable('Path', "$Path;$BinDir", $User)
  $Env:Path += ";$BinDir"
}

Write-Output "Success! Installed Rush at $BinDir\rush.exe!"
Write-Output "Run 'rush --help' to get started.`n"
