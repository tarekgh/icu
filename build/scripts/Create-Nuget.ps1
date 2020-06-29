<#
.SYNOPSIS
    This script sets up the folder structure for the Nuget package,copies/prepares the contents, and finally
    invokes the Nuget pack operation to create the package.

.PARAMETER sourceRoot
    The path to the root/top-level source code folder. Must already exist.

.PARAMETER icuBinaries
    The path to the location of the signed ICU binaries. Must already exist.
    Under this path there should be one folder per-arch: x64, x86, ARM, or ARM64.

.PARAMETER icuHeaders
    The path to the location of the public ICU headers. Must already exist.

.PARAMETER output
    The path to the output location. This script will create a subfolder named "nuget" for the Nuget package(s).

.PARAMETER codeSigned
    If TRUE use the codesigned binaries (under the bin\signed folder).
    If FALSE use the binaries from the bin folder.
#>
param(
    [Parameter(Mandatory=$true)]
    [ValidateScript({Test-Path $_ -PathType 'Container'})]
    [string]$sourceRoot,

    [Parameter(Mandatory=$true)]
    [ValidateScript({Test-Path $_ -PathType 'Container'})]
    [string]$icuBinaries,

    [Parameter(Mandatory=$true)]
    [ValidateScript({Test-Path $_ -PathType 'Container'})]
    [string]$icuHeaders,

    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string]$output,

    [Parameter(Mandatory=$true)]
    [bool]$codeSigned
)

# We should already have the nugetPackageVersion set as an environment variable in Set-ICUVersion.ps1.
if (!(Test-Path 'env:nugetPackageVersion')) {
    throw "Error: The nugetPackageVersion environment variable is not set."
}

$icuSource = Resolve-Path "$sourceRoot\icu\icu4c"

# Create the output folder.
$outputNugetLocation = "$output\nuget"
if (Test-Path $outputNugetLocation -PathType Container) {
    throw "Error: The output path $outputNugetLocation path already exists! I don't want to over-write any existing files."
}
# Note: We store the return value from New-Item in order to suppress the Cmdlet output to stdout.
Write-Host "Creating folder for the Nuget package..."
$ret = New-Item -Path $outputNugetLocation -ItemType "Directory"

# Read in the various arch from the names of the folders (x64, x86, ARM, or ARM64).
$architectures = Get-ChildItem -Path $icuBinaries | Where-Object {$_.PSIsContainer} | ForEach-Object {$_.Name}

# Create the folder structure for the Nuget
Write-Host "Creating folders"
$ret = New-Item -Path "$outputNugetLocation\build" -ItemType "Directory"
$ret = New-Item -Path "$outputNugetLocation\build\native" -ItemType "Directory"
$ret = New-Item -Path "$outputNugetLocation\build\native\include" -ItemType "Directory"
$ret = New-Item -Path "$outputNugetLocation\build\native\lib" -ItemType "Directory"
$ret = New-Item -Path "$outputNugetLocation\runtimes" -ItemType "Directory"

foreach ($arch in $architectures)
{
    $ret = New-Item -Path "$outputNugetLocation\runtimes\$arch" -ItemType "Directory"
    $ret = New-Item -Path "$outputNugetLocation\runtimes\$arch\native" -ItemType "Directory"
    $ret = New-Item -Path "$outputNugetLocation\build\native\lib\$arch" -ItemType "Directory"
    $ret = New-Item -Path "$outputNugetLocation\build\native\lib\$arch\Release" -ItemType "Directory"
    
    # Import Libs and PDBs
    $libInput = "$icuBinaries\$arch\lib"
    $libOuput = "$outputNugetLocation\build\native\lib\$arch\Release"
    Copy-Item "$libInput\*.lib" -Destination $libOuput -Recurse
    Copy-Item "$libInput\*.pdb" -Destination $libOuput -Recurse
    
    # Compiled DLLs and EXEs
    $dllInput = "$icuBinaries\$arch\bin\signed"
    if ($codeSigned) {
        $dllInput = "$icuBinaries\$arch\bin\signed"
    }
    $dllOuput = "$outputNugetLocation\runtimes\$arch\native"
    Copy-Item "$dllInput\*.dll" -Destination $dllOuput -Recurse
    Copy-Item "$dllInput\*.exe" -Destination $dllOuput -Recurse
}

# Copy the headers
Copy-Item $icuHeaders -Destination "$outputNugetLocation\build\native\include" -Recurse

# Add the License file
Write-Host "Copying the License file into the Nuget location."
$licenseFile = Resolve-Path "$icuSource\LICENSE"
Copy-Item $licenseFile -Destination "$outputNugetLocation\LICENSE"

# Copy the Nuget "targets" files.
Copy-Item "$sourceRoot\build\nuget\*.targets" -Destination "$outputNugetLocation\build\native"

# Update the placeholders in the template nuspec file.
$nuspecFileContent = (Get-Content "$sourceRoot\build\nuget\Template-Microsoft.icu4c.nuspec")
$nuspecFileContent = $nuspecFileContent.replace('$id$', 'Microsoft.icu4c.win')
$nuspecFileContent = $nuspecFileContent.replace('$version$', $env:nugetPackageVersion)
$nuspecFileContent | Set-Content "$outputNugetLocation\Microsoft.icu4c.nuspec"

# Actually do the "nuget pack" operation
$nugetCmd = ("nuget pack $outputNugetLocation\Microsoft.icu4c.nuspec -BasePath $outputNugetLocation -OutputDirectory $output")
Write-Host "Executing: $nugetCmd"
&cmd /c $nugetCmd