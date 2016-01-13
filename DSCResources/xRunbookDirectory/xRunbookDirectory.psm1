function Get-TargetResource
{
	[CmdletBinding()]
	[OutputType([System.Collections.Hashtable])]
	param
	(
		[parameter(Mandatory = $true)]
		[System.String]
		$RunbookPath,

		[System.Boolean]
		$Publish = $true,

		[parameter(Mandatory = $true)]
		[System.String]
		$WebServiceEndpoint,

		[Int]
		$Port = 9090
	)

	$RunbookPathItems = Get-Item $RunbookPath -Filter *.ps1

    $match = $true
    forEach ($RunbookPathItem in $RunbookPathItems)
    {
        if( $match )
        {
            Write-Verbose "Finding runbook definition for $($RunbookPathItem.BaseName)."

            # Get runbook definition if one exist
            $runbookFound = $false
            try
            {
                if( $publish )
                {
                    $runbookDefinition = Get-SmaRunbookDefinition -Name $($RunbookPathItem.BaseName) -WebServiceEndpoint $WebServiceEndpoint -Port $port -Type 'Published' -ErrorAction Stop
                }
                else
                {
                    $runbookDefinition = Get-SmaRunbookDefinition -Name $($RunbookPathItem.BaseName) -WebServiceEndpoint $WebServiceEndpoint -Port $port -Type 'Draft' -ErrorAction Stop
                }

                $runbookFound = $true
                Write-Verbose "Existing Runbook definition found."
            }
            catch
            {
                Write-Verbose $_ 
                $match = $false
            }

            if( $runbookFound )
            {
                # Can't compare the value of the $runbookDefinition.Content variable to a file, so writing it to a file, then will compare that.
                Write-Verbose "Creating temp file at $env:TEMP\$($RunbookPathItem.BaseName).ps1"
                $runbookDefinition.Content.ToString() | Out-File -FilePath "$env:TEMP\$($RunbookPathItem.BaseName).ps1"

                $compare = Compare-Object -ReferenceObject (Get-Content $RunbookPathItem.FullName) -DifferenceObject (Get-Content "$env:TEMP\$($RunbookPathItem.BaseName).ps1")
                if( $compare -eq $null )
                {
                    Write-Verbose "Runbook found matches. No import needed."
                }
                Else
                {
                    # Compare-Object sometimes returns new lines as a difference, this can cause repeated re-imports if that new line is at the top of the ps1
                    # since SMA will strip this out on import.

                    foreach( $difference in $compare )
                    {
                        if( $difference.InputObject -ne "" )
                        {
                            Write-Verbose "Runbook differences found. New import needed."
                            $match = $false
                        }
                    }

                    if( $match )
                    {
                        Write-Verbose "Runbook found matches. No import needed."
                    }
                }

                Write-Verbose "Removing temp file at $env:TEMP\$($RunbookPathItem.BaseName).ps1"
                Remove-Item -Path "$env:TEMP\$($RunbookPathItem.BaseName).ps1"
            }
        }
    }

	$returnValue = @{
		RunbookPath = [System.String]$RunbookPath
		WebServiceEndpoint = [System.String]$WebServiceEndpoint
		Port = [System.String]$Port
		Publish = [System.Boolean]$Publish
		Matches = [System.Boolean]$match
	}

	$returnValue
}


function Set-TargetResource
{
	[CmdletBinding()]
	param
	(
		[parameter(Mandatory = $true)]
		[System.String]
		$RunbookPath,

		[System.Boolean]
		$Publish = $true,

		[parameter(Mandatory = $true)]
		[System.String]
		$WebServiceEndpoint,

		[Int]
		$Port = 9090
	)

	$RunbookPathItems = Get-Item $RunbookPath

    Write-Verbose "Importing all runbooks twice to build all dependencies." 
    for($k = 1; $k -lt 3; $k++)
    {
        Write-Verbose "Import number $k"
        forEach ($RunbookPathItem in $RunbookPathItems)
        {
            # try to edit an existing runbook with the same name, this saves a read to verify that the runbook exist.
            # if error, assume the runbook has never been imported
            Write-Verbose "Importing Runbook $($RunbookPathItem.BaseName)."
	        try
            {
                Edit-SmaRunbook -Path $RunbookPathItem.FullName -Name $RunbookPathItem.BaseName -WebServiceEndpoint $WebServiceEndpoint -Port $port -Overwrite -ErrorAction Stop
            }
            catch
            {
                Import-SmaRunbook -Path $RunbookPathItem.FullName -WebServiceEndpoint $WebServiceEndpoint -Port $port -ErrorAction Stop
            }      
        }
    }

    if( $publish )
    {
        forEach ($RunbookPathItem in $RunbookPathItems)
        {
            Publish-SmaRunbook -Name $RunbookPathItem.BaseName -WebServiceEndpoint $WebServiceEndpoint -Port $port
        }
    }
}


function Test-TargetResource
{
	[CmdletBinding()]
	[OutputType([System.Boolean])]
	param
	(
		[parameter(Mandatory = $true)]
		[System.String]
		$RunbookPath,

		[System.Boolean]
		$Publish = $true,

		[parameter(Mandatory = $true)]
		[System.String]
		$WebServiceEndpoint,

		[Int]
		$Port = 9090
	)

    $results = (Get-TargetResource @PSBoundParameters).Matches -eq $true

    if( $results )
    {
        Write-Verbose "A runbook import is not required"
        return $true
    }
    else
    {
        Write-Verbose "A runbook import is required"
        return $false
    }
}


Export-ModuleMember -Function Get-TargetResource, Set-TargetResource, Test-TargetResource

