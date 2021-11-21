<#
.SYNOPSIS
    Bootstraps the installation of Puppetserver
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
param
(
    # The major version of Puppetserver to install
    [Parameter(Mandatory = $true)]
    [int]
    $MajorVersion,

    # The domain name you use in your environment, mandatory as Puppet requires a FQDN to work
    [Parameter(Mandatory = $true)]
    [string]
    $DomainName,

    # The name of the Puppetserver class to use
    [Parameter(Mandatory = $false)]
    [string]
    $PuppetserverClass,

    # The Hostname to set for this Puppet Server
    [Parameter(Mandatory = $false)]
    [string]
    $Hostname,

    # Optional CSR attributes to set
    [Parameter(Mandatory = $false)]
    [hashtable]
    $CSRExtensions = @{pp_environment = 'live'; pp_service = 'puppetserver'; 'pp_role' = 'puppet6_server' },

    # Set this if you plan to use r10k to deploy your Puppet code
    [Parameter(Mandatory = $false)]
    [switch]
    $GenerateR10kConfiguration,

    # The repository where your Puppet configurations are stored (if using r10k), this should be the ssh URL
    [Parameter(Mandatory = $false)]
    [string]
    $GitHubRepo,

    # The bootstrap environment to use for the Puppet code (if using r10k), this should be the branch name
    [Parameter(Mandatory = $false)]
    [string]
    $BootstrapEnvironment,

    # An optional bootstrap hiera data file to use
    [Parameter(Mandatory = $false)]
    [string]
    $BootstrapHiera,

    # Optional eyaml private key
    [Parameter(Mandatory = $false)]
    [string]
    $eyamlPrivateKey,

    # Optional eyaml public key
    [Parameter(Mandatory = $false)]
    [string]
    $eyamlPublicKey,

    # If set will skip all optional prompts that have not been provided
    [Parameter(Mandatory = $false)]
    [switch]
    $SkipOptionalPrompts
)
#Requires -Version 6

### Parameter validation ###
if ($eyamlPrivateKey -and !($eyamlPublicKey))
{
    throw 'You must specify both a private and public key for eyaml'
}
if (!($eyamlPrivateKey) -and $eyamlPublicKey)
{
    throw 'You must specify both a private and public key for eyaml'
}

# Copy these functions from Brownserve.PSTools as they are super helpful
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

if (!$IsLinux)
{
    throw 'Cannot install Puppetserver on non-linux systems.'
}

if (!(Test-Administrator))
{
    throw 'This script must be run as administrator.'
}

if (!$DomainName)
{
    $DomainName = Get-Response 'Enter your domain name (e.g foo-bar.com)' 'string' -Mandatory
}

if (!$Hostname)
{
    $Hostname = & hostname
    if (!$SkipOptionalPrompts)
    {
        Write-Host "Current hostname is $Hostname"
        $HostnameCheck = Get-Response 'Do you want to change the hostname?' 'bool'
        if ($HostnameCheck)
        {
            $Hostname = Get-Response 'Enter the new hostname' 'string' -Mandatory
        }
    }
}

if ($Hostname -notmatch "$DomainName")
{
    $Hostname += ".$DomainName"
}

if (!$eyamlPrivateKey -or !$eyamlPublicKey -and !$SkipOptionalPrompts)
{
    $eyamlCheck = Get-Response 'Do you have an eyaml key pair?' 'bool'
    if ($eyamlCheck)
    {
        $eyamlPrivateKey = Get-Response 'Please enter your eyaml private key' 'string' -Mandatory
        $eyamlPublicKey = Get-Response 'Please enter your eyaml public key' 'string' -Mandatory
    }
}

if ((!$GenerateR10kConfiguration) -or (!$GitHubRepo) -and !$SkipOptionalPrompts)
{
    $r10kCheck = Get-Response 'Do you plan to use r10k?' 'bool'
    if ($r10kCheck)
    {
        $GenerateR10kConfiguration = $true
        while ($GitHubRepo -notmatch 'git@github.com:(.*)\/(.*).git')
        {
            $GitHubRepo = Get-Response 'Please enter your GitHub repository' 'string' -Mandatory
        }
    }
}

if ($GitHubRepo)
{
    if (!$DeployKeyPath)
    {
        # Check if this is a private repo
        $PrivateRepoCheck = Get-Response 'Is this a private repository?' 'bool'
        if ($PrivateRepoCheck)
        {
            # Try to be clever about key naming
            if ($GitHubRepo -match '\/(?<repo_name>.*).git')
            {
                $RepoName = $matches['repo_name']
            }
            else
            {
                $RepoName = 'control_repo'
            }
            $DeployKeyPath = "/etc/puppetlabs/puppetserver/ssh/id-$RepoName.rsa"
        }
    }

    if (!$BootstrapEnvironment)
    {
        $BootstrapEnvironment = Get-Response 'Please enter the bootstrap environment name (e.g bootstrap, production)' 'string' -Mandatory
    }
}

if (!$BootstrapHiera -and !$SkipOptionalPrompts)
{
    $BootstrapHieraCheck = Get-Response 'Do you want to set a bootstrap hiera data file?' 'bool'
    if ($BootstrapHieraCheck)
    {
        $BootstrapHiera = Get-Response 'Please enter the bootstrap hiera data file name (e.g puppet.bootstrap.yaml)' 'string' -Mandatory
    }
}

# We MUST have a PuppetserverClass if we've got a bootstrap hiera otherwise Puppet apply won't do anything 😂
if ($BootstrapHiera)
{
    if (!$PuppetserverClass)
    {
        $PuppetserverClass = Get-Response 'Please enter the puppetserver class name (e.g puppetserver)' 'string' -Mandatory
    }
}

$ConfirmationMessage = @"
`nThe Puppet server will be configured with the following:

Hostname: $Hostname
Major Puppet version: $MajorVersion`n
"@

if ($eyamlPrivateKey)
{
    $ConfirmationMessage += "Install eyaml: true`n"
}
else
{
    $ConfirmationMessage += "Install eyaml: false`n"
}
if ($GitHubRepo)
{
    $ConfirmationMessage += @"
Install r10k: true
GitHub repository: $GitHubRepo`n
"@
    if ($DeployKeyPath)
    {
        $ConfirmationMessage += "Deploy key: $DeployKeyPath`n"
    }
    if ($BootstrapEnvironment)
    {
        $ConfirmationMessage += "Bootstrap environment: $BootstrapEnvironment`n"
    }
    if ($BootstrapHiera)
    {
        $ConfirmationMessage += "Bootstrap hiera data file: $BootstrapHiera`n"
    }
}
else
{
    $ConfirmationMessage += "Install r10k: false`n"
}
if ($PuppetserverClass)
{
    $ConfirmationMessage += "Puppetserver class: $PuppetserverClass`n"
}
$ConfirmationMessage += "`nIs this correct?"
$ConfirmCheck = Get-Response $ConfirmationMessage 'bool'
if (!$ConfirmCheck)
{
    # We could potentially wrap the whole in a while loop until we are happy
    throw 'Bootstrap aborted'
}

### Begin bootstrap ###
Write-Host 'Beginning bootstrap process'

# Check for the presence of the PuppetPowerShell module and install it if it's not present
try
{
    $PuppetPowerShellCheck = Get-InstalledModule 'PuppetPowerShell'
}
catch {}

if (!$PuppetPowerShellCheck)
{
    Write-Host 'Installing Puppet PowerShell module'
    try
    {
        Install-Module -Name 'PuppetPowerShell' -Repository PSGallery -Scope AllUsers -Force
    }
    catch
    {
        throw "Failed to install Puppet PowerShell module.`n$($_.Exception.Message)"
    }
}

# Install puppetserver
Write-Host 'Installing puppetserver'
try
{
    Install-Puppet -MajorVersion $MajorVersion -Application 'puppetserver'
}
catch
{
    throw "Failed to install Puppetserver.`n$($_.Exception.Message)"
}

# Install r10k if necessary
Write-Host 'Installing r10k'
& gem install r10k
if ($LASTEXITCODE -ne 0)
{
    throw 'Failed to install r10k'
}

# Set the hostname if we have one
if ($Hostname)
{
    Write-Host "Setting hostname to $Hostname"
    try
    {
        & hostname $Hostname
        if ($LASTEXITCODE -ne 0)
        {
            throw  'Failed to set hostname'
        }
        Set-Content -Path '/etc/hostname' -Value $Hostname
    }
    catch
    {
        throw "Failed to set hostname to $Hostname.`n$($_.Exception.Message)"
    }
}

# Sort out deployment keys if we have a private repo
if ($DeployKeyPath)
{
    # If the deploy key doesn't exist we'll need to generate one to be able to pull
    if (!(Test-Path $DeployKeyPath))
    {
        Write-Host 'A deploy key will now be generated for you to copy to your repository'
        # Create the directory structure
        $DeployKeyParent = Split-Path $DeployKeyPath
        if (!(Test-Path $DeployKeyParent))
        {
            try
            {
                New-Item -ItemType Directory -Force -Path $DeployKeyParent
            }
            catch
            {
                throw "Failed to create directory $DeployKeyParent.`n$($_.Exception.Message)"
            }
        }
        if ((Test-Path $DeployKeyPath))
        {
            Write-Host "A deploy key already exists at $DeployKeyPath, it will be removed"
            try
            {
                Remove-Item -Path $DeployKeyPath -Force
            }
            catch
            {
                throw "Failed to remove existing deploy key at $DeployKeyPath.`n$($_.Exception.Message)"
            }
        }
        # Generate the key
        $KeygenOutput = & ssh-keygen -b 2048 -t rsa -q -C "$Hostname" -N '' -f $DeployKeyPath
        if ($LASTEXITCODE -ne 0)
        {
            $KeygenOutput
            throw 'Failed to generate deploy key'
        }
        $KeyContent = Get-Content $DeployKeyPath -Raw
        Write-Host "Please copy the following deploy key to your repository:`n"
        Write-Host $KeyContent
        Write-Host 'Press any key to continue the bootstrap process'
        $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
    }

    # Make sure the key has sensible permissions (we run Puppetserver as root)
    Write-Host 'Setting ACLs on deploy key'
    & chown root:root (Join-Path $DeployKeyParent '*')
    if ($LASTEXITCODE -ne 0)
    {
        throw 'Failed to chown deploy key'
    }
    & chmod '0600' (Join-Path $DeployKeyParent '*')
    if ($LASTEXITCODE -ne 0)
    {
        throw 'Failed to set ACLs on deploy key'
    }
}

# Keyscan github.com, it makes things easier later on
Write-Host 'Adding github.com to known hosts'
$Keyscan = & ssh-keyscan github.com
try
{
    $KnownHostsFile = Get-Content '/root/.ssh/known_hosts' -Raw
}
catch {}
if ($KnownHostsFile)
{
    # Only add if it's not already there
    if ($KnownHostsFile -notmatch $Keyscan)
    {
        try
        {
            Add-Content -Path $KnownHostsFile -Value $Keyscan
        }
        catch
        {
            throw "Failed to add github.com key.`n$($_.Exception.Message)"
        }
    }
}
else
{
    try
    {
        New-Item -Path $KnownHostsFile -Value $Keyscan
    }
    catch
    {
        throw "Failed to create known_hosts file.`n$($_.Exception.Message)"
    }
}

if ($BootstrapEnvironment)
{
    Write-Host "Setting Puppet agent environment to $BootstrapEnvironment"
    try
    {
        Set-PuppetConfigOption -ConfigOptions @{environment = $BootstrapEnvironment }
    }
    catch
    {
        throw "Failed to set Puppet agent environment.`n$($_.Exception.Message)"
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

# Sort out our r10k config
if ($GenerateR10kConfiguration)
{
    $r10kConfigurationPath = '/etc/puppetlabs/r10k/r10k.yaml'
    $r10kConfigurationParent = Split-Path $r10kConfigurationPath
    if (!(Test-Path $r10kConfigurationParent))
    {
        Write-Host 'Creating r10k configuration directory'
        try
        {
            New-Item -ItemType Directory -Force -Path $r10kConfigurationParent
        }
        catch
        {
            throw "Failed to create directory $r10kConfigurationParent.`n$($_.Exception.Message)"
        }
    }
    $r10kConfiguration = @"
# The location to use for storing cached Git repos
:cachedir: '/var/cache/r10k'

# A list of git repositories to create
:sources:
    # This will clone the git repository and instantiate an environment per
    # branch in /etc/puppetlabs/code/environments
  :$($RepoName):
    remote: '$($GitHubRepo)'
    basedir: '/etc/puppetlabs/code/environments'`n
"@
    if ($DeployKeyPath)
    {
        $r10kConfiguration += @"
git:
  private_key: '$($DeployKeyPath)'
"@
    }
    try
    {
        New-Item -Path $r10kConfigurationPath -Value $r10kConfiguration -Force
    }
    catch
    {
        throw "Failed to create r10k configuration file.`n$($_.Exception.Message)"
    }

    Write-Host 'Performing first run of r10k, this may take a while...' -ForegroundColor Yellow
    & /usr/local/bin/r10k deploy environment --puppetfile
    if ($LASTEXITCODE -ne 0)
    {
        throw 'Failed to perform first run of r10k'
    }
    # Test that our environment exists
    if (!(Test-Path "/etc/puppetlabs/code/environments/$BootstrapEnvironment"))
    {
        throw "'$BootstrapEnvironment' does not exist, are you sure it's a valid branch?"
    }
}

# Perform a Puppet run
# If we're bootstrapping hiera then we'll need to a puppet apply to get up and running
if ($BootstrapHiera)
{
    Write-Host "Running puppet apply against $BootstrapHiera"
    $ApplyArguments = @('apply')
    if ($BootstrapEnvironment)
    {
        $BootstrapHieraPath = "/etc/puppetlabs/code/environments/$BootstrapEnvironment/$BootstrapHiera"
    }
    else
    {
        $BootstrapHieraPath = "/etc/puppetlabs/code/environments/production/$BootstrapHiera"
    }
    if (!(Test-Path $BootstrapHieraPath))
    {
        throw "Cannot find hiera file at '$BootstrapHieraPath'"
    }
    $ApplyArguments += @("--hiera_config=$BootstrapHieraPath")
    if ($BootstrapEnvironment)
    {
        $ModulePath = "/etc/puppetlabs/code/environments/$BootstrapEnvironment/modules:/etc/puppetlabs/code/environments/$BootstrapEnvironment/ext-modules"
        $ApplyArguments += ("--module_path=$ModulePath")
    }
    if ($PuppetserverClass)
    {
        $ApplyArguments += ('-e', "include $PuppetserverClass")
    }
    & /opt/puppetlabs/bin/puppet $ApplyArguments
    if ($LASTEXITCODE -ne 0)
    {
        throw 'Failed to run puppet apply'
    }
}
# If we're not bootstrapping hiera (or only bootstrapping the environment) we can just run a puppet agent -t
else
{
    Write-Host 'Running puppet agent -t'
    & /opt/puppetlabs/bin/puppet agent -t
    # Sign cert?
}


Write-Host 'Bootstrapping complete 🎉' -ForegroundColor Green
Write-Host "Don't forget to:"
Write-Host "  - Add a DHCP reservation or static IP for this machine.`n  - Test your eyaml encryption/decryption"
if ($BootstrapEnvironment)
{
    Write-Host '  - Merge your branch into production.'
}