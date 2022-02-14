function Update-PesterTest {
    <#
        .SYNOPSIS
        The function intended to update Pester tests notation from version 3.x to 4.x.

        .DESCRIPTION
        Notation for the Should assertion changed between Pester version 3.x and 4.x.
        The function helps to update existing Pester 3.x tests to the new notation.

        Please be aware that if your original Pester test files are encoded differently than UTF-8
        than the final files encoding will be Unicode (UTF-7) / ASCSI.

        .PARAMETER Path
        Path to the file that contain Pester tests to update.

        .PARAMETER Destination
        Path to the file for which updated tests will be saved.

        If the Destination parameter is ommitted tests will be updated in place.
        The content of an original file will be replaced.

        .EXAMPLE

        Update-PesterTest -Path .\Pester3-Tests\Dumy.Tests.ps1 .\Pester4-Tests\Dumy.Tests.ps1

        .NOTES
        Original author
        Chris Dent, @indented-automation

        Updates
        Wojciech Sciesinski, @it-praktyk

        LICENSE
        Copyright 2017 Chris Dent

        Licensed under the Apache License, Version 2.0 (the "License");
        you may not use this file except in compliance with the License.
        You may obtain a copy of the License at

        http://www.apache.org/licenses/LICENSE-2.0

        Unless required by applicable law or agreed to in writing, software
        distributed under the License is distributed on an "AS IS" BASIS,
        WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
        See the License for the specific language governing permissions and
        limitations under the License.

        .LINK
        https://github.com/pester/Pester/issues/892
        https://gist.github.com/indented-automation/aeb14825e39dd8849beee44f681fbab3
        https://gist.github.com/jpoehls/2406504
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('FullName')]
        [System.IO.FileInfo]$Path,
        [Parameter(Mandatory = $false)]
        [String]$Destination
    )

    begin {
        $shouldParams = [String[]](Get-Command Should).Parameters.Keys
        $destIsEmpty = [String]::IsNullOrEmpty($Destination)
    }

    process {
        $Path = $pscmdlet.GetUnresolvedProviderPathFromPSPath($Path)

        $encoding = Get-FileEncoding -Path $Path

        [String]$MessageText = "The file {0} will be {1} encoded." -f $Path, $encoding

        Write-Verbose -Message $MessageText

        $errors = $tokens = @()
        $ast = [System.Management.Automation.Language.Parser]::ParseFile(
            $Path,
            [Ref]$tokens,
            [Ref]$errors
        )

        $script = Get-Content $Path -Raw -Encoding $encoding
        $ast.FindAll(
            {
                param ( $ast )

                $ast -is [System.Management.Automation.Language.CommandAst] -and
                $ast.GetCommandName() -eq 'Should'
            },
            $true
        ) |
        ForEach-Object {
            $_.CommandElements | Where-Object {
                $_.StringConstantType -eq 'BareWord' -and
                $_.Value -in $shouldParams -or
                $_.Value -eq 'Contain'
            }
        } |
        Sort-Object { $_.Extent.StartOffset } -Descending |
        ForEach-Object {
            if ($_.Value -eq 'Contain') {
                $script = $script.Remove($_.Extent.StartOffset, 7).Insert($_.Extent.StartOffset, '-FileContentMatch')
            }
            else {
                $script = $script.Insert($_.Extent.Startoffset, '-')
            }
        }

        if ( $destIsEmpty) { $Destination = $Path }

        Set-Content -Path $Destination -Value $script -NoNewline -Encoding $encoding
    }

}

function Get-FileEncoding {
    # source https://gist.github.com/jpoehls/2406504
    # simplified.

    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $True, ValueFromPipelineByPropertyName = $True)]
        [string]$Path
    )

    [byte[]]$byte = get-content -Encoding byte -ReadCount 4 -TotalCount 4 -Path $Path

    if ( $byte[0] -eq 0xef -and $byte[1] -eq 0xbb -and $byte[2] -eq 0xbf )
    { Write-Output 'UTF8' }

    else
    { Write-Output 'ASCII' }
}

$files = Get-ChildItem -Path "C:\Users\Sander\source\repos\PowerShell\PStSQLtTestGenerator\tests\general" | Where-Object { $_.Name -like '*.Tests.ps1' }

foreach ($file in $files) {
    Update-PesterTest -Path $file.FullName -Destination "C:\Users\Sander\source\repos\PowerShell\PStSQLtTestGenerator\tests\general\new\$($file.Name)" -Verbose
}

