# -*- mode: ruby -*-
# vi: set ft=ruby :
Vagrant.configure("2") do |config|
    config.vm.box = "bento/ubuntu-20.04"
    config.vm.provider "virtualbox" do |vb|
      vb.memory = "2048"
      vb.cpus = 2
    end
    # IMPORTANT: we must update and install ca-certifcates due to the letsencrypt SSL certificate expiring.
    config.vm.provision "install", type: "shell", inline: <<-SHELL
        sudo apt-get update
        apt-get install -y git procps lsb-release avahi-daemon libnss-mdns wget apt-transport-https software-properties-common ca-certificates
        wget -q https://packages.microsoft.com/config/ubuntu/20.04/packages-microsoft-prod.deb
        dpkg -i packages-microsoft-prod.deb
        apt-get update
        add-apt-repository universe
        apt-get install -y powershell
    SHELL
    config.vm.provision "hosts", type: "shell", inline: <<-SHELL
      sudo bash -c 'echo "192.168.60.2 puppetserver.local" >> /etc/hosts'
    SHELL
    config.vm.define "puppetagent-linux" do |pl|
      pl.vm.hostname = "puppetagent-linux"
      pl.vm.network "private_network", ip: "192.168.60.3"
    end
    config.vm.define "puppetagent-windows" do |pw|
      pw.vm.box = "gusztavvargadr/windows-server"
      pw.winrm.retry_limit = 5
      pw.winrm.retry_delay = 20
      pw.vm.box_version = "1809.0.2006.standard"
      pw.vm.hostname = "puppetagent-win"
      pw.vm.network "private_network", ip: "192.168.60.4"
      # We need to upgrade chocolatey to ensure that we don't run into the version number bug.
      pw.vm.provision "install", type: "shell", reboot: true, inline: <<-SHELL
        choco upgrade chocolatey -y
        choco install powershell-core -y
      SHELL
      pw.vm.provision "hosts", type: "shell", inline: "Add-Content -Path 'c:\\Windows\\System32\\Drivers\\etc\\hosts' -Value '192.168.60.2    puppetserver.local'"
    end
    config.vm.define "puppetserver" do |ps|
      ps.vm.hostname = "puppetserver"
      ps.vm.network "forwarded_port", guest: 80, host: 8000 # To test puppetboard.
      ps.vm.network "forwarded_port", guest: 8080, host: 8081 # So other nodes can query puppetDB
      ps.vm.network "private_network", ip: "192.168.60.2"
      ps.vm.provider "virtualbox" do |vb|
        vb.memory = "4096" # extra memories for a Puppetserver
      end
    end
end