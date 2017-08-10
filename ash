# OSP10 Installation Guide

## Pre-requisites

### Install RHEL 7.3
1. Download the official image from https://access.redhat.com/downloads/content/69/ver=/rhel---7/7.3/x86_64/product-software
2. Create a bootable USB. Follow instructions in https://access.redhat.com/documentation/en-US/Red_Hat_Enterprise_Linux/7/html/Installation_Guide/sect-making-usb-media.html
3. Connect the drive to the target server (Director node)
4. Boot from the USB drive and follow the UI instructions.
5. Select  **Installation Destination**. Select **Manual Partitioning**. Then select **Automatic LVM partitioning**. Modify the size of the `/home` and `/` root directory. Allow at least 100GB for the root directory.
6. Configure the **Network & Hostname`** Configure *only* the public interface. Leave unconfigured the provisioning interface. Select a qualified *hostname* for the machine (i.e. `homadirector`).
7. Consult the following guide for additional information. https://access.redhat.com/documentation/en-US/Red_Hat_Enterprise_Linux/7/html/Installation_Guide/chap-simple-install.html#sect-simple-install
8. Start the installation.
9. Select a password for the root account.
10. Select a user name for the administrator account (i.e. `homa-admin`). Check the box to make this account the administrator. Select a password for the account.
11. Wait for installation to finish. Reboot the machine when indicated by the installation UI.

This complete the installation of the basic operating system for the Director node.

### Important information.
1. Commands with the symbol `$` should be executed as non root user. In general this is the `stack` account.
2. Commands with the symbol `#` should be executed as  `root` user.

## Installing the Undercloud (OSP Director)
1. Connect to the Director machine.
  ```
  $ ssh homa-admin@<director-ipaddr>
  ```
2. Create the `stack` account.
  ```
  $ su root
  # useradd stack
  # echo H0MA_clu5t3r! | passwd stack --stdin
  # echo "stack ALL=(root) NOPASSWD:ALL" | tee -a /etc/sudoers.d/stack
  # chmod 0440 /etc/sudoers.d/stack
  # su stack
  ```

3. (Optional - Only for the Administrator) Add your sshkeys to the stack account.

  From your local machine:
  ```
  $ ssh-copy-id -i ~/.ssh/id_rsa.pub stack@<director-ipaddr>
  ```
4. Configure the Director machine.
  ```
  $ ssh stack@<director-ipaddr>
  $ mkdir ~/images
  $ mkdir ~/templates
  ```
  Configure the machine's hostname:
  ```
  $ sudo vi /etc/hosts
  >>>
  127.0.0.1 homadirector.telus.com homadirector locahost
  ::1

  $ sudo vi /etc/hostname
  >>>
  homadirector
  ```
  Check the changes on the hostname
  ```
  $ hostname
  $ hostname -f
  ```
5. Register the system

  You will need a valid RedHat user name and password.
  ```
  $ sudo subscription-manager register
  ```
  Check available subscriptions for the user.
  ```
  $ sudo subscription-manager list --available --all
  ```
  Attach a subscription to the system
  ```
  $ sudo subscription-manager attach --pool=<pool_id>
  ```
6. Configure repositories

  Disable all repositories
  ```
  $ sudo subscription-manager repos --disable=*
  ```
  Enable OSP10 repositories
  ```
  $ sudo subscription-manager repos \
      --enable=rhel-7-server-rpms \
      --enable=rhel-7-server-extras-rpms \
      --enable=rhel-7-server-rh-common-rpms \
      --enable=rhel-ha-for-rhel-7-server-rpms \
      --enable=rhel-7-server-openstack-10-rpms \
      --enable=rhel-7-server-openstack-10-devtools-rpms
  ```
  Update the system
  ```
  $ sudo yum update -y
  ```
  Reboot the machine
  ```
  $ sudo reboot now
  ```

7. Install Director packages
  ```
  $ sudo yum install -y python-tripleoclient
  ```
8. Configuring the Director

  Copy the basic template
  ```
  $ cp /usr/share/instack-undercloud/undercloud.conf.sample ~/undercloud.conf
  ```
  At the following minimum parameters right after the `[DEFAULT]` section:
  ```
  local_ip = 172.19.196.98/27
  network_gateway = 172.19.196.97
  undercloud_public_vip = 172.19.196.99
  undercloud_admin_vip = 172.19.196.100
  local_interface = enp6s0
  masquerade_network = 172.19.196.96/27
  dhcp_start = 172.19.196.101
  dhcp_end = 172.19.196.116
  generate_service_certificate = true
  certificate_generation_ca = local
  network_cidr = 172.19.196.96/27
  inspection_iprange = 172.19.196.117,172.19.196.125
  ipxe_enabled = true
  enable_ui = true
  ```

9. Install the Undercloud
  ```
  $ openstack undercloud install
  ```
  After finishing, check that all OpenStack Platform services runs correctly
  ```
  $ sudo systemctl list-units openstack-*
  ```
10. Set environment varibles
  ```
  $ source stackrc
  ```

## Installing the Overcloud

1. Obtain the images for the overcloud
  ```
  $ sudo yum install rhosp-director-images rhosp-director-images-ipa
  ```
  Extract the images
  ```
  $ cd ~/images
  $ for i in /usr/share/rhosp-director-images/overcloud-full-latest-10.0.tar /usr/share/rhosp-director-images/ironic-python-agent-latest-10.0.tar; do tar -xvf $i; done
  ```
  Import these images into the director:
  ```  
  $ openstack overcloud image upload --image-path /home/stack/images/
  ```
  View a list of the available images:
  ```
  $ openstack image list
  ```
2. Set the DNS for the undercloud network
  ```
  $ neutron subnet-list
  $ neutron subnet-update <subnet_UUID> --dns-nameservers list=true 209.20.8.249 205.206.214.249
  ```
3. Enable the IPMI driver

  Enable the `fake_pxe` driver
  ```
  $ sudo vi /etc/ironic/ironic.conf
  ```
  Search for the line `enabled_drivers` and edit as follows:
  ```
  enabled_drivers = pxe_ipmitool,pxe_ssh,pxe_drac,pxe_ilo,fake_pxe
  ```
  Restart the Ironic services. Check that all services are `enabled`
  ```
  $ ironic_services=$(sudo systemctl list-unit-files | grep ironic | awk '/enabled/ {print $1}')
  $ sudo systemctl restart $ironic_services
  $ sudo systemctl list-unit-files | grep ironic
  ```
  Validate the driver is active
  ```
  $ openstack baremetal driver list
  ```

4. Registering the nodes for the overcloud

  Create the instackenv.json file
  ```
  $ cd ~
  $ vi instackenv,json
  ```
  Edit is content with the details of each server:
  ```
  {
    "nodes": [
      {
        "name": "Svr-04",
        "pm_user": "admin",
        "pm_password": "H0MA_clu5t3r!",
        "pm_type": "fake_pxe",
        "pm_addr": "172.18.232.231",
        "mac": [
  	  "00:25:b5:00:00:7f"
        ]
      },
      {
        "name": "Svr-05",
        "pm_user": "admin",
        "pm_password": "H0MA_clu5t3r!",
        "pm_type": "fake_pxe",
        "pm_addr": "172.18.232.234",
        "mac": [
  	  "00:25:b5:00:01:df"
        ]
      },
      {
        "name": "Svr-07",
        "pm_user": "admin",
        "pm_password": "H0MA_clu5t3r!",
        "pm_type": "fake_pxe",
        "pm_addr": "172.18.232.253",
        "mac": [
    	"00:25:b5:00:01:ef"
        ]
      },
      {
        "name": "Svr-08",
        "pm_user": "admin",
        "pm_password": "H0MA_clu5t3r!",
        "pm_type": "fake_pxe",
        "pm_addr": "172.18.232.236",
         "mac": [
  	"00:25:b5:00:00:2f"
        ]
      }
    ]
  }
  ```
  Register the nodes
  ```
  $ openstack baremetal import --initial-state=enroll instackenv.json
  ```
  View a list of the registered nodes:
  ```
  $ openstack baremetal node list
  ```

5. Perform instrospection

  Verify that the nodes are in `managed` state:
  ```
  $ openstack baremetal node list
  ```
  If not,
  ```
  $ openstack baremetal node manage [NODE UUID]
  ```
  You can run instrospection in all nodes at the same time:
  ```
  $ openstack baremetal introspection bulk start
  ```
  The following command is equivalent
  ```
  $ openstack overcloud node introspect --all-manageable --provide
  ```
  Or, perform a single introspection on each node individually
  ```
  $ openstack baremetal node manage [NODE UUID]
  $ openstack overcloud node introspect [NODE UUID] --provide
  ```
  Monitor the progress of the instrospection in a separate window:
  ```
  $ sudo journalctl -l -u openstack-ironic-inspector -u openstack-ironic-inspector-dnsmasq -u openstack-ironic-conductor -f
  ```

  **IMPORTANT**: When using the `fake_pxe` driver, you must manually turn on and of the servers. For instrospection the procedure is as follows:
  Monitor the status of the machines in a separate window:
  ```
  $ source ~/stackrc
  $ watch -n5 "openstack baremetal node list"
  ```
  - When the introspection process starts, you’ll see the **Power State** switch to `power on`.
  - At this point, *power on* manually the machines
  - When introspection completes, you’ll see the **Provisioning State** switch to `available` and the **Power State** should show `power off`. You’ll need to manually *power down* the machines at this point.

6. Tagging nodes into profiles

  Tag compute nodes:
  ```
  $ openstack baremetal node set --property capabilities='profile:compute,boot_option:local' [NODE UUID]
  ```
  Tag controller nodes:
  ```
  $ openstack baremetal node set --property capabilities='profile:control,boot_option:local' [NODE UUID]
  ```
  Tag block storage nodes:
  ```
  $ openstack baremetal node set --property capabilities='profile:block-storage,boot_option:local' [NODE UUID]
  ```
  After completing node tagging, check the assigned profiles or possible profiles:
  ```
  $ openstack overcloud profiles list
  ```

7. Defining the root disk for nodes

  Download swift data about the nodes
  ```
  $ mkdir ~/swift-data
  $ cd ~/swift-data
  $ export SWIFT_PASSWORD=`sudo crudini --get /etc/ironic-inspector/inspector.conf swift password`
  $ for node in $(ironic node-list | grep -v UUID| awk '{print $2}'); do swift -U service:ironic -K $SWIFT_PASSWORD download ironic-inspector inspector_data-$node; done
  ```
  Check the information for each node
  ```
  $ for node in $(ironic node-list | awk '!/UUID/ {print $2}'); do echo "NODE: $node" ; cat inspector_data-$node | jq '.inventory.disks' ; echo "-----" ; done
  ```
  Use the value for the `serial` key and set the `root_device` for each node:
  ```
  $ openstack baremetal node set --property root_device='{"serial": "[DISK SERIAL]"}' [NODE UUID]
  ```
8. Deploy the Overcloud

  ```
  $ openstack overcloud deploy --templates --control-scale 1 --compute-scale 3 --neutron-network-type vxlan --neutron-tunnel-types vxlan --neutron-public-interface enp5s0
  ```
  **IMPORTANT**: When using the `fake_pxe` driver, you must manually turn on and of the servers. For overcloud deployment the procedure is as follows:
  Monitor the status of the machines in a separate window:
  ```
  $ source ~/stackrc
  $ watch -n5 "openstack baremetal node list"
  ```
  - When you see **Power State** switch to `power on` and and **Provisioning State** `wait for call-back` then *power on* the machines.
  - Machines will boot via PXE, pull image from undercloud, write to disk..
  - Machines will power down automatically.
  - Continue monitoring the nodes for the **Provisioning State** to switch to `active`.
  - After the state changes to `active` power the machines back on manually.

9. Wait for the Overcloud to finish the installation.

  After the installation finish, the `overcloudrc` file is generated. The file contains the overcloud endpoint, passwords, and additional environment variables necessaries for running commands in the overcloud from the director machine. This file must be secured.


## Overcloud Procedures:

The following is a set of useful commands to perform regular operations in the Overcloud using CLI.
