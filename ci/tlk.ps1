
# global initialization

$RootPath = $($PSScriptRoot | Get-Item).Parent.FullName
$PSSourceRoot = Join-Path $RootPath "PowerShell"
Import-Module "$PSSourceRoot\build.psm1" -Force

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
        $Platform = if ($global:IsWindows) {
            'windows'
        } elseif ($global:IsMacOS) {
            'macos'
        } elseif ($global:IsLinux) {
            'linux'
        }
    }

    $Platform
}

function Get-TlkArchitecture {
    param(
        [Parameter(Position=0)]
        [string] $Architecture
    )

    if (-Not $Architecture) {
        $Architecture = 'x86_64'
    }

    $Architecture
}

class TlkTarget
{
    [string] $Platform
    [string] $Architecture
    [string] $Distribution

    [string] $ExecutableExtension

    TlkTarget() {
        $this.Init()
    }

    [void] Init() {
        $this.Platform = Get-TlkPlatform
        $this.Architecture = Get-TlkArchitecture

        if ($this.IsWindows()) {
            $this.ExecutableExtension = 'exe'
        } else {
            $this.ExecutableExtension = ''
        }
    }

    [bool] IsWindows() {
        return $this.Platform -eq 'Windows'
    }

    [bool] IsMacOS() {
        return $this.Platform -eq 'macOS'
    }

    [bool] IsLinux() {
        return $this.Platform -eq 'Linux'
    }

    [string] LlvmArchitecture() {
        $Arch = switch ($this.Architecture) {
            "x86" { "i386" }
            "x64" { "x86_64" }
            "arm64" { "aarch64" }
        }
        return $Arch
    }

    [string] DebianArchitecture() {
        # https://wiki.debian.org/Multiarch/Tuples
        $Arch = switch ($this.Architecture) {
            "x86" { "i386" }
            "x64" { "amd64" }
            "arm64" { "arm64" }
        }
        return $Arch
    }
}

class TlkRecipe
{
    [string] $PackageName
    [string] $Version
    [string] $SourcePath
    [string] $HostPlatform
    [bool] $Verbose

    [TlkTarget] $Target

    TlkRecipe() {
        $this.Init()
    }

    [void] Init() {
        $this.SourcePath = $($PSScriptRoot | Get-Item).Parent.FullName
        $this.PackageName = "PowerShell"
        $this.Version = $(Get-PSVersion -OmitCommitId)
        $this.Verbose = $true

        $this.Target = [TlkTarget]::new()
        $this.HostPlatform = $this.DetectHostPlatform()
    }

    [string] DetectHostPlatform() {
        $Platform = if ($global:IsWindows) {
            'windows'
        } elseif ($global:IsMacOS) {
            'macos'
        } elseif ($global:IsLinux) {
            'linux'
        }
        return $Platform;
    }

    [void] Build() {
        $OutputPath = Join-Path $this.SourcePath "output"

        $CrossCompiling = ($this.Target.Platform -ne $this.HostPlatform)

        $Configuration = "Release"
        $PSVersion = $this.Version
        $Platform = $this.Target.Platform.ToLower()

        $RuntimeArch = $this.Target.Architecture

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

        if ($this.Target.Distribution -eq 'alpine') {
            $Runtime = "alpine-$RuntimeArch"
            $Platform = "linux-alpine"
        } elseif ($this.Target.Distribution -eq 'ubuntu') {
            $Runtime = "ubuntu.18.04-$RuntimeArch"
            $Platform = "ubuntu-18.04"
        }

        $PSBuildPath = Join-Path $OutputPath "PowerShell-${PSVersion}-${Platform}-${RuntimeArch}"

        $ForMinimalSize = $false

        if ($CrossCompiling) {
            # https://docs.microsoft.com/en-us/dotnet/core/deploying/ready-to-run#cross-platformarchitecture-restrictions
            Write-Warning "Disabling ReadyToRun while cross-compiling (smaller output size, but no AOT compilation)"
            $ForMinimalSize = $true
        }

        $PSBuildParams = @{
            Configuration = $Configuration;
            Runtime = $Runtime;
            Output = $PSBuildPath;
            ForMinimalSize = $ForMinimalSize;
            Detailed = $true;
            Clean = $true;
        }

        Start-PSBuild @PSBuildParams

        $TarArchivePath = "$PSBuildPath.tar.gz"
        Remove-Item $TarArchivePath -ErrorAction SilentlyContinue | Out-Null
        & 'tar' '-czf' "$TarArchivePath" -C "$PSBuildPath" "."
    }

    [void] Package_Windows() {

    }

    [void] Package_MacOS() {

    }

    [void] Package_Linux() {

    }

    [void] Package() {
        if ($this.Target.IsWindows()) {
            $this.Package_Windows()
        } elseif ($this.Target.IsMacOS()) {
            $this.Package_MacOS()
        } elseif ($this.Target.IsLinux()) {
            $this.Package_Linux()
        }
    }
}

function Invoke-TlkStep {
	param(
        [Parameter(Position=0,Mandatory=$true)]
		[ValidateSet('build','package')]
		[string] $TlkVerb,
		[ValidateSet('windows','macos','linux')]
		[string] $Platform,
		[ValidateSet('x86','x64','arm','arm64')]
		[string] $Architecture,
        [ValidateSet('debian','ubuntu','alpine')]
        [string] $Distribution
	)

    if (-Not $Platform) {
        $Platform = Get-TlkPlatform
    }

    if (-Not $Architecture) {
        $Architecture = Get-TlkArchitecture
    }

    $RootPath = Split-Path -Parent $PSScriptRoot

    $tlk = [TlkRecipe]::new()
    $tlk.SourcePath = $RootPath
    $tlk.Target.Platform = $Platform
    $tlk.Target.Architecture = $Architecture
    $tlk.Target.Distribution = $Distribution

    switch ($TlkVerb) {
        "build" { $tlk.Build() }
        "package" {$tlk.Package() }
    }
}

Invoke-TlkStep @args
