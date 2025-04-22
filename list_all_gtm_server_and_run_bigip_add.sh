devices=$(tmsh list gtm server | awk -v exclude_ips="$exclude_ips" '
  BEGIN {
    # Convert the space-separated exclude_ips string into an array
    split(exclude_ips, exclude_array, " ")
    output_devices=""
  }

  # Flag to indicate we are inside a gtm server block
  /^gtm server/ {
    # Reset variables for each new server block
    server_name=$3
    inside_addresses=0
    product_bigip=0
    device_ip=""
  }

  # Process the "addresses" section and extract IPs
  /            addresses {/ {inside_addresses=1}
  inside_addresses && /^                +[0-9.]+/ {
    ip=$1

    # Accumulate IPs in device_ip
    device_ip=device_ip " " ip
  }

  # Look for the "product bigip" line after processing the devices section
  /    product bigip/ {
    product_bigip=1
  }

  # End processing addresses once we exit the block
  /^}/ {
    inside_addresses=0
    # After processing a server block, print the result if the server has "product bigip"
    if (product_bigip && device_ip != "") {
      # Exclude IPs that are found in the exclude_ips list
      valid_ips=""
      for (i in exclude_array) {
        # Exclude the IPs from the device_ip list
        device_ip = gensub(" " exclude_array[i], "", "g", device_ip)
      }

      # If we still have valid IPs after exclusion, print the result
      if (device_ip != "") {
        output_devices=output_devices " " device_ip
      }
    }
  }
  #
  END {
    print output_devices
  }
')

echo $devices
