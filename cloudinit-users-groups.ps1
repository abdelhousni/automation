# source : https://cloudinit.readthedocs.io/en/latest/topics/examples.html
# source : 
# https://github.com/MicrosoftDocs/Virtualization-Documentation/blob/master/hyperv-samples/benarm-powershell/Ubuntu-VM-Build/BaseUbuntuBuild.ps1   
# via https://omiossec.github.io/blog/running-linux-on-hyper-v.html

$tempPath = [System.IO.Path]::GetTempPath() + [System.Guid]::NewGuid().ToString()

# ADK Download - https://www.microsoft.com/en-us/download/confirmation.aspx?id=39982
# You only need to install the deployment tools
$oscdimgPath = "L:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe"

# Download qemu-img from here: http://www.cloudbase.it/qemu-img-windows/
$qemuImgPath = "C:\ProgramData\chocolatey\bin\qemu-img.exe"

# Update this to the release of Ubuntu that you want
#$ubuntuPath = "http://cloud-images.ubuntu.com/trusty/current/trusty-server-cloudimg-amd64"
$ubuntuPath = "http://cloud-images.ubuntu.com/focal/current/focal-server-cloudimg-amd64"

$GuestOSName = "Hyper-V-VM"
$GuestOSID = "iid-123456"
$GuestAdminPassword = "P@ssw0rd"

$VMName = "Ubuntu Test"
#$virtualSwitchName = "Virtual Switch"
$virtualSwitchName = "Default Switch"

$vmPath = "C:\Working Space\VM"
$imageCachePath = "C:\Working Space"
$vhdx = "$($vmPath)\test.vhdx"
$metaDataIso = "$($vmPath)\metadata.iso"

# Get the timestamp of the latest build on the Ubuntu cloud-images site
$stamp = (Invoke-WebRequest "$($ubuntuPath).manifest").BaseResponse.LastModified.ToFileTimeUtc()
$metadata = @"
#cloudinit
instance-id: $($GuestOSID)
local-hostname: $($GuestOSName)
"@
$userdata = @"
#cloud-config
hostname: ubuntubionic
fqdn: ubuntubionic.local.lab
write_files:
  - path: /etc/netplan/50-cloud-init.yaml
  content: |
  network:
    version: 2
    ethernets:
      ens192:
        addresses: [192.168.10.79/24]
        gateway4: 192.168.10.1
        dhcp6: false
        nameservers:
          addresses:
            - 192.168.10.2
            - 192.168.10.3
            search:
              - local.lab
              dhcp4: false
              optional: true
              - path: /etc/sysctl.d/60-disable-ipv6.conf
              owner: root
              content: |
              net.ipv6.conf.all.disable_ipv6=1
              net.ipv6.conf.default.disable_ipv6=1
              runcmd:
                - netplan --debug apply
                - sysctl -w net.ipv6.conf.all.disable_ipv6=1
                - sysctl -w net.ipv6.conf.default.disable_ipv6=1
                - apt-get -y update
                - add-apt-repository universe
                - apt-get -y clean
                - apt-get -y autoremove --purge
                timezone: Europe/Brussels
                system_info:
                  default_user:
                    name: default-user
                    lock_passwd: false
                    sudo: ["ALL=(ALL) NOPASSWD:ALL"]
                    disable_root: false
                    ssh_pwauth: yes
                    users:
                      - default
                      - name: luc
                      gecos: LucD
                      lock_passwd: false
                      groups: sudo, users, admin
                      shell: /bin/bash
                      sudo: ['ALL=(ALL) NOPASSWD:ALL']
                      chpasswd:
                        list: |
                        default-user:`$6`$ogILNfS91`$8P1BTAcytZb14zXkrAVM3xmVdIjiNynx2zkNXdBd.sUs7G6q4jc6FPeUFDOHAZDAe82gwUct.nrBpi/v06Tm10
                        luc:`$6`$ogILNfS91`$8P1BTAcytZb14zXkrAVM3xmVdIjiNynx2zkNXdBd.sUs7G6q4jc6FPeUFDOHAZDAe82gwUct.nrBpi/v06Tm10
                        root:`$6`$ogILNfS91`$8P1BTAcytZb14zXkrAVM3xmVdIjiNynx2zkNXdBd.sUs7G6q4jc6FPeUFDOHAZDAe82gwUct.nrBpi/v06Tm10
                        expire: false
                        package_upgrade: true
                        package_reboot_if_required: true
                        power_state:
                          delay: now
                          mode: reboot
                          message: Rebooting the OS
                          condition: if [ -e /var/run/reboot-required ]; then exit 0; else exit 1; fi
"@

# Check Pathszzz
if (!(test-path $vmPath)) {mkdir $vmPath}
if (!(test-path $imageCachePath)) {mkdir $imageCachePath}

# Helper function for no error file cleanup
Function cleanupFile ([string]$file) {if (test-path $file) {Remove-Item $file}}

# Delete the VM if it is around
If ((Get-VM | ? name -eq $VMName).Count -gt 0)
      {stop-vm $VMName -TurnOff -Confirm:$false -Passthru | Remove-VM -Force}

cleanupFile $vhdx
cleanupFile $metaDataIso

# Make temp location
md -Path $tempPath
md -Path "$($tempPath)\Bits"
if (!(test-path "$($imageCachePath)\ubuntu-$($stamp).img")) {
      # If we do not have a matching image - delete the old ones and download the new one
      Remove-Item "$($imageCachePath)\ubuntu-*.img"
      Invoke-WebRequest "$($ubuntuPath).img" -UseBasicParsing -OutFile "$($imageCachePath)\ubuntu-$($stamp).img"
}

# Output meta and user data to files
sc "$($tempPath)\Bits\meta-data" ([byte[]][char[]] "$metadata") -Encoding Byte
sc "$($tempPath)\Bits\user-data" ([byte[]][char[]] "$userdata") -Encoding Byte


# Convert cloud image to VHDX
& $qemuImgPath convert -f qcow2 "$($imageCachePath)\ubuntu-$($stamp).img" -O vhdx -o subformat=dynamic $vhdx
Resize-VHD -Path $vhdx -SizeBytes 50GB

# Create meta data ISO image
& $oscdimgPath "$($tempPath)\Bits" $metaDataIso -j2 -lcidata

# Clean up temp directory
rd -Path $tempPath -Recurse -Force

# Create new virtual machine and start it
new-vm $VMName -MemoryStartupBytes 2048mb -VHDPath $vhdx -Generation 2 `
               -SwitchName $virtualSwitchName -Path $vmPath | Out-Null
Set-VM -Name $VMName -ProcessorCount 2
Set-VMDvdDrive -VMName $VMName -Path $metaDataIso
Set-VMFirmware -VMName $VMName -SecureBootTemplate MicrosoftUEFICertificateAuthority

Start-VM $VMName

# Open up VMConnect
Invoke-Expression "vmconnect.exe localhost `"$VMName`""

