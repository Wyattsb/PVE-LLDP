#!/bin/bash

# ----------------------------------------------------------------------------
# Script to Update Network Interface Descriptions Based on LLDP Information
# Developer: Abdelbar Aglagane
# Email: abdellbar@gmail.com
# 
# DISCLAIMER:
# This script is provided "AS IS", without warranty of any kind, express or
# implied, including but not limited to the warranties of merchantability,
# fitness for a particular purpose and noninfringement. In no event shall the
# authors or copyright holders be liable for any claim, damages or other
# liability, whether in an action of contract, tort or otherwise, arising from,
# out of or in connection with the script or the use or other dealings in the
# script.
#
# LICENSE:
# This script is part of the "ProxLLDPConfig" repository and governed by the
# terms of the repository's license agreement. Unauthorized copying of this file,
# via any medium is strictly prohibited and the file may not be modified or
# distributed without the permission of the copyright holder.
# ----------------------------------------------------------------------------

# Path to the network interfaces configuration file
INTERFACES_FILE="/etc/network/interfaces"
TEMP_FILE="/tmp/interfaces.new"
LOG_FILE="/var/log/update_interface_desc.log"

# Logging function
log() {
    echo "$(date +'%Y-%m-%d %H:%M:%S') - $*" >> $LOG_FILE
}

# Backup the current interfaces file
cp $INTERFACES_FILE $TEMP_FILE
log "Backed up current interfaces file."

# Configure lldpcli to only monitor en* interfaces
lldpcli configure system interface pattern '*'
log "Configured lldpcli to monitor interfaces matching '*' pattern."

# Function to update interface description
update_description() {
    iface=$1
    descr=$2
    # Use the description as provided
    full_descr="$descr"
    pattern="iface $iface inet"
    if grep -q "^$pattern" $TEMP_FILE; then
        log "Found configuration for $iface."
        # Check if the description already exists
        descr_line="^#\s*$full_descr"
        if ! grep -q "$descr_line" $TEMP_FILE; then
            # Add the description to the interface definition
            sed -i "/$pattern/a #$full_descr" $TEMP_FILE
            log "Added description '$full_descr' to $iface."
        else
            log "Description '$full_descr' already exists for $iface, skipping."
        fi
    else
        log "No configuration found for $iface, skipping."
    fi
}

# Initialize variables to track interfaces and their SysName/PortDescr
declare -A iface_sysnames
declare -A iface_portdescrs
declare -A iface_portid

# Process each neighbor and extract relevant data
while IFS= read -r line; do
    if [[ "$line" =~ Interface: ]]; then
        iface=$(echo "$line" | awk '{print $2}' | tr -d ',')
    elif [[ "$line" =~ SysName: ]]; then
        ll_dp_sysname=$(echo "$line" | awk '{for(i=2;i<=NF;i++) printf "%s ", $i}' | sed 's/ *$//')
        # Store SysName only if not already set for this interface
        if [[ -z "${iface_sysnames[$iface]}" ]]; then
            iface_sysnames[$iface]="$ll_dp_sysname"
        fi
    elif [[ "$line" =~ PortID: ]]; then
        port_id=$(echo "$line" | cut -d ' ' -f 2-)
        # Store PortID only if not already set for this interface
        if [[ -z "${iface_portid[$iface]}" ]]; then
            iface_portid[$iface]="$port_id"
        fi
    elif [[ "$line" =~ PortDescr: ]]; then
        port_descr=$(echo "$line" | awk '{for(i=2;i<=NF;i++) printf "%s ", $i}' | sed 's/ *$//')
        # Store PortDescr only if not already set for this interface
        if [[ -z "${iface_portdescrs[$iface]}" ]]; then
            iface_portdescrs[$iface]="$port_descr"
            log "Found SysName '${iface_sysnames[$iface]}' plugged into '${iface_portid[$iface]}' and PortDescr '$port_descr' for $iface."
        fi
    fi
done < <(lldpcli show neighbors)

# Update descriptions for each interface with a SysName and PortDescr
for iface in "${!iface_sysnames[@]}"; do
    ll_dp_sysname="${iface_sysnames[$iface]}"
    port_descr="${iface_portdescrs[$iface]}"
    port_id="${iface_portid[$iface]}"
    if [[ -n "$ll_dp_sysname" && -n "$port_descr" && -n "$port_id"]]; then
        descr="${ll_dp_sysname}/${port_id} - ${port_descr}"
        log "Processing $iface with description $descr."
        update_description "$iface" "$descr"
    else
        log "No SysName or PortDescr found for $iface, skipping."
    fi
done

# Check for changes and update the original file if needed
if ! cmp -s $TEMP_FILE $INTERFACES_FILE; then
    echo "Updating network interface descriptions..."
    cp $TEMP_FILE $INTERFACES_FILE
    log "Updated the network interface file with new descriptions."
else
    log "No changes to apply."
fi

# Clean up temporary file
rm $TEMP_FILE
log "Cleanup completed."
