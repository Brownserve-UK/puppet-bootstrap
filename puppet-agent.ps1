<#
.SYNOPSIS
    Bootstraps the installation of Puppet agent on a node
.DESCRIPTION
    Long description
.EXAMPLE
    PS C:\> <example usage>
    Explanation of what the example does
.INPUTS
    Inputs (if any)
.OUTPUTS
    Output (if any)
.NOTES
    General notes
#>
[CmdletBinding()]
param (
    # The major version of Puppet agent to install
    [Parameter(Mandatory = $false)]
    [int]
    $MajorVersion,

    # The exact version of Puppet agent to install
    [Parameter(Mandatory = $false)]
    [version]
    $ExactVersion,

    # The Puppet server to connect to
    [Parameter(Mandatory = $true)]
    [string]
    $PuppetServer,

    # The Puppet server port to connect to
    [Parameter(Mandatory = $false)]
    [int]
    $PuppetServerPort = 8140,

    # The Puppet environment to use
    [Parameter(Mandatory = $false)]
    [string]
    $PuppetEnvironment,

    # Set this to change the default certificate name
    [Parameter(Mandatory = $false)]
    [string]
    $CertificateName,

    # Any certificate extensions to add to the Puppet agent certificate
    [Parameter(Mandatory = $false)]
    [hashtable]
    $CSRExtensions,

    # Whether or not to enable the service at system startup
    [Parameter(Mandatory = $false)]
    [string]
    $EnableService = $true,

    # If set the Puppet agent will wait for the certificate to be signed before continuing
    [Parameter(Mandatory = $false)]
    [string]
    $WaitForCert = 30,

    # If set will change the Hostname of this node
    [Parameter(Mandatory = $false)]
    [string]
    $NewHostname,

    # Your domain name
    [Parameter(Mandatory = $true)]
    [string]
    $DomainName,

    # Skip the Puppetserver check
    [Parameter(Mandatory = $false)]
    [switch]
    $SkipPuppetserverCheck,

    # Skips all optional prompts
    [Parameter(Mandatory = $false)]
    [switch]
    $SkipOptionalPrompts,

    # Skips the confirmation prompt
    [Parameter(Mandatory = $false)]
    [switch]
    $SkipConfirmation,

    # Skips the initial Puppet run, useful in some edge-cases
    [switch]
    $SkipInitialRun
)
#Requires -Version 6

$ErrorActionPreference = 'Stop'

function Get-Response
{
    param
    (
        # The prompt to post on screen
        [Parameter(
            Mandatory = $true,
            Position = 0
        )]
        [string]
        $Prompt,

        # The type of value to return
        [Parameter(
            Mandatory = $true,
            Position = 1
        )]
        [string]
        [ValidateSet('string', 'bool', 'array')]
        $ResponseType,

        # Make the response mandatory (applies to string and arrays only)
        [Parameter(
            Mandatory = $false
        )]
        [switch]
        $Mandatory
    )
    # I've seen some weirdness where $Response can end up hanging around so set it to $null every time this cmdlet is called.
    $Response = $null
    switch ($ResponseType)
    {
        'bool'
        {
            # Booleans are always mandatory by their very nature 
            while (!$Response)
            {
                $Response = Read-Host "$Prompt [y]es/[n]o"
                switch ($Response.ToLower())
                {
                    { ($_ -eq 'y') -or ($_ -eq 'yes') }
                    {
                        Return $true
                    }
                    { ($_ -eq 'n') -or ($_ -eq 'no') }
                    {
                        Return $false
                    }
                    Default
                    {
                        Write-Host "Invalid response '$Response'" -ForegroundColor red
                        Clear-Variable 'Response'
                    }
                }
            }    
        }
        'string'
        {
            # If the string is mandatory then keep prompting until we get a valid response
            if ($Mandatory)
            {
                While (!$Response)
                {
                    $Response = Read-Host $Prompt
                }
            }
            # If not then allow us to skip
            else
            {
                $Prompt = $Prompt + ' (Optional - press enter to skip)'
            }
            # Only return an object if we have one
            if ($Response)
            {
                Return [string]$Response
            }
        }
        'array'
        {
            # If the array is mandatory then keep prompting until we get a value
            if ($Mandatory)
            {
                While (!$Response)
                {
                    $Response = Read-Host "$Prompt [if specifying more than one separate with a comma]"
                }
            }
            # Otherwise allow the user to skip by hitting enter
            else
            {
                $Response = Read-Host "$Prompt [if specifying more than one separate with a comma] (Optional - press enter to skip)"
            }
            # Only return an object if we have one
            if ($Response)
            {
                $Array = $Response -split ','
                Return $Array
            }
        }
    }
}
function Test-Administrator
{
    if ($IsWindows)
    {
        $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
        $Return = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        Return $Return
    }
    else
    {
        $RootCheck = & id -u
    
        if ($RootCheck -eq 0)
        {
            return $true
        }
        else
        {
            return $false
        }
    }
}
function Get-CSRAttributes 
{
    $Continue = $true
    $CSRExtensions = @{}
    while ($Continue)
    {
        $KeyName = Get-Response 'Please enter the key name (e.g pp_environment)' 'string' -Mandatory
        $Value = Get-Response "Please enter the value for '$KeyName'" 'string' -Mandatory
        $CSRExtensions.Add($KeyName, $Value)
        $Continue = Get-Response 'Would you like to add another key? [y]es/[n]o' 'bool'
    }
}

### Pre-install checks ###
if (!$MajorVersion -and !$ExactVersion)
{
    $VersionPrompt = $null
    while ($VersionPrompt -notmatch '^[0-9]+$')
    {
        $VersionPrompt = Read-Host -Prompt 'Enter the major version of Puppet agent to install (e.g. 7): '
    }
    try
    {
        $MajorVersion = [int]$VersionPrompt
    }
    catch
    {
        throw "Failed to convert $VersionPrompt to int"
    }
}
if ($MajorVersion -and $ExactVersion)
{
    Write-Warning 'Both MajorVersion and ExactVersion were specified, ExactVersion will be used.'
}
if ($ExactVersion)
{
    $MajorVersion = $ExactVersion.Major
}
Write-Verbose "Installing Version $MajorVersion"
# Check if we are running as an administrator
if (!(Test-Administrator))
{
    throw 'You must run this script as an administrator'
}
# Make sure the PuppetServer is a valid FQDN
if ($PuppetServer -notmatch "$($DomainName)$")
{
    $PuppetServer = "$($PuppetServer).$($DomainName)"
}
# Check we can contact the Puppet Server
if (!$SkipPuppetserverCheck)
{
    $arguments = @($PuppetServer)
    if (!$IsWindows)
    {
        $arguments += @('-c', 4)
    }
    $PuppetServerPing = & ping $arguments
    if ($LASTEXITCODE -ne 0)
    {
        $PuppetServerPing
        throw "Unable to ping $PuppetServer, are you sure it's correct?"
    }
}
###

### Prompt for optional information ###
if (!$SkipOptionalPrompts)
{
    if (!$PuppetEnvironment)
    {
        $PuppetEnvironment = Get-Response 'Enter the Puppet environment to use (e.g production), press enter to skip' 'string'
    }
    if (!$CSRExtensions)
    {
        $CSRExtensionCheck = Get-Response 'Do you want to add CSR extensions?' 'bool'
        if ($CSRExtensionCheck)
        {
            $CSRExtensions = Get-CSRAttributes
        }
    }
}
# Always get current hostname so we can skip setting it if it's not changing
if ($IsLinux -or $IsMacOS)
{
    $CurrentNodeName = & hostname
}
if ($IsWindows)
{
    $CurrentNodeName = $env:ComputerName
}
if (!$NewHostname)
{
    if (!$SkipOptionalPrompts)
    {
        Write-Host "Current hostname: $($CurrentNodeName)"
        $ChangeHostname = Get-Response 'Do you want to change the hostname?' -ResponseType 'bool'
    }
    if ($ChangeHostname)
    {
        $NewHostname = Get-Response 'Enter the new hostname' -ResponseType 'string' -Mandatory
    }
    else
    {
        $NewHostname = $CurrentNodeName
    }
}
# On Nix ensure the hostname is lowercase and fully qualified
if (($NewHostname -notmatch "$($DomainName)$") -and (!$IsWindows))
{
    $NewHostname = "$($NewHostname).$($DomainName)"
    $NewHostName = $NewHostname.ToLower()
}
# On Windows ensure the hostname is NOT fully qualified 
if (($NewHostname -match "$($DomainName)$") -and $IsWindows)
{
    $NewHostName -replace "\.$($DomainName)", ''
}
###

### Double check the user wants to continue ###
$Message = "`nPuppet will be installed with the following options:`n`n"
$Message += @"
    Puppet Server: $PuppetServer
    Puppet Server Port: $PuppetServerPort
    Hostname: $NewHostname`n
"@
if ($CSRExtensions)
{
    $Message += "    Certificate Extensions:`n"
    $CSRExtensions.GetEnumerator() | ForEach-Object {
        $Message += "       $($_.Key): $($_.Value)`n"
    }

}
if ($CertificateName)
{
    $Message += "    Certificate Name: $($CertificateName)`n"
}
if ($WaitForCert -gt 0)
{
    $Message += "    Wait for certificate: $($WaitForCert)s`n"
}
if ($EnableService)
{
    $Message += "    Enable Puppet Service: $($EnableService)`n"
}
    
if (!$SkipConfirmation)
{
    $Message += "`nDo you want to continue?"
    $Confirm = Get-Response $Message -ResponseType 'bool'
    if (!$Confirm)
    {
        throw 'User cancelled installation'
    }
}
else
{
    Write-Host $Message
}


### Begin by making sure the Machine is ready to go with Puppet ###
### Begin bootstrap ###
Write-Host 'Beginning bootstrap process' -ForegroundColor Magenta

# Check for the presence of the PuppetPowerShell module and install it if it's not present
try
{
    $PuppetPowerShellCheck = Get-InstalledModule 'PuppetPowerShell' -ErrorAction SilentlyContinue
}
catch
{
    # Don't do anything - we'll install it below
}

if (!$PuppetPowerShellCheck)
{
    Write-Host 'Installing PuppetPowerShell module' -ForegroundColor Magenta
    try
    {
        Install-Module -Name 'PuppetPowerShell' -Repository PSGallery -Scope AllUsers -Force
    }
    catch
    {
        throw "Failed to install Puppet PowerShell module.`n$($_.Exception.Message)"
    }
}

# Install puppet-agent
Write-Host 'Installing puppet-agent' -ForegroundColor Magenta
$InstallArgs = @{
    Application = 'puppet-agent'
}
if ($ExactVersion)
{
    $InstallArgs.Add('ExactVersion', $ExactVersion)
}
else
{
    $InstallArgs.Add('MajorVersion', $MajorVersion)
}
try
{
    Install-Puppet @InstallArgs
}
catch
{
    throw "Failed to install puppet-agent.`n$($_.Exception.Message)"
}
# On Windows we need to set the alias to Puppet
if ($IsWindows)
{
    if ($env:Path -notcontains 'C:\Program Files\Puppet Labs\Puppet\bin' ) 
    {
        $env:Path += ';C:\Program Files\Puppet Labs\Puppet\bin'
        [Environment]::SetEnvironmentVariable('Path', $env:Path, 'Machine')
    }
}

if ($CSRExtensions)
{
    try
    {
        Set-CertificateExtensions -ExtensionAttributes $CSRExtensions
    }
    catch
    {
        throw "Failed to set certificate extensions.`n$($_.Exception.Message)"
    }
}

$PuppetMainConfigOptions = @{server = $PuppetServer; masterport = $PuppetServerPort }
$PuppetAgentConfigOptions = @{}
if ($PuppetEnvironment)
{
    $PuppetAgentConfigOptions.Add('environment', $PuppetEnvironment)
}


if ($NewHostname -ne $CurrentNodeName)
{
    Write-Host "Setting hostname to $NewHostname" -ForegroundColor Magenta
    if (!$IsWindows)
    {
        & hostname $NewHostname
        if ($LASTEXITCODE -ne 0)
        {
            throw "Failed to set hostname to $($NewHostname)"
        }
        try
        {
            Set-Content -Path '/etc/hostname' -Value $NewHostname -Force
        }
        catch
        {
            throw "Failed to set hostname to $($NewHostname)`n$($_.Exception.Message)"
        }    
    }
    else
    {
        # Not sure how to handle fqdn's on Windows 🤷 
        # it'll largely be taken care of by DNS/DHCP, so just change the hostname
        try
        {
            Rename-Computer -NewName $NewHostname -Force -Confirm:$false
        }
        catch
        {
            throw "Failed to set hostname to $($NewHostname).`n$($_.Exception.Message)"
        }
        # Windows name changes don't take hold until after a reboot
        Write-Warning 'Hostname change will take effect after a reboot'
        # So set the Puppet certname to match the hostname that will be used going forward
        $CertificateName = "$($NewHostname).$($DomainName)".ToLower()
    }
}

if ($CertificateName)
{
    $PuppetMainConfigOptions.Add('certname', $CertificateName)
}

if ($PuppetMainConfigOptions)
{
    Write-Host 'Setting Puppet [main] configuration options' -ForegroundColor Magenta
    try
    {
        Set-PuppetConfigOption -ConfigOptions $PuppetMainConfigOptions -Section 'main'
    }
    catch
    {
        throw "Failed to set Puppet agent environment.`n$($_.Exception.Message)"
    }
}
if ($PuppetAgentConfigOptions)
{
    Write-Host 'Setting Puppet [agent] configuration options' -ForegroundColor Magenta
    try
    {
        Set-PuppetConfigOption -ConfigOptions $PuppetAgentConfigOptions -Section 'agent'
    }
    catch
    {
        throw "Failed to set Puppet agent configuration.`n$($_.Exception.Message)"
    }
}
###

# Wait for a few seconds, I've found that sometimes Puppet isn't quite ready to go
Start-Sleep -Seconds 10

if (!$SkipInitialRun)
{
    # Perform first run of Puppet
    Write-Host 'Performing initial Puppet run' -ForegroundColor Magenta
    $PuppetArgs = @('agent', '-t', '--detailed-exitcodes')
    if ($WaitForCert)
    {
        $PuppetArgs += @('--waitforcert', $WaitForCert)
    }
    if ($IsWindows)
    {
        & puppet $PuppetArgs
    }
    else
    {
        & /opt/puppetlabs/bin/puppet $PuppetArgs
    }
    if ($LASTEXITCODE -notin (0, 2))
    {
        # Only warn as we want to continue if the run fails
        Write-Warning "First Puppet run failed with exit code $LASTEXITCODE"
    }
}

if ($EnableService)
{
    Write-Host 'Enabling Puppet Service' -ForegroundColor Magenta
    try
    {
        Enable-PuppetService
    }
    catch
    {
        throw "Failed to enable Puppet service.`n$($_.Exception.Message)"
    }
}
Write-Host 'Puppet bootstrapping complete 🎉' -ForegroundColor Green