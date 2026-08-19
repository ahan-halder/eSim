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
#       AUTHORS: Ahan Halder
#  ORGANIZATION: eSim Team, FOSSEE, IIT Bombay
#       CREATED: Sunday 19 August 2026 17:40
#      REVISION: Tuesday 19 August 2026
#=============================================================================

# Function to detect Ubuntu version and full version string.
#
# Ubuntu 25.04 reports a two-component version string (e.g. "25.04") while
# older releases such as 22.04.4 report three components.  The original
# upstream regex '\d+\.\d+\.\d+' required exactly three components and
# therefore returned an empty string on Ubuntu 25.04, causing the dispatcher
# to fall through to the unsupported-version branch.  The pattern is now
# '\d+\.\d+(?:\.\d+)?' so that both two- and three-component strings match.
get_ubuntu_version() {
    VERSION_ID=$(grep "^VERSION_ID" /etc/os-release | cut -d '"' -f 2)
    FULL_VERSION=$(lsb_release -d | grep -oP '\d+\.\d+(?:\.\d+)?')
    echo "Detected Ubuntu Version: $FULL_VERSION"
}

# Choose and execute the version-specific installer sub-script.
#
# VERSION_ID (e.g. "25.04") is taken directly from /etc/os-release and is
# used as the switch key because it is always a clean two-component string,
# even on Ubuntu 25.04.  The more verbose FULL_VERSION is kept for the
# 22.04 vs 22.04.4 distinction and for the diagnostic message printed by
# get_ubuntu_version().
#
# Ubuntu 25.04 routes to install-eSim-25.04.sh, a new script that handles
# the compatibility changes required for that release (LLVM 18 / GHDL 4.1.0,
# KiCad 8, updated NGHDL installer).
run_version_script() {
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/install-eSim-scripts"

    case $VERSION_ID in
        "22.04")
            if [[ "$FULL_VERSION" == "22.04.4" ]]; then
                SCRIPT="$SCRIPT_DIR/install-eSim-22.04.sh"
            else
                SCRIPT="$SCRIPT_DIR/install-eSim-23.04.sh"
            fi
            ;;
        "23.04")
            SCRIPT="$SCRIPT_DIR/install-eSim-23.04.sh"
            ;;
        "24.04")
            SCRIPT="$SCRIPT_DIR/install-eSim-24.04.sh"
            ;;
        "25.04")
            # Ubuntu 25.04 requires a dedicated installer; the 24.04 script
            # cannot be reused because of LLVM, KiCad, and NGHDL differences.
            SCRIPT="$SCRIPT_DIR/install-eSim-25.04.sh"
            ;;
        *)
            echo "Unsupported Ubuntu version: $VERSION_ID ($FULL_VERSION)"
            exit 1
            ;;
    esac

    # Run the script if found
    if [[ -f "$SCRIPT" ]]; then
        echo "Running script: $SCRIPT $ARGUMENT"
        bash "$SCRIPT" "$ARGUMENT"
    else
        echo "Installation script not found: $SCRIPT"
        exit 1
    fi
}

# --- Main Execution Starts Here ---

# Validate argument
if [[ $# -ne 1 ]]; then
    echo "Usage: $0 --install | --uninstall"
    exit 1
fi

ARGUMENT=$1
if [[ "$ARGUMENT" != "--install" && "$ARGUMENT" != "--uninstall" ]]; then
    echo "Invalid argument: $ARGUMENT"
    echo "Usage: $0 --install | --uninstall"
    exit 1
fi

get_ubuntu_version
run_version_script

