$moduleName = "Advanced-PRTG-Sensors"
$moduleRoot = Resolve-Path "$PSScriptRoot\.."

Describe "General project validation: $moduleName" {

    $scripts = Get-ChildItem $moduleRoot -Include *.ps1, *.psm1, *.psd1 -Recurse
    $testCase = $scripts | Foreach-Object {@{file = $_}}
    It "Script <file> should be valid powershell" -TestCases $testCase {
        param($file)

        $file.fullname | Should Exist
        $contents = Get-Content -Path $file.fullname -ErrorAction Stop
        $errors = $null
        $null = [System.Management.Automation.PSParser]::Tokenize($contents, [ref]$errors)
        $errors.Count | Should Be 0
    }

    Import-Module PSScriptAnalyzer -Force
    It 'Script <file> should not have Errors in PSScriptAnalyzer analysis' -TestCases $testCase {
        param($file)

        $file.fullname | Should Exist
        $ScriptAnalyzerResults = Invoke-ScriptAnalyzer -Path $file.fullname -Severity Error
        $ScriptAnalyzerResults | Should BeNullOrEmpty

    }

    $modules = Get-ChildItem $moduleRoot -Include *.psd1 -Recurse
    if ($modules) {
    $testCase = $modules | Foreach-Object {@{file = $_}}
    It "Module <file> can import cleanly" -TestCases $testCase {
        param($file)

        $file.fullname | Should Exist
        $error.clear()
        {Import-Module  $file.fullname } | Should Not Throw
        $error.Count | Should Be 0
    }
}

Describe "Individual Sensor Tests" {

    It "PRTG-VeeamBRStats Script should include Debug Region" {
        "$moduleRoot\Veeam\PRTG-VeeamBRStats.ps1" | Should FileContentMatch "#region: Debug"
    }

    It "PRTG-VeeamBRStats Script should include Debug Example" {
        "$moduleRoot\Veeam\PRTG-VeeamBRStats.ps1" | Should FileContentMatch 'PRTG-VeeamBRStats.ps1 -BRHost veeam01.lan.local -reportmode "Monthly" -repoCritical 80 -repoWarn 70 -Debug'
    }

    It "PRTG-VeeamBRStats Script should include PRTG XML Root" {
        "$moduleRoot\Veeam\PRTG-VeeamBRStats.ps1" | Should FileContentMatch 'Write-Output "<prtg>"'
        "$moduleRoot\Veeam\PRTG-VeeamBRStats.ps1" | Should FileContentMatch 'Write-Output "</prtg>"'
    }

}
}
