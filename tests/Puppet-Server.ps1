<#
.SYNOPSIS
    This script tests the Puppet server bootstrap process.
.DESCRIPTION
    This script tests the Puppet server bootstrap process.
    It is intended to be run from within a VM or docker container.
    This only works with the puppet_hiera_example repository
#>
#Requires -Version 6
[CmdletBinding()]
param
(
    # The GitHub repository to use for testing
    [Parameter(Mandatory = $false, Position = 0)]
    [string]
    $GitHubRepo = 'https://github.com/Brownserve-UK/puppet_hiera_example.git',

    # The branch to use for testing
    [Parameter(Mandatory = $false, Position = 1)]
    [string]
    $GitHubBranch = 'production'
)
$ErrorActionPreference = 'Stop'
# dotsource our functions
. (Join-Path $PSScriptRoot 'functions.ps1')

$PuppetVersion = 6
$GitHubRepoURL = $GitHubRepo -replace '\.git', ''
$RAWGitHubRepoURL = $GitHubRepoURL -replace 'github.com', 'raw.githubusercontent.com'

$PrivateKeyPath = "$RAWGitHubRepoURL/$GitHubBranch/keys/private_key.pkcs7.pem"
$PublicKeyPath = "$RAWGitHubRepoURL/$GitHubBranch/keys/public_key.pkcs7.pem"

try
{
    $PrivateKey = Invoke-WebRequest $PrivateKeyPath | Select-Object -ExpandProperty Content
    $PublicKey = Invoke-WebRequest $PublicKeyPath | Select-Object -ExpandProperty Content
}
catch
{
    throw "Unable to retrieve private and public keys from GitHub.`n$($_.Exception.Message)"
}

$DomainName = 'local'
if ($GitHubBranch -eq 'dev')
{
    $DomainName = 'dev'
    $PuppetVersion = 7
}
$Hostname = "puppet$PuppetVersion"

$CSRExtensions = @{
    pp_environment = $GitHubBranch
    pp_service     = 'puppetserver'
    pp_role        = "puppet$PuppetVersion"
}

/vagrant/puppet-server.ps1 `
    -Hostname $Hostname `
    -MajorVersion $PuppetVersion `
    -DomainName $DomainName `
    -PuppetserverClass 'puppetserver' `
    -CSRExtensions $CSRExtensions `
    -GitHubRepo $GitHubRepoURL `
    -BootstrapEnvironment $GitHubBranch `
    -BootstrapHiera 'hiera.bootstrap.yaml' `
    -eyamlKeyPath '/etc/puppetlabs/puppet/keys' `
    -eyamlPrivateKey $PrivateKey `
    -eyamlPublicKey $PublicKey `
    -SkipOptionalPrompts `
    -SkipConfirmation

# Perform a second run to check for idempotency
& /opt/puppetlabs/puppet/bin/puppet agent -t

Wait-UntilConvergence -ComputerName "$Hostname.$DomainName" -PuppetServer "$Hostname.$DomainName" -PuppetDBPort "8080" -Verbose
