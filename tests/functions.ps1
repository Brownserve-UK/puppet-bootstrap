# Functions to be used within tests


# Waits until Puppet has applied idempotently
function Wait-UntilConvergence
{
    [CmdletBinding()]
    param(
        [string] $ComputerName,
        [string] $PuppetServer,
        [string] $PuppetDBPort,
        # Timeout in mins. Default to 300min (5h)
        [int] $Timeout = 30
    )

    Write-Verbose 'Checking Puppet state...'
    $startTime = [datetime]::UtcNow
    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    try
    {
        $LastReportSummary = @{ latest_report_status = 'AnyStringWillDo' }
        while ($LastReportSummary.latest_report_status -ne 'unchanged')
        {
            if ($watch.Elapsed.TotalMinutes -gt $Timeout)
            {
                throw "Timed out waiting for $ComputerName to reach desired state after $Timeout minutes..."
            }

            Start-Sleep 90

            try
            {
                Write-Verbose "Probing http://${PuppetServer}:${PuppetDBPort}/pdb/query/v4/nodes/${ComputerName}"
                $LastReportSummary = Invoke-RestMethod "http://${PuppetServer}:${PuppetDBPort}/pdb/query/v4/nodes/${ComputerName}"
            }
            catch
            {
                # Print any error as a warning - we want to continue in case PuppetDB isn't ready yet
                $errorFromPuppetDb = $_.ErrorDetails.Message
                $errorMessage = $_.Exception.Message
            }
            if ($errorMessage -or $errorFromPuppetDb)
            {
                # We need to use another try catch block to avoid having the ConvertFrom-Json error message bomb out the whole script :(
                try
                {
                    $errorFromPuppetDb = ($errorFromPuppetDb | ConvertFrom-Json -ErrorAction SilentlyContinue).error
                    # If we can ConvertFrom-Json the error, then we know it's a PuppetDB error 
                    Write-Warning $errorFromPuppetDb
                }
                catch
                {
                    # Otherwise it's a generic error
                    Write-Warning $errorMessage
                }
            }
            else
            {
                Write-Verbose "Last report status: $($LastReportSummary.latest_report_status)"
            }
        }

        Write-Host 'Reached desired state.'
        Write-Debug @"
`$LastReportSummary.latest_report_status=$($LastReportSummary.latest_report_status)
`$LastReportSummary.report_timestamp=$($LastReportSummary.report_timestamp)
`$starttime=${starttime}
"@

    }
    finally
    {
        $watch.Stop()
    }
}