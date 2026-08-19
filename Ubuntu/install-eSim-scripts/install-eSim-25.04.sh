#!/bin/bash 
#=============================================================================
#          FILE: install-eSim.sh
# 
#         USAGE: ./install-eSim.sh --install 
#                            OR
#                ./install-eSim.sh --uninstall
#                
#   DESCRIPTION: Installation script for eSim EDA Suite
#
#       OPTIONS: ---
#  REQUIREMENTS: ---
#          BUGS: ---
#         NOTES: ---
#       AUTHORS: Fahim Khan, Rahul Paknikar, Saurabh Bansode,
#                Sumanto Kar, Partha Singha Roy, Harsha Narayana P, 
#                Jayanth Tatineni, Anshul Verma
#  ORGANIZATION: eSim Team, FOSSEE, IIT Bombay
#       CREATED: Wednesday 15 July 2015 15:26
#      REVISION: Sunday 25 May 2025 17:40
#=============================================================================

# All variables goes here
config_dir="$HOME/.esim"
config_file="config.ini"
eSim_Home="$(pwd)"
installer_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ngspiceFlag=0

## All Functions goes here

error_exit()
{

    echo -e "\n\nError! Kindly resolve above error(s) and try again."
    echo -e "\nAborting Installation...\n"

}


function createConfigFile
{
    mkdir -p "$config_dir"
    : > "$config_dir/$config_file"

    echo "[eSim]" >> "$config_dir/$config_file"
    echo "eSim_HOME = $eSim_Home" >> "$config_dir/$config_file"
    echo "LICENSE = %(eSim_HOME)s/LICENSE" >> "$config_dir/$config_file"
    echo "KicadLib = %(eSim_HOME)s/library/kicadLibrary.tar.xz" >> "$config_dir/$config_file"
    echo "IMAGES = %(eSim_HOME)s/images" >> "$config_dir/$config_file"
    echo "VERSION = %(eSim_HOME)s/VERSION" >> "$config_dir/$config_file"
    echo "MODELICA_MAP_JSON = %(eSim_HOME)s/library/ngspicetoModelica/Mapping.json" >> "$config_dir/$config_file"
}


function installNghdl
{
    echo "Installing NGHDL..........................."

    # Always start from a fresh copy of the bundled NGHDL tree.
    rm -rf nghdl
    unzip -o nghdl.zip

    echo "Applying Ubuntu 25.04 NGHDL compatibility installer..."
    cp "$installer_script_dir/install-nghdl-25.04.sh" \
       "nghdl/install-nghdl-scripts/install-nghdl-25.04.sh"
    chmod +x "nghdl/install-nghdl-scripts/install-nghdl-25.04.sh"

    # Capture the NGHDL installer's status explicitly instead of letting the
    # parent ERR trap terminate before we can report it.
    trap "" ERR
    set +e
    (
        cd nghdl || exit 1
        bash install-nghdl-scripts/install-nghdl-25.04.sh --install
    )
    nghdl_status=$?
    set -e
    trap error_exit ERR

    if [ "$nghdl_status" -ne 0 ]; then
        echo "NGHDL installation failed with status $nghdl_status"
        return "$nghdl_status"
    fi

    ngspiceFlag=1
}


function installSky130Pdk
{
    echo "Installing SKY130 PDK......................"

    tar -xJf library/sky130_fd_pr.tar.xz

    sudo rm -rf /usr/share/local/sky130_fd_pr
    echo "Copying SKY130 PDK........................."

    sudo mkdir -p /usr/share/local/
    sudo mv sky130_fd_pr /usr/share/local/

    sudo chown -R "$USER:$USER" /usr/share/local/sky130_fd_pr/
}


function installKicad
{
    echo "Installing KiCad..........................."

    # Detect Ubuntu version
    ubuntu_version=$(lsb_release -rs)

    # Define KiCad PPAs based on Ubuntu version
    if [[ "$ubuntu_version" == "24.04" || "$ubuntu_version" == "25.04" ]]; then
        echo "Ubuntu $ubuntu_version detected."
        kicadppa="kicad/kicad-8.0-releases"

        # Check if KiCad is installed using dpkg-query for the main package
        if dpkg -s kicad &>/dev/null; then
            installed_version=$(dpkg-query -W -f='${Version}' kicad | cut -d'.' -f1)
            if [[ "$installed_version" != "8" ]]; then
                echo "A different version of KiCad ($installed_version) is installed."
                read -p "Do you want to remove it and install KiCad 8.0? (yes/no): " response

                if [[ "$response" =~ ^([Yy][Ee][Ss]|[Yy])$ ]]; then
                    echo "Removing KiCad $installed_version..."
                    sudo apt-get remove --purge -y kicad kicad-footprints kicad-libraries kicad-symbols kicad-templates
                    sudo apt-get autoremove -y
                else
                    echo "Exiting installation. KiCad $installed_version remains installed."
                    exit 1
                fi
            else
                echo "KiCad 8.0 is already installed."
                return 0
            fi
        fi

    else
        kicadppa="kicad/kicad-6.0-releases"
    fi

    # Check if the PPA is already added
    if ! grep -q "^deb .*${kicadppa}" /etc/apt/sources.list /etc/apt/sources.list.d/* 2>/dev/null; then
        echo "Adding KiCad PPA to local apt repository: $kicadppa"
        sudo add-apt-repository -y "ppa:$kicadppa"
        sudo apt-get update
    else
        echo "KiCad PPA is already present in sources."
    fi

    # Install KiCad packages
    sudo apt-get install -y --no-install-recommends kicad=8.0.8+dfsg-1 kicad-footprints kicad-libraries kicad-symbols kicad-templates

    echo "KiCad installation completed successfully!"
}


function installDependency
{

    set +e      # Temporary disable exit on error
    trap "" ERR # Do not trap on error of any command

    # Update apt repository
    echo "Updating apt index files..................."
    sudo apt-get update
    
    set -e      # Re-enable exit on error
    trap error_exit ERR
    
    echo "Instaling virtualenv......................."
    sudo apt install python3-virtualenv
   
    echo "Creating virtual environment to isolate packages "
    virtualenv $config_dir/env
    
    echo "Starting the virtual env..................."
    source $config_dir/env/bin/activate

    echo "Upgrading Pip.............................."
    pip install --upgrade pip
    
    echo "Installing Xterm..........................."
    sudo apt-get install -y xterm
    
    echo "Installing Psutil.........................."
    sudo apt-get install -y python3-psutil
    
    echo "Installing PyQt5..........................."
    sudo apt-get install -y python3-pyqt5

    echo "Installing Matplotlib......................"
    sudo apt-get install -y python3-matplotlib

    echo "Installing Setuptools..................."
    sudo apt-get install -y python3-setuptools

    # Install NgVeri Depedencies
    echo "Installing Pip3............................"
    sudo apt install -y python3-pip

    echo "Installing Watchdog........................"
    pip3 install watchdog

    echo "Installing Hdlparse........................"
    pip3 install --upgrade https://github.com/hdl/pyhdlparser/tarball/master

    echo "Installing Makerchip......................."
    pip3 install makerchip-app

    echo "Installing SandPiper Saas.................."
    pip3 install sandpiper-saas

   
    echo "Installing Hdlparse......................"
    pip3 install hdlparse

    echo "Installing matplotlib................"
    pip3 install matplotlib

    echo "Installing PyQt5............."
    pip3 install PyQt5  
}


function copyKicadLibrary
{
    echo "Extracting custom KiCad Library..."

    # Remove a partial extraction from an earlier failed run.
    rm -rf kicadLibrary
    tar -xJf library/kicadLibrary.tar.xz

    kicad_version="8.0"
    kicad_config_dir="$HOME/.config/kicad/$kicad_version"

    echo "Using KiCad configuration directory: $kicad_config_dir"
    mkdir -p "$kicad_config_dir"

    echo "Copying eSim symbol table..."
    cp "kicadLibrary/template/sym-lib-table" \
       "$kicad_config_dir/sym-lib-table"

    echo "Copying eSim custom symbols..."
    sudo mkdir -p /usr/share/kicad/symbols
    sudo cp -f kicadLibrary/eSim-symbols/* /usr/share/kicad/symbols/

    # /usr/share/kicad is system-owned; keep copied files root-owned.
    rm -rf kicadLibrary

    echo "KiCad Library configured successfully."
}


function createDesktopStartScript
{
    # Generate the eSim launcher.
    cat > esim-start.sh <<EOF
#!/bin/bash
cd "$eSim_Home/src/frontEnd"
source "$config_dir/env/bin/activate"
python3 Application.py
EOF

    sudo install -m 0755 esim-start.sh /usr/bin/esim
    rm -f esim-start.sh

    cat > esim.desktop <<EOF
[Desktop Entry]
Version=1.0
Name=eSim
Comment=EDA Tool
GenericName=eSim
Keywords=eda-tools
Exec=esim %u
Terminal=true
X-MultipleArgs=false
Type=Application
Icon=$config_dir/logo.png
Categories=Development;
MimeType=text/html;text/xml;application/xhtml+xml;application/xml;application/rss+xml;application/rdf+xml;image/gif;image/jpeg;image/png;x-scheme-handler/http;x-scheme-handler/https;x-scheme-handler/ftp;x-scheme-handler/chrome;video/webm;application/x-xpinstall;
StartupNotify=true
EOF

    chmod 755 esim.desktop
    sudo cp -f esim.desktop /usr/share/applications/

    # Desktop can be absent in minimal/headless installations.
    mkdir -p "$HOME/Desktop"
    cp -f esim.desktop "$HOME/Desktop/esim.desktop"

    set +e
    trap "" ERR
    gio set "$HOME/Desktop/esim.desktop" "metadata::trusted" true
    chmod a+x "$HOME/Desktop/esim.desktop"
    set -e
    trap error_exit ERR

    rm -f esim.desktop
    cp -f images/logo.png "$config_dir/"
}


####################################################################
#                   MAIN START FROM HERE                           #
####################################################################

### Checking if file is passsed as argument to script

if [ "$#" -eq 1 ];then
    option=$1
else
    echo "USAGE : "
    echo "./install-eSim.sh --install"
    echo "./install-eSim.sh --uninstall"
    exit 1;
fi

## Checking flags

if [ "$option" == "--install" ];then

    set -e  # Set exit option immediately on error
    set -E  # inherit ERR trap by shell functions

    # Trap on function error_exit before exiting on error
    trap error_exit ERR


    echo "Enter proxy details if you are connected to internet thorugh proxy"
    
    echo -n "Is your internet connection behind proxy? (y/n): "
    read getProxy
    if [ "$getProxy" == "y" -o "$getProxy" == "Y" ];then
        echo -n 'Proxy Hostname :'
        read proxyHostname

        echo -n 'Proxy Port :'
        read proxyPort

        echo -n username@$proxyHostname:$proxyPort :
        read username

        echo -n 'Password :'
        read -s passwd

        unset http_proxy
        unset https_proxy
        unset HTTP_PROXY
        unset HTTPS_PROXY
        unset ftp_proxy
        unset FTP_PROXY

        export http_proxy="http://$username:$passwd@$proxyHostname:$proxyPort"
        export https_proxy="http://$username:$passwd@$proxyHostname:$proxyPort"
        export HTTP_PROXY="http://$username:$passwd@$proxyHostname:$proxyPort"
        export HTTPS_PROXY="http://$username:$passwd@$proxyHostname:$proxyPort"
        export ftp_proxy="http://$username:$passwd@$proxyHostname:$proxyPort"
        export FTP_PROXY="http://$username:$passwd@$proxyHostname:$proxyPort"

        echo "Install with proxy"

    elif [ "$getProxy" == "n" -o "$getProxy" == "N" ];then
        echo "Install without proxy"
    
    else
        echo "Please select the right option"
        exit 0    
    fi

    # Calling functions
    createConfigFile
    installDependency
    installKicad
    copyKicadLibrary
    installNghdl
    installSky130Pdk
    createDesktopStartScript

    if [ $? -ne 0 ];then
        echo -e "\n\n\nERROR: Unable to install required packages. Please check your internet connection.\n\n"
        exit 0
    fi

    echo "-----------------eSim Installed Successfully-----------------"
    echo "Type \"esim\" in Terminal to launch it"
    echo "or double click on \"eSim\" icon placed on Desktop"


elif [ "$option" == "--uninstall" ];then
    echo -n "Are you sure? It will remove eSim completely including KiCad, Makerchip, NGHDL and SKY130 PDK along with their models and libraries (y/n):"
    read getConfirmation

    if [ "$getConfirmation" == "y" -o "$getConfirmation" == "Y" ]; then
        echo "Removing eSim............................"
        rm -rf "$HOME/.esim" "$HOME/Desktop/esim.desktop"
        sudo rm -f /usr/bin/esim /usr/share/applications/esim.desktop

        echo "Removing KiCad..........................."
        sudo apt purge -y kicad kicad-footprints kicad-libraries kicad-symbols kicad-templates
        sudo rm -rf /usr/share/kicad
        sudo rm -f /etc/apt/sources.list.d/kicad*
        rm -rf "$HOME/.config/kicad/8.0"

        echo "Removing SKY130 PDK......................"
        sudo rm -rf /usr/share/local/sky130_fd_pr

        echo "Removing NGHDL..........................."
        rm -rf library/modelParamXML/Nghdl/* library/modelParamXML/Ngveri/*

        if [ -d nghdl ]; then
            if [ -f nghdl/install-nghdl-scripts/install-nghdl-25.04.sh ]; then
                (
                    cd nghdl || exit 1
                    bash install-nghdl-scripts/install-nghdl-25.04.sh --uninstall
                ) || echo "Warning: NGHDL uninstall script reported an error."
            fi
            rm -rf nghdl
        else
            echo "NGHDL source directory is not present; skipping bundled uninstall script."
        fi

        echo "----------------eSim Uninstalled Successfully----------------"
    elif [ "$getConfirmation" == "n" -o "$getConfirmation" == "N" ]; then
        exit 0
    else
        echo "Please select the right option."
        exit 1
    fi
else 
    echo "Please select the proper operation."
    echo "--install"
    echo "--uninstall"
fi

