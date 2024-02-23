
if (-Not [string]::IsNullOrWhiteSpace($PSScriptRoot)) {
    $PSSourceRoot = Join-Path ($PSScriptRoot.Parent) "PowerShell"
} else {
    $PSSourceRoot = Join-Path (Get-item .).Parent "PowerShell"
}

$nugetConfigPath = "$PSSourceRoot/nuget.config"
[xml]$nugetConfig = Get-Content $nugetConfigPath

$nugetLocalSource = $nugetConfig.configuration.packageSources.add | Where-Object { $_.key -eq 'nuget-local' }

if ($null -eq $nugetLocalSource) {
    $nugetLocalSource = $nugetConfig.CreateElement("add")
    $nugetLocalSource.SetAttribute("key", "nuget-local")
    $nugetLocalSource.SetAttribute("value", "nuget-local")

    $packageSources = $nugetConfig.configuration.packageSources
    $firstAddElement = $packageSources.ChildNodes | Where-Object { $_.Name -eq 'add' } | Select-Object -First 1

    if ($firstAddElement -ne $null) {
        $packageSources.InsertBefore($nugetLocalSource, $firstAddElement)
    } else {
        $packageSources.AppendChild($nugetLocalSource)
    }

    $nugetConfig.Save($nugetConfigPath)
}

$NugetCachePath = Join-Path $HOME ".nuget/packages"
$NugetLocalPath = Join-Path $PSSourceRoot "nuget-local"
New-Item $NugetLocalPath -ItemType Directory -ErrorAction SilentlyContinue

Import-Module "$PSSourceRoot/build.psm1" -Force
Start-PSBootstrap
Find-Dotnet
Start-PSBuild -Clean -PSModuleRestore -Configuration Release

$PSVersion = Get-PSVersion -OmitCommitId

$PowerShellSdkProjects = @(
  'System.Management.Automation',
  'Microsoft.PowerShell.Security',
  'Microsoft.PowerShell.ConsoleHost',
  'Microsoft.PowerShell.Commands.Utility',
  'Microsoft.PowerShell.Commands.Management',
  'Microsoft.PowerShell.SDK'
)

foreach ($ProjectName in $PowerShellSdkProjects) {
    $ProjectFilePath = "$PSSourceRoot/src/$ProjectName/${ProjectName}.csproj"
    [xml]$csproj = Get-Content -Path $ProjectFilePath
    $projectReferences = $csproj.Project.ItemGroup | Where-Object { $_.ProjectReference -ne $null }

    if ($projectReferences -ne $null) {
        $packageReferencesItemGroup = $csproj.CreateElement("ItemGroup", $csproj.Project.NamespaceURI)
        
        foreach ($projectReference in $projectReferences.ProjectReference) {
            $projectName = if ($projectReference.Include -match '\\([^\\]+)\.csproj$') { $matches[1] }

            if ($PowerShellSdkProjects -contains $projectName) {
                $packageReference = $csproj.CreateElement("PackageReference", $csproj.Project.NamespaceURI)
                $packageReference.SetAttribute("Include", $projectName)
                $packageReference.SetAttribute("Version", $PSVersion)
                $packageReferencesItemGroup.AppendChild($packageReference) | Out-Null
                $projectReferences.RemoveChild($projectReference) | Out-Null
            }
        }

        $csproj.Project.AppendChild($packageReferencesItemGroup) | Out-Null
        $csproj.Save($ProjectFilePath)
    }
}

Get-Item "$NugetOutputPath/*.nupkg" | Remove-Item
foreach ($ProjectName in $PowerShellSdkProjects) {
  $ProjectFilePath = "$PSSourceRoot/src/$ProjectName/${ProjectName}.csproj"
  $NugetPackageCachePath = "$NugetCachePath/$($ProjectName.ToLower())/$PSVersion"
  Remove-Item $NugetPackageCachePath -Recurse -Force -ErrorAction SilentlyContinue
  dotnet restore $ProjectFilePath
  dotnet clean $ProjectFilePath
  dotnet pack $ProjectFilePath -c Release -o $NugetLocalPath
}
