function Remove-IllegalCharacters {

    [CmdLetBinding()]

    param(
        [string]$Value,
        [string]$Type
    )

    begin {
        if (-not $Type) {
            Stop-PSFFunction -Message "Please enter a type"
        }
    }

    process {
        if(Test-PSFFunctionInterrupt){ return }

        switch ($Type) {

            "Path" {
                # < (less than)
                # > (greater than)
                # : (colon - sometimes works, but is actually NTFS Alternate Data Streams)
                # " (double quote)
                # / (forward slash)
                # \ (backslash)
                # | (vertical bar or pipe)
                # ? (question mark)
                # * (asterisk)

                $Value = $Value -replace "\<|\>|\/|\||\?|\*", ''
            }
        }

        return $Value
    }
}