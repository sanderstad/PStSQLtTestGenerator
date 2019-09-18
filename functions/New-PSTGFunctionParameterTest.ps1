function New-PSTGFunctionParameterTest {
    <#
    .SYNOPSIS
        Function to create parameter tests

    .DESCRIPTION
        The function will retrieve the current parameters for a function and create a test for it

    .PARAMETER Function
        Function(s) to create tests for

    .PARAMETER OutputPath
        Path to output the test to

    .PARAMETER TemplateFolder
        Path to template folder. By default the internal templates folder will be used

    .PARAMETER InputObject
        Takes the parameters required from a Function object that has been piped into the command

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .EXAMPLE
        New-PSTGFunctionParameterTest -Function $function -OutputPath $OutputPath

        Create a new function parameter test

    .EXAMPLE
        $functions | New-PSTGFunctionParameterTest -OutputPath $OutputPath

        Create the tests using pipelines
    #>

    [CmdletBinding()]

    param(
        [parameter(ParameterSetName = "Function", Mandatory)]
        [object[]]$Function,
        [string]$OutputPath,
        [string]$TemplateFolder,
        [parameter(ParameterSetName = "InputObject", ValueFromPipeline)]
        [object]$InputObject,
        [switch]$EnableException
    )

    begin {
        # Check the output path
        if (-not $OutputPath) {
            Stop-PSFFunction -Message "Please enter an output path"
            return
        }

        if (-not (Test-Path -Path $OutputPath)) {
            Stop-PSFFunction -Message "Could not access output path" -Category ResourceUnavailable -Target $OutputPath
        }

        # Check the template folder
        if (-not $TemplateFolder) {
            $TemplateFolder = Join-Path -Path ($script:ModuleRoot) -ChildPath "internal\templates"
        }

        if (-not (Test-Path -Path $TemplateFolder)) {
            Stop-PSFFunction -Message "Could not find template folder" -Target $OutputPath
        }

        $date = Get-Date -Format (Get-culture).DateTimeFormat.ShortDatePattern
        $creator = $env:username
    }

    process {
        if (Test-PSFFunctionInterrupt) { return }

        if (-not $InputObject -and -not $Function) {
            Stop-Function -Message "You must pipe in an object or specify a Function"
            return
        }

        if ($Function) {
            $InputObject = $Function
        }

        if ($InputObject[0].GetType().Name -ne 'UserDefinedFunction') {
            Stop-Function -Message "The object is not a valid type '$($InputObject[0].GetType().Name)'" -Target $InputObject
            return
        }

        foreach ($input in $InputObject) {
            $testName = "test If function $($input.Schema).$($input.Name) has the correct parameters Expect Success"

            # Test if the name of the test does not become too long
            if ($testName.Length -gt 128) {
                Stop-PSFFunction -Message "Name of the test is too long" -Target $testName
            }

            $fileName = Join-Path -Path $OutputPath -ChildPath "$($testName).sql"

            # Get the parameters
            $parameters = $input.Parameters

            if ($parameters.Count -ge 1) {
                # Import the template
                try {
                    $script = Get-Content -Path (Join-Path -Path $TemplateFolder -ChildPath "FunctionParameterTest.template")
                }
                catch {
                    Stop-PSFFunction -Message "Could not import test template 'FunctionParameterTest.template'" -Target $testName -ErrorRecord $_
                }

                $paramTextCollection = @()

                # Loop through the parameters
                foreach ($parameter in $parameters) {
                    $paramText = "`t('$($parameter.Name)', '$($parameter.DataType.Name)', $($parameter.DataType.MaximumLength), $($parameter.DataType.NumericPrecision), $($parameter.DataType.NumericScale))"
                    $paramTextCollection += $paramText
                }

                # Replace the markers with the content
                $script = $script.Replace("___TESTNAME___", $testName)
                $script = $script.Replace("___SCHEMA___", $input.Schema)
                $script = $script.Replace("___NAME___", $input.Name)
                $script = $script.Replace("___CREATOR___", $creator)
                $script = $script.Replace("___DATE___", $date)
                $script = $script.Replace("___PARAMETERS___", ($paramTextCollection -join ",`n") + ";")

                # Write the test
                try {
                    Write-PSFMessage -Message "Creating function parameter test for function '$($Function.Schema).$($Function.Name)'"
                    $script | Out-File -FilePath $fileName
                }
                catch {
                    Stop-PSFFunction -Message "Something went wrong writing the test" -Target $testName -ErrorRecord $_
                }
            }
            else {
                Write-PSFMessage -Message "Function $($Function.Schema).$($Function.Name) does not have any parameters. Skipping..."
            }
        }
    }
}