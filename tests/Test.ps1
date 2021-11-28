<#
.SYNOPSIS
    Performs basic testing of the bootstrap process.
.DESCRIPTION
    This script performs basic testing of the bootstrap process by spinning up test instances based off of the puppet_hiera_example
    repository and then running the bootstrap script against them.
#>
[CmdletBinding()]
param
(
    # The environment to use for the test
    [Parameter(Mandatory = $false)]
    [string]
    [ValidateSet('production', 'dev')]
    $Environment = 'production'
)
$ErrorActionPreference = 'stop'

# First we need to vagrant up the test environment
Push-Location
Set-Location (Join-Path $PSScriptRoot '..')

try
{
    & vagrant up
    if ($LastExitCode -ne 0)
    {
        Write-Error 'Failed to vagrant up the test environment'
    }

    # Start by provisioning the Puppet server
    & vagrant ssh puppetserver -c "sudo pwsh -f /vagrant/tests/Puppet-Server.ps1 -GitHubBranch '$Environment'"
    if ($LastExitCode -ne 0)
    {
        Write-Error 'Failed to provision the Puppet server'
    }

    # Try connecting to Puppet board, it should be on port 8000 which is forwarded to port 80 via vagrant.
    $URI = 'http://127.0.0.1:8000/'
    if ($Environment -eq 'dev')
    {
        $URI += 'dev/'
    }
    $PuppetBoardTest = Invoke-WebRequest -Uri  -Method Get
    if ($PuppetBoardTest.StatusCode -ne 200)
    {
        Write-Error 'Failed to connect to the PuppetBoard'
    }

    # Next try the linux agent
    & vagrant ssh puppetagent-linux -c "sudo pwsh -f /vagrant/tests/Puppet-Agent.ps1 -Environment '$Environment'"
    if ($LastExitCode -ne 0)
    {
        Write-Error 'Failed to provision the Puppet Linux agent'
    }

    # Finally try the windows agent
    & vagrant winrm puppetagent-windows -e -c "pwsh -f C:\Vagrant\tests\Puppet-Agent.ps1 -Environment '$Environment'" 
    if ($LastExitCode -ne 0)
    {
        Write-Error 'Failed to provision the Puppet Windows agent'
    }

    Write-Host "All nodes successfully reached their desired state. 🎉" -ForegroundColor Green
}
catch
{
    throw $_.Exception.Message
}
finally
{
    # Clean up the test environment
    & vagrant destroy -f
    Pop-Location
}