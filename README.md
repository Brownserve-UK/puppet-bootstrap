# puppet-bootstrap

This repo contains the scripts required to bootstrap a Puppet installation.
These scripts are likely only relevant to Brownserve projects.

## puppet-agent.ps1

This sets up Puppet agent on Linux/Windows nodes.

| Parameter Name          | Type    | Mandatory | Description                                                                                                                                                        |
|-------------------------|---------|-----------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `MajorVersion`          | int     | false     | The major version of Puppet agent to install (e.g '6')                                                                                                             |
| `ExactVersion`          | version | false     | The exact version of Puppet agent to be installed (e.g. '6.25.1')                                                                                                  |
| `PuppetServer`          | string  | true      | The name of the Puppet server that will manage this node                                                                                                           |
| `PuppetServerPort`      | int     | false     | The port that the Puppet server communicates on (defaults to 8140)                                                                                                 |
| `PuppetEnvironment`     | string  | false     | The environment to use for this node (e.g 'production','dev')                                                                                                      |
| `CertificateName`       | string  | false     | Allows the node to use a different certname other than the standard FQDN                                                                                           |
| `CSRExtensions`         | hash    | false     | Allows for setting additional certificate signing request parameters                                                                                               |
| `EnableService`         | boolean | false     | Enables the Puppet agent service (defaults to `$true`)                                                                                                             |
| `WaitForCert`           | int     | false     | If set the Puppet agent will wait this amount of seconds for the certificate to be signed before continuing. Defaults to 30                                        |
| `NewHostname`           | string  | false     | Allows for setting a new hostname, useful if the node is a fresh install and is yet unnamed.                                                                       |
| `DomainName`            | string  | true      | The domain name you are using (e.g `foo-bar.com`,`example.co.uk`)                                                                                                  |
| `SkipPuppetserverCheck` | switch  | false     | If declared this will skip checking communication with the Puppet server                                                                                           |
| `SkipOptionalPrompts`   | switch  | false     | If declared this will disable any prompts for additional information and configure the node with the information that has been provided in the scripts parameters. |
| `SkipConfirmation`      | switch  | false     | If declared this will skip the confirmation prompt.                                                                                                                |
| `SkipInitialRun`      | switch  | false     | If declared this will skip the first run of Puppet.                                                                                                                |

## puppet-server.ps1

Bootstraps the installation and configuration of a new Puppetserver.

| Parameter Name         | Type   | Mandatory | Description                                                                                                                                    |
|------------------------|--------|-----------|------------------------------------------------------------------------------------------------------------------------------------------------|
| `MajorVersion`         | int    | true      | The major version of Puppetserver to be installed, this should match the agent version you plan to run.                                        |
| `DomainName`           | string | true      | The name of your domain (e.g. `example.com`, `foo-bar.co.uk`)                                                                                  |
| `PuppetserverClass`    | string | false     | The name of the class in your manifest that configures a Puppet server                                                                         |
| `Hostname`             | string | false     | Allows you to rename the node before configuring it, useful one a fresh install.                                                               |
| `CSRExtensions`        | hash   | false     | Any CSR extensions that you wish to set.                                                                                                       |
| `GitHubRepo`           | string | false     | The URL/SSH address of any GitHub repos you wish to use with r10k                                                                              |
| `DeployKeyPath`        | string | false     | If your repository is private this should be the path to a deploy key that will be used to access it, if one doesn't exist it will be created. |
| `BootstrapEnvironment` | string | false     | Allows you to set an environment for bootstrapping the Puppet server                                                                           |
| `BootstrapHiera`       | string | false     | If you use a separate hiera file for bootstrapping then you can specify that here                                                              |
| `eyamlPrivateKey`      | string | false     | Allows you to pass in your private eyaml key (if using eyaml)                                                                                  |
| `eyamlPublicKey`       | string | false     | Allows you to pass in your public eyaml key (if using eyaml)                                                                                   |
| `eyamlKeyPath`         | string | false     | Allows you to specify the path to where you will store your eyaml public/private keys.                                                         |
| `SkipOptionalPrompts`  | switch | false     | If declared will skip all information gathering prompts.                                                                                       |
| `SkipConfirmation`     | switch | false     | If declared will skip the confirmation prompt.                                                                                                 |
