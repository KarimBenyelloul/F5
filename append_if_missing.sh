#!/bin/bash

# Iterating Over Each Certificate in CRTS_TO_ADD
# For each certificate, it verifies if it already exists in CRT_LIST_FILE
# If not, appends it.


CRTS_TO_ADD="$1"
CRT_LIST_FILE="$2"


# Check if CRT_TO_ADD file exists and is readable
if [[ ! -f "$CRTS_TO_ADD" || ! -r "$CRTS_TO_ADD" ]]; then
    echo "Error: $CRTS_TO_ADD does not exist or is not readable."
    exit 1
fi

# Check if CRT_LIST_FILE exists and is readable
if [[ ! -f "$CRT_LIST_FILE" || ! -r "$CRT_LIST_FILE" ]]; then
    echo "Error: $CRT_LIST_FILE does not exist or is not readable."
    exit 1
fi

# Split the certificates in CRT_TO_ADD and CRT_LIST_FILE into separate files
csplit -f temp-toAdd- "$CRTS_TO_ADD" '/-----BEGIN CERTIFICATE-----/' '{*}' >/dev/null 2>&1
csplit -f temp-exist- "$CRT_LIST_FILE" '/-----BEGIN CERTIFICATE-----/' '{*}' >/dev/null 2>&1

# Process each certificate in CRT_TO_ADD
for CRT_TO_ADD in temp-toAdd-*; do
    if grep -q "BEGIN CERTIFICATE" "$CRT_TO_ADD"; then
        NEW_CERT_HASH=$(openssl x509 -in "$CRT_TO_ADD" -outform PEM | sha256sum | awk '{print $1}')
        FOUND=0

        # Check if the certificate is already in CRT_LIST_FILE
        for CERT in temp-exist-*; do
            if grep -q "BEGIN CERTIFICATE" "$CERT"; then
                CERT_HASH=$(openssl x509 -in "$CERT" -outform PEM 2>/dev/null | sha256sum | awk '{print $1}')
                if [ "$CERT_HASH" == "$NEW_CERT_HASH" ]; then
                    FOUND=1
                    break
                fi
            fi
        done

        if [ "$FOUND" -eq 1 ]; then
            echo "Certificate already exists in $CRT_LIST_FILE. Skipping append."
        else
            # Append the certificate to the CRT_LIST_FILE using tee for appending
            cat "$CRT_TO_ADD" | tee -a "$CRT_LIST_FILE" >/dev/null
            echo "Appended cert to $CRT_LIST_FILE"
        fi
    fi
done

# Clean up temporary files
rm -f temp-exist-* temp-toAdd-*

# Output the action completion status
echo "Script completed."
