#!/bin/bash

append_if_missing() {
    CRT_TO_ADD="$1"
    CRT_LIST_FILE="$2"

    NEW_CERT_HASH=$(openssl x509 -in "$CRT_TO_ADD" -outform PEM | sha256sum | awk '{print $1}')
    FOUND=0

    # Split the target into individual certs and compare hash
    csplit -f temp-cert- "$CRT_LIST_FILE" '/-----BEGIN CERTIFICATE-----/' '{*}' >/dev/null 2>&1

    for CERT in temp-cert-*; do
        if grep -q "BEGIN CERTIFICATE" "$CERT"; then
            CERT_HASH=$(openssl x509 -in "$CERT" -outform PEM 2>/dev/null | sha256sum | awk '{print $1}')
            if [ "$CERT_HASH" == "$NEW_CERT_HASH" ]; then
                FOUND=1
                break
            fi
        fi
    done

    rm -f temp-cert-*

    if [ "$FOUND" -eq 1 ]; then
        echo "Certificate already exists in $CRT_LIST_FILE. Skipping append."
    else
        cat "$CRT_TO_ADD" >> "$CRT_LIST_FILE"
        echo "Appended cert to $CRT_LIST_FILE"
    fi
}



read -p "Username: " username
echo
read -s -p "Password: " password
echo


ips="192.168.1.1"

# Loop through each IP in the variable
for ip in $ips; do
  echo "Processing IP: $ip"
  CRT=$(openssl s_client -showcerts -host ${ip} -port 4353 </dev/null 2>/dev/null | openssl x509 -outform PEM)

  echo

  append_if_missing "$CRT" "/config/gtm/server.crt"

done
