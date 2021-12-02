<#
.SYNOPSIS
    This tests the Puppet agent bootstrap process on Windows and Linux.
.DESCRIPTION
    This script will test the Puppet agent bootstrap process on Windows and Linux.
    It is intended to be run inside a virtual machine or a container.
    It uses the puppet_hiera_example repository to test the bootstrap process.
#>
[CmdletBinding()]
param (
    # The branch/environment to use
    [Parameter(Mandatory = $false, Position = 0)]
    [string]
    $Environment
)
$ErrorActionPreference = 'Stop'
# dotsource our functions
. (Join-Path $PSScriptRoot 'functions.ps1')

$PuppetVersion = 6
$PuppetServer = 'puppetserver'
$DomainName = 'local'
$pp_environment = 'live'
if ($Environment -eq 'dev')
{
    $PuppetVersion = 7
    $pp_environment = 'staging'
    $DomainName = 'dev'
}
if ($IsLinux)
{
    $Hostname = & hostname
    $pp_service = 'webserver'
    $pp_role = 'nginx'
}
if ($IsWindows)
{
    $Hostname = $env:ComputerName
    $pp_service = 'fileserver'
    $pp_role = 'smb'
    # At the time of writing, Puppet seems to be absorbing any local DNS into the FQDN for Workgroup machines.
    # (eg if the machine is vagrant.local but we have a DNS server for foobar.com on our network Puppet is creating a csr for vagrant.foobar.com)
    # Almost certainly not a problem in usual operation but for Vagrant it most certainly is.
    # So we override the certname when testing.
    $CertName = ("$Hostname.$DomainName").ToLower()
}

$CSRExtensions = @{
    pp_environment = $pp_environment
    pp_service = $pp_service
    pp_role = $pp_role
}

$AgentArgs = @{
    MajorVersion = $PuppetVersion
    PuppetServer = $PuppetServer
    PuppetEnvironment = $Environment
    CSRExtensions = $CSRExtensions
    DomainName = $DomainName
    SkipOptionalPrompts = $true
    SkipConfirmation = $true
}
if ($CertName)
{
    $AgentArgs.Add('CertificateName',$CertName)
}

/vagrant/puppet-agent.ps1 @AgentArgs

# Do a second run of Puppet to check for idempotency
if ($IsWindows)
{
    # On Windows we seem to be getting clashing Puppet runs, so try to space them out a bit
    Start-Sleep 120
    & puppet agent -t
}
else
{
    & /opt/puppetlabs/puppet/bin/puppet agent -t
}

# This probably needs to come out into the calling logic so if a node is rebooted it doesn't die!
Wait-UntilConvergence -ComputerName ("$Hostname.$DomainName").ToLower() -PuppetServer "$PuppetServer.$DomainName" -PuppetDBPort "8080" -Verbose