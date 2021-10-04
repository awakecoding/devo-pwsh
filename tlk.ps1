#!/usr/bin/env pwsh

$PSSourceRoot = Join-Path $PSScriptRoot "PowerShell"
Import-Module "$PSSourceRoot/build.psm1" -Force

if (-Not (Test-Path 'variable:global:IsWindows')) {
    $global:IsWindows = $true; # Windows PowerShell 5.1 or earlier
}

if ($IsWindows) {
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12;
}

function Get-TlkPlatform {
    param(
        [Parameter(Position=0)]
        [string] $Platform
    )

    if (-Not $Platform) {
        $Platform = if ($IsWindows) {
            'windows'
        } elseif ($IsMacOS) {
            'macos'
        } elseif ($IsLinux) {
            'linux'
        }
    }

    $Platform
}

function Invoke-TlkBootstrap {
    param(
    )

    Start-PSBootstrap
}

function Invoke-TlkBuild {
    param(
        [ValidateSet('windows','macos','linux')]
        [string] $Platform,
        [ValidateSet('x86','x64','arm','arm64')]
        [string] $Architecture,
        [ValidateSet('debian','ubuntu','alpine')]
        [string] $Distribution,
        [ValidateSet('Debug','Release')]
        [string] $Configuration,
        [string] $OutputPath,
        [switch] $ArchiveFile
    )

    $HostPlatform = Get-TlkPlatform
    
    if (-Not $Platform) {
        $Platform = $HostPlatform
    }

    if (-Not $Architecture) {
        $Architecture = "x64"
    }

    if (-Not $OutputPath) {
        $OutputPath = Join-Path $PWD "PowerShell-$Platform-$Architecture"
    }

    $CrossCompiling = ($Platform -ne $HostPlatform)

    if (-Not $Configuration) {
        $Configuration = "Release"
    }

    $RuntimeArch = $Architecture

    $Runtime = switch ($Platform) {
        "windows" {
            if ($RuntimeArch -Like 'arm*') {
                "win-$RuntimeArch"
            } else {
                "win7-$RuntimeArch"
            }
        }
        "macos" { "osx-$RuntimeArch" }
        "linux" { "linux-$RuntimeArch" }
    }

    if ($Distribution -eq 'alpine') {
        $Runtime = "alpine-$RuntimeArch"
    } elseif ($Distribution -eq 'ubuntu') {
        $Runtime = "ubuntu.18.04-$RuntimeArch"
    }

    $ForMinimalSize = $false

    if ($CrossCompiling) {
        # https://docs.microsoft.com/en-us/dotnet/core/deploying/ready-to-run#cross-platformarchitecture-restrictions
        Write-Warning "Disabling ReadyToRun while cross-compiling (smaller output size, but no AOT compilation)"
        $ForMinimalSize = $true
    }

    $PSBuildParams = @{
        Configuration = $Configuration;
        Runtime = $Runtime;
        Output = $OutputPath;
        ForMinimalSize = $ForMinimalSize;
        Detailed = $true;
        Clean = $true;
    }

    Start-PSBuild @PSBuildParams

    if ($ArchiveFile) {
        Remove-Item $ArchiveFile -ErrorAction SilentlyContinue | Out-Null
        & 'tar' '-czf' "$ArchiveFile" -C "$OutputPath" "."
    }
}

$CmdVerbs = @('bootstrap','build')

if ($args.Count -lt 1) {
    throw "not enough arguments!"
}

$CmdVerb = $args[0]
$CmdArgs = $args[1..$args.Count]

if ($CmdVerbs -NotContains $CmdVerb) {
    throw "invalid verb $CmdVerb, use one of: [$($CmdVerbs -Join ',')]"
}

switch ($CmdVerb) {
    "bootstrap" { Invoke-TlkBootstrap @CmdArgs }
    "build" { Invoke-TlkBuild @CmdArgs }
}
