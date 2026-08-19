#!/bin/bash 
#==========================================================
#          FILE: install-nghdl.sh
# 
#         USAGE: ./install-nghdl.sh --install
#                 			OR
#                ./install-nghdl.sh --uninstall
# 
#   DESCRIPTION: Installation script for Ngspice, GHDL 
#                and Verilator simulators (NGHDL)
#       OPTIONS: ---
#  REQUIREMENTS: ---
#          BUGS: ---
#         NOTES: ---
#        AUTHOR: Ahan Halder
#  ORGANIZATION: eSim, FOSSEE group at IIT Bombay
#       CREATED: Tuesday 02 December 2014 17:01
#      REVISION: Tuesday 19 August 2026
#==========================================================
#
# This is the Ubuntu 25.04-specific NGHDL installer.
# It is injected into the bundled NGHDL tree by install-eSim-25.04.sh
# and replaces the original install-nghdl.sh, which only supported
# older Ubuntu releases.

nghdl="nghdl-simulator"
ghdl="ghdl-4.1.0"
verilator="verilator-4.210"
config_dir="$HOME/.nghdl"
config_file="config.ini"
src_dir="$(pwd)"

# Will be used to take backup of any file
sysdate="$(date)"
timestamp=$(echo "$sysdate" | awk '{print $3"_"$2"_"$6"_"$4}')


# All functions goes here

error_exit() {
    echo -e "\n\nError! Kindly resolve above error(s) and try again."
    echo -e "\nAborting Installation...\n"
}


function installDependency
{
    echo "Installing dependencies for $ghdl LLVM................"

    echo "Installing Make..........................................."
    sudo apt install -y make

    echo "Installing GNAT..........................................."
    sudo apt install -y gnat

    # GHDL 4.1.0 supports up to LLVM 18.  Ubuntu 25.04's default LLVM
    # packages install LLVM 20.1.2, which is not recognised by GHDL 4.1.0's
    # configure script ("Unhandled version llvm 20.1.2").  Installing the
    # versioned llvm-18 / llvm-18-dev / clang-18 packages alongside the
    # system default avoids downgrading or replacing the system LLVM.
    echo "Installing LLVM 18 for GHDL 4.1.0......................."
    sudo apt install -y llvm-18 llvm-18-dev

    echo "Installing Clang 18......................................."
    sudo apt install -y clang-18

    echo "Installing Zlib1g-dev....................................."
    sudo apt install -y zlib1g-dev

    # libcanberra-gtk-module was removed from Ubuntu 25.04 repositories.
    # libcanberra-gtk3-module provides the same GTK3 sound-events support
    # and is available in Ubuntu 25.04.
    echo "Installing Gtk Canberra module............................"
    sudo apt install -y libcanberra-gtk3-module

    echo "Installing graphics dependencies for Ngspice.............."
    sudo apt install -y libxaw7 libxaw7-dev

    echo "Installing dependencies for $verilator...................."
    sudo apt install -y make autoconf g++ flex bison
}



function installGHDL
{
    echo "Installing $ghdl LLVM................................."

    # Remove any previous build directory so that failed or partially
    # completed builds (which may be root-owned from a prior sudo make)
    # do not cause permission errors on the next run.
    rm -rf "$ghdl"
    tar xvf "$ghdl.tar.gz"

    echo "$ghdl successfully extracted"
    echo "Changing directory to $ghdl installation"
    cd "$ghdl" || return 1

    echo "Configuring $ghdl build as per requirements"
    chmod +x configure
    # CXX=clang++-18 tells the C++ compiler to use Clang 18, which matches
    # the LLVM 18 libraries.  --with-llvm-config=/usr/bin/llvm-config-18
    # points GHDL at the versioned LLVM 18 config tool rather than the
    # system default llvm-config (LLVM 20 on Ubuntu 25.04).  Both the
    # compiler and llvm-config must refer to the same LLVM version;
    # mixing versions produces link errors.
    CXX=clang++-18 ./configure --with-llvm-config=/usr/bin/llvm-config-18

    echo "Building the install file for $ghdl LLVM"
    make -j"$(nproc)"
    sudo make install

    echo "GHDL installed successfully"
    cd "$src_dir" || return 1
}


function installVerilator
{
    echo "Installing $verilator......................."

    rm -rf "$verilator"
    tar -xvf "$verilator.tar.xz"

    echo "$verilator successfully extracted"
    echo "Changing directory to $verilator installation"
    cd "$verilator" || return 1

    echo "Configuring $verilator build as per requirements"
    chmod +x configure
    ./configure
    make -j"$(nproc)"
    sudo make install

    echo "Removing unessential Verilator files........"
    rm -rf docs examples include test_regress bin
    ls -1 | grep -E -v 'config.status|configure.ac|Makefile.in|verilator.1|configure|Makefile|src|verilator.pc' | xargs -r rm -f

    echo "Verilator installed successfully"
    cd "$src_dir" || return 1
}


function installNGHDL
{
    echo "Installing NGHDL........................................"

    local source_archive="$src_dir/${nghdl}-source.tar.xz"
    local extracted_dir="$HOME/${nghdl}-source"
    local install_root="$HOME/$nghdl"

    # Make repeated installation deterministic instead of nesting a new
    # source tree inside a previous installation.
    rm -rf "$extracted_dir" "$install_root"

    tar -xJf "$source_archive" -C "$HOME"
    mv "$extracted_dir" "$install_root"

    echo "NGHDL extracted successfully to $install_root"

    mkdir -p "$install_root/install_dir"
    mkdir -p "$install_root/release"
    cd "$install_root/release" || return 1

    echo "Configuring NGHDL..........."
    chmod +x ../configure
    ../configure \
        --enable-xspice \
        --disable-debug \
        --prefix="$install_root/install_dir/" \
        --exec-prefix="$install_root/install_dir/"

    make -j"$(nproc)"
    make install

    sudo chmod 755 "$install_root/install_dir/bin/ngspice"

    # Remove a distro ngspice package if present, then point /usr/bin/ngspice
    # at the NGHDL build.
    set +e
    trap "" ERR
    echo "Removing previously installed Ngspice package (if any)"
    sudo apt-get purge -y ngspice
    sudo rm -f /usr/bin/ngspice
    set -e
    trap error_exit ERR

    sudo ln -sf "$install_root/install_dir/bin/ngspice" /usr/bin/ngspice
    echo "NGHDL installed successfully"
    echo "Added symlink for Ngspice."

    cd "$src_dir" || return 1
}


function createConfigFile
{
    mkdir -p "$config_dir"
    : > "$config_dir/$config_file"

    echo "[NGHDL]" >> "$config_dir/$config_file"
    echo "NGHDL_HOME = $HOME/$nghdl" >> "$config_dir/$config_file"
    echo "DIGITAL_MODEL = %(NGHDL_HOME)s/src/xspice/icm" >> "$config_dir/$config_file"
    echo "RELEASE = %(NGHDL_HOME)s/release" >> "$config_dir/$config_file"
    echo "[SRC]" >> "$config_dir/$config_file"
    echo "SRC_HOME = $src_dir" >> "$config_dir/$config_file"
    echo "LICENSE = %(SRC_HOME)s/LICENSE" >> "$config_dir/$config_file"
}


function createSoftLink
{
    sudo chmod 755 "$src_dir/src/ngspice_ghdl.py"
    sudo ln -sf "$src_dir/src/ngspice_ghdl.py" /usr/local/bin/nghdl
    echo "Added symlink for NGHDL."
}


#####################################################################
#       Script start from here                                     #
#####################################################################

### Checking if file is passsed as argument to script

if [ "$#" -eq 1 ];then
    option=$1
else
    echo "USAGE : "
    echo "./install-nghdl.sh --install"
    exit 1;
fi

## Checking flags
if [ "$option" == "--install" ];then
    
    set -e  # Set exit option immediately on error
    set -E  # inherit ERR trap by shell functions

    # Trap on function error_exit before exiting on error
    trap error_exit ERR
    
    #Calling functions
    installDependency
    if [ $? -ne 0 ];then
        echo -e "\n\n\nERROR: Unable to install required packages. Please check your internet connection.\n\n"
        exit 0
    fi
   
    installGHDL
    installVerilator
    installNGHDL
    createConfigFile
    createSoftLink

elif [ "$option" == "--uninstall" ];then
    echo "Removing NGHDL installation..........................."

    if [ -d "$src_dir/$ghdl" ]; then
        (
            cd "$src_dir/$ghdl" || exit 1
            sudo make uninstall
        ) || echo "Warning: GHDL make uninstall reported an error."
    fi

    if [ -d "$src_dir/$verilator" ]; then
        (
            cd "$src_dir/$verilator" || exit 1
            sudo make uninstall
        ) || echo "Warning: Verilator make uninstall reported an error."
    fi

    rm -rf "$src_dir/$ghdl" "$src_dir/$verilator"
    rm -rf "$HOME/$nghdl" "$HOME/.nghdl"
    sudo rm -f /usr/local/bin/nghdl /usr/bin/ngspice

    echo "Keeping shared LLVM 18, Clang 18, GNAT and build dependencies installed."
    echo "NGHDL uninstall completed."
else 
    echo "Please select the proper operation."
    echo "--install"
    echo "--uninstall"
fi

