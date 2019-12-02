Param (
    [switch]$Batch
)

if ($PSScriptRoot) { $commandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", ""); $here = $PSScriptRoot }
else { $commandName = "_ManualExecution"; $here = (Get-Item . ).FullName }

if (!$Batch) {
    # Is not a part of the global batch => import module
    #Explicitly import the module for testing
    Import-Module "$here\..\dbops.psd1" -Force; Get-DBOModuleFileList -Type internal | ForEach-Object { . $_.FullName }
}
else {
    # Is a part of a batch, output some eye-catching happiness
    Write-Host "Running $commandName tests" -ForegroundColor Cyan
}

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
. "$here\..\internal\classes\DBOpsHelper.class.ps1"
. "$here\..\internal\classes\DBOps.class.ps1"

$slash = [IO.Path]::DirectorySeparatorChar
$packageName = Join-PSFPath -Normalize "$here\etc\$commandName.zip"
$script1 = Join-PSFPath -Normalize "$here\etc\sqlserver-tests\success\1.sql"
$script2 = Join-PSFPath -Normalize "$here\etc\sqlserver-tests\success\2.sql"
$script3 = Join-PSFPath -Normalize "$here\etc\sqlserver-tests\success\3.sql"
$fileObject1 = Get-Item $script1
$fileObject2 = Get-Item $script2
$fileObject3 = Get-Item $script3

Describe "DBOpsPackage class tests" -Tag $commandName, UnitTests, DBOpsPackage {
    AfterAll {
        if (Test-Path $packageName) { Remove-Item $packageName }
    }
    Context "validating DBOpsPackage creation" {
        AfterAll {
            if (Test-Path $packageName) { Remove-Item $packageName }
        }
        It "Should create new DBOpsPackage object" {
            $pkg = [DBOpsPackage]::new()
            $pkg.ScriptDirectory | Should Be 'content'
            $pkg.DeployFile.ToString() | Should Be 'Deploy.ps1'
            $pkg.DeployFile.GetContent() | Should BeLike '*Invoke-DBODeployment @params*'
            $pkg.Configuration.SchemaVersionTable | Should Be 'SchemaVersions'
            $pkg.FileName | Should BeNullOrEmpty
            $pkg.Version | Should BeNullOrEmpty
            { $pkg.SaveToFile($packageName, $true) } | Should Not Throw
        }
        $testResults = Get-ArchiveItem $packageName
        It "should contain module files" {
            foreach ($file in (Get-DBOModuleFileList)) {
                Join-PSFPath -Normalize 'Modules\dbops' $file.Path | Should BeIn $testResults.Path
            }
        }
        It "should contain config files" {
            'dbops.config.json' | Should BeIn $testResults.Path
            'dbops.package.json' | Should BeIn $testResults.Path
        }
        It "should contain deploy file" {
            'Deploy.ps1' | Should BeIn $testResults.Path
        }
    }
    Context "validate DBOpsPackage being loaded from file" {
        AfterAll {
            if (Test-Path $packageName) { Remove-Item $packageName }
        }
        BeforeAll {
            $pkg = [DBOpsPackage]::new()
            $pkg.SaveToFile($packageName, $force)
        }
        It "should load package from file" {
            $pkg = [DBOpsPackage]::new($packageName)
            $pkg.ScriptDirectory | Should Be 'content'
            $pkg.DeployFile.ToString() | Should Be 'Deploy.ps1'
            $pkg.DeployFile.GetContent() | Should BeLike '*Invoke-DBODeployment @params*'
            $pkg.ConfigurationFile.ToString() | Should Be 'dbops.config.json'
            ($pkg.ConfigurationFile.GetContent() | ConvertFrom-Json).SchemaVersionTable | Should Be 'SchemaVersions'
            $pkg.Configuration.SchemaVersionTable | Should Be 'SchemaVersions'
            $pkg.FileName | Should Be $packageName
            $pkg.Version | Should BeNullOrEmpty
            $pkg.PackagePath | Should BeNullOrEmpty
        }
    }
    Context "should validate DBOpsPackage methods" {
        AfterAll {
            if (Test-Path $packageName) { Remove-Item $packageName }
        }
        BeforeEach {
            $pkg = [DBOpsPackage]::new()
            $pkg.Slim = $true
            $pkg.SaveToFile($packageName, $true)
        }
        It "Should test GetBuilds method" {
            $pkg.GetBuilds() | Should Be $null
            $pkg.Builds.Add([DBOpsBuild]::new('1.0'))
            $pkg.GetBuilds().Build | Should Be '1.0'
            $pkg.Builds.Add([DBOpsBuild]::new('2.0'))
            $pkg.GetBuilds().Build | Should Be @('1.0', '2.0')
        }
        It "Should test NewBuild method" {
            $b = $pkg.NewBuild('1.0')
            $b.Build | Should Be '1.0'
            $b.PackagePath | Should Be '1.0'
            $b.Parent.GetType().Name | Should Be 'DBOpsPackage'
            $b.Scripts | Should BeNullOrEmpty
            ([datetime]$b.CreatedDate).Date | Should Be ([datetime]::Now).Date
            $pkg.Version | Should Be '1.0'
        }
        It "Should test GetBuild method" {
            $null = $pkg.NewBuild('1.0')
            $null = $pkg.NewBuild('2.0')
            $b = $pkg.GetBuild('1.0')
            $b.Build | Should Be '1.0'
            $b.PackagePath | Should Be '1.0'
            $b.Parent.GetType().Name | Should Be 'DBOpsPackage'
            $b.Scripts | Should BeNullOrEmpty
            ([datetime]$b.CreatedDate).Date | Should Be ([datetime]::Now).Date
            $b2 = $pkg.GetBuild(@('1.0', '2.0'))
            $b2.Build | Should Be @('1.0', '2.0')
        }
        It "Should test AddBuild method" {
            $pkg.AddBuild('2.0')
            $b = $pkg.GetBuild('2.0')
            $b.Build | Should Be '2.0'
            $b.PackagePath | Should Be '2.0'
            $b.Parent.GetType().Name | Should Be 'DBOpsPackage'
            $b.Scripts | Should BeNullOrEmpty
            ([datetime]$b.CreatedDate).Date | Should Be ([datetime]::Now).Date
            $pkg.Version | Should Be '2.0'
        }
        It "Should test EnumBuilds method" {
            $pkg.Builds.Add([DBOpsBuild]::new('1.0'))
            $pkg.Builds.Add([DBOpsBuild]::new('2.0'))
            $pkg.EnumBuilds() | Should Be @('1.0', '2.0')
        }
        It "Should test GetVersion method" {
            $pkg.AddBuild('2.0')
            $pkg.GetVersion() | Should Be '2.0'
        }
        It "Should test RemoveBuild method" {
            $pkg.AddBuild('1.0')
            $pkg.AddBuild('2.0')
            $pkg.RemoveBuild('2.0')
            '2.0' | Should Not BeIn $pkg.EnumBuilds()
            $pkg.GetBuild('2.0') | Should BeNullOrEmpty
            $pkg.Version | Should Be '1.0'
            #Testing overloads
            $pkg.AddBuild('2.0')
            $b = $pkg.Builds | Where-Object Build -eq '2.0'
            '2.0' | Should BeIn $pkg.EnumBuilds()
            $pkg.Version | Should Be '2.0'
            $pkg.RemoveBuild($b)
            '2.0' | Should Not BeIn $pkg.EnumBuilds()
            $pkg.Builds | Where-Object Build -eq '2.0' | Should BeNullOrEmpty
            $pkg.Version | Should Be '1.0'
        }
        It "should test ScriptExists method" {
            $b = $pkg.NewBuild('1.0')
            $s = Join-PSFPath -Normalize "$here\etc\sqlserver-tests\success\1.sql"
            $f = [DBOpsFile]::new($fileObject1, (Join-PSFPath -Normalize 'success\1.sql'), $true)
            $f.SetContent([DBOpsHelper]::GetBinaryFile($s))
            $b.AddFile($f, 'Scripts')
            $pkg.ScriptExists($script1) | Should Be $true
            $pkg.ScriptExists($script2) | Should Be $false
            { $pkg.ScriptExists("Nonexisting\path") } | Should Throw
        }
        It "should test ScriptModified method" {
            $b = $pkg.NewBuild('1.0')
            $f = [DBOpsFile]::new($fileObject1, (Join-PSFPath -Normalize 'success\1.sql'), $true)
            $f2 = [DBOpsFile]::new($fileObject2, (Join-PSFPath -Normalize 'success\1.sql'), $true)
            $f.SetContent([DBOpsHelper]::GetBinaryFile($script1))
            $b.AddFile($f, 'Scripts')
            $pkg.ScriptModified($script2, (Join-PSFPath -Normalize 'success\1.sql')) | Should Be $true
            $pkg.ScriptModified($script1, (Join-PSFPath -Normalize 'success\1.sql')) | Should Be $false
            $pkg.ScriptModified($f2) | Should Be $true
            $pkg.ScriptModified($f) | Should Be $false
        }
        It "should test PackagePathExists method" {
            $b = $pkg.NewBuild('1.0')
            $f = [DBOpsFile]::new($fileObject1, (Join-PSFPath -Normalize 'success\1.sql'), $true)
            $f.SetContent([DBOpsHelper]::GetBinaryFile($script1))
            $b.AddFile($f, 'Scripts')
            $pkg.PackagePathExists($f.PackagePath) | Should Be $true
            $pkg.PackagePathExists('foo') | Should Be $false
        }
        It "should test ExportToJson method" {
            $b = $pkg.NewBuild('1.0')
            $f = [DBOpsFile]::new($fileObject1, (Join-PSFPath -Normalize 'success\1.sql'), $true)
            $f.SetContent([DBOpsHelper]::GetBinaryFile($script1))
            $b.AddFile($f, 'Scripts')
            $j = $pkg.ExportToJson() | ConvertFrom-Json
            $j.Builds | Should Not BeNullOrEmpty
            $j.ConfigurationFile | Should Not BeNullOrEmpty
            $j.DeployFile | Should Not BeNullOrEmpty
            $j.ScriptDirectory | Should Not BeNullOrEmpty
            $j.psobject.properties.name | Should -BeIn @('ScriptDirectory', 'DeployFile', 'PreScripts', 'PostScripts', 'ConfigurationFile', 'Builds')
            foreach ($build in $j.Builds) {
                $build.psobject.properties.name | Should -BeIn @('Scripts', 'Build', 'PackagePath', 'CreatedDate')
                foreach ($script in $build.Scripts) {
                    $script.psobject.properties.name | Should -BeIn @('Hash', 'PackagePath')
                }
            }

        }
        It "Should test GetPackagePath method" {
            $pkg.GetPackagePath() | Should Be ''
        }
        It "Should test SetPreScripts method" {
            $f = [DBOpsFile]::new($fileObject1, (Join-PSFPath -Normalize 'success\1.sql'), $true)
            $f2 = [DBOpsFile]::new($fileObject2, (Join-PSFPath -Normalize '2.sql'), $true)
            # test one script
            $pkg.SetPreScripts($f)
            $pkg.PreScripts.Scripts.FullName | Should Be $script1
            # test two scripts
            $pkg.SetPreScripts(@($f, $f2))
            $pkg.PreScripts.Scripts.FullName | Should Be $script1, $script2
        }
        It "Should test GetPreScripts method" {
            $f = [DBOpsFile]::new($fileObject1, (Join-PSFPath -Normalize 'success\1.sql'), $true)
            $f2 = [DBOpsFile]::new($fileObject2, (Join-PSFPath -Normalize '2.sql'), $true)
            # test one script
            $preBuild = [DBOpsBuild]::new('.dbops.prescripts')
            $preBuild.AddScript($f)
            $pkg.PreScripts = $preBuild
            $pkg.GetPreScripts().FullName | Should Be $script1
            # test two scripts
            $preBuild = [DBOpsBuild]::new('.dbops.prescripts')
            $preBuild.AddScript(@($f, $f2))
            $pkg.PreScripts = $preBuild
            $pkg.GetPreScripts().FullName | Should Be $script1, $script2
        }
        It "Should test SetPostScripts method" {
            $f = [DBOpsFile]::new($fileObject1, (Join-PSFPath -Normalize 'success\1.sql'), $true)
            $f2 = [DBOpsFile]::new($fileObject2, (Join-PSFPath -Normalize '2.sql'), $true)
            # test one script
            $pkg.SetPostScripts($f)
            $pkg.PostScripts.Scripts.FullName | Should Be $script1
            # test two scripts
            $pkg.SetPostScripts(@($f, $f2))
            $pkg.PostScripts.Scripts.FullName | Should Be $script1, $script2
        }
        It "Should test GetPostScripts method" {
            $f = [DBOpsFile]::new($fileObject1, (Join-PSFPath -Normalize 'success\1.sql'), $true)
            $f2 = [DBOpsFile]::new($fileObject2, (Join-PSFPath -Normalize '2.sql'), $true)
            # test one script
            $postBuild = [DBOpsBuild]::new('.dbops.postscripts')
            $postBuild.AddScript($f)
            $pkg.PostScripts = $postBuild
            $pkg.GetPostScripts().FullName | Should Be $script1
            # test two scripts
            $postBuild = [DBOpsBuild]::new('.dbops.postscripts')
            $postBuild.AddScript(@($f, $f2))
            $pkg.PostScripts = $postBuild
            $pkg.GetPostScripts().FullName | Should Be $script1, $script2
        }
        It "Should test ReadMetadata method" {
            $b = $pkg.NewBuild('1.0')
            $f = [DBOpsFile]::new($fileObject1, (Join-PSFPath -Normalize 'success\1.sql'), $true)
            $f.SetContent([DBOpsHelper]::GetBinaryFile($script1))
            $b.AddFile($f, 'Scripts')
            $f = [DBOpsFile]::new($fileObject2, 'success/2.sql', $true)
            $f.SetContent([DBOpsHelper]::GetBinaryFile($script2))
            $b.AddFile($f, 'Scripts')
            $j = $pkg.ExportToJson()
            $md = $pkg.ReadMetadata($j)
            $md.Builds.Scripts.PackagePath | Should -Be @("success$($slash)1.sql", "success$($slash)2.sql")
        }
        It "Should test RefreshFileProperties method" {
            $pkg.RefreshFileProperties()
            $FileObject = Get-Item $packageName
            $pkg.PSPath | Should Be $FileObject.PSPath.ToString()
            $pkg.PSParentPath | Should Be $FileObject.PSParentPath.ToString()
            $pkg.PSChildName | Should Be $FileObject.PSChildName.ToString()
            $pkg.PSDrive | Should Be $FileObject.PSDrive.ToString()
            $pkg.PSIsContainer | Should Be $FileObject.PSIsContainer
            $pkg.Mode | Should Be $FileObject.Mode
            $pkg.BaseName | Should Be $FileObject.BaseName
            $pkg.Name | Should Be $FileObject.Name
            $pkg.Length | Should Be $FileObject.Length
            $pkg.DirectoryName | Should Be $FileObject.DirectoryName
            $pkg.Directory | Should Be $FileObject.Directory.ToString()
            $pkg.IsReadOnly | Should Be $FileObject.IsReadOnly
            $pkg.Exists | Should Be $FileObject.Exists
            $pkg.FullName | Should Be $FileObject.FullName
            $pkg.Extension | Should Be $FileObject.Extension
            $pkg.CreationTime | Should Be $FileObject.CreationTime
            $pkg.CreationTimeUtc | Should Be $FileObject.CreationTimeUtc
            $pkg.LastAccessTime | Should Not BeNullOrEmpty
            $pkg.LastAccessTimeUtc | Should Not BeNullOrEmpty
            $pkg.LastWriteTime | Should Be $FileObject.LastWriteTime
            $pkg.LastWriteTimeUtc | Should Be $FileObject.LastWriteTimeUtc
            $pkg.Attributes | Should Be $FileObject.Attributes
        }

        It "Should test SetConfiguration method" {
            $config = @{ SchemaVersionTable = 'dbo.NewTable' } | ConvertTo-Json -Depth 1
            { $pkg.SetConfiguration([DBOpsConfig]::new($config)) } | Should Not Throw
            $pkg.Configuration.SchemaVersionTable | Should Be 'dbo.NewTable'
        }
    }
    Context "should validate DBOpsPackage Save methods" {
        AfterAll {
            if (Test-Path $packageName) { Remove-Item $packageName }
        }
        BeforeAll {
            $pkg = [DBOpsPackage]::new()
            $pkg.SaveToFile($packageName, $true)
        }
        It "Should test RefreshModuleVersion method" {
            $pkg.RefreshModuleVersion()
            $pkg.ModuleVersion | Should Be (Get-Module dbops).Version
        }
        $oldResults = Get-ArchiveItem $packageName
        #Sleep 1 second to ensure that modification date is changed
        Start-Sleep -Seconds 2
        It "should test Save*/Alter methods" {
            $b = $pkg.NewBuild('1.0')
            $f = [DBOpsFile]::new($fileObject1, (Join-PSFPath -Normalize 'success\1.sql'), $true)
            $preFile = [DBOpsFile]::new($fileObject2, (Join-PSFPath -Normalize 'success\2.sql'), $true)
            $postFile = [DBOpsFile]::new($fileObject3, (Join-PSFPath -Normalize 'success\3.sql'), $true)
            $pkg.SetPreScripts($preFile)
            $pkg.SetPostScripts($postFile)
            $b.AddFile($f, 'Scripts')
            { $pkg.SaveToFile($packageName) } | Should Throw #File already exists
            { $pkg.Alter() } | Should Not Throw
            $testResults = Get-ArchiveItem $packageName
            foreach ($file in (Get-DBOModuleFileList)) {
                Join-PSFPath -Normalize 'Modules\dbops' $file.Path | Should BeIn $testResults.Path
            }
            'dbops.config.json' | Should BeIn $testResults.Path
            'dbops.package.json' | Should BeIn $testResults.Path
            'Deploy.ps1' | Should BeIn $testResults.Path
            Join-PSFPath -Normalize 'content\1.0\success\1.sql' | Should BeIn $testResults.Path
            Join-PSFPath -Normalize 'content\.dbops.prescripts\success\2.sql' | Should BeIn $testResults.Path
            Join-PSFPath -Normalize 'content\.dbops.postscripts\success\3.sql' | Should BeIn $testResults.Path
        }
        # Testing file contents to be updated by the Save method
        $testResults = Get-ArchiveItem $packageName
        $saveTestsErrors = 0
        foreach ($testResult in $oldResults) {
            if ($testResult.LastWriteTime -ge ($testResults | Where-Object Path -eq $testResult.Path).LastWriteTime) {
                It "Should have updated Modified date for file $($testResult.Path)" {
                    $testResult.LastWriteTime -lt ($testResults | Where-Object Path -eq $testResult.Path).LastWriteTime | Should Be $true
                }
                $saveTestsErrors++
            }
        }
        if ($saveTestsErrors -eq 0) {
            It "Ran silently $($oldResults.Length) file modification tests" {
                $saveTestsErrors | Should be 0
            }
        }
    }
}