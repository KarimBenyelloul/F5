#!/bin/bash

# Takes two input files (cert and key) and updates the F5 device certificate.
# Verifies the given cert and key match.
# Verifies that the current destination cert/key exist
# Checks if httpd is running.
# Backs up the current destination cert/key.
# Replaces them with the new ones.
# Restores permissions/ownership.
# Restarts httpd and checks it restarted correctly.
# Appends the cert to big3d/client.crt and gtm/server.crt only if not already present.



# Ensure two arguments are passed (certificate and key files)
if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <cert_file> <key_file>"
    exit 1
fi

# Source files (provided by the user)
CERT_FILE="$1"
KEY_FILE="$2"

# Destination file paths
CRT_DEST="/config/httpd/conf/ssl.crt/server.crt"
KEY_DEST="/config/httpd/conf/ssl.key/server.key"
BACKUP_SUFFIX=$(date +%Y%m%d_%H%M%S)

# Function to check and append certificate only if not already present
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

# Check existence of necessary files
if [ ! -f "$CERT_FILE" ] || [ ! -f "$KEY_FILE" ]; then
    echo "Error: Source certificate or key file not found. Aborting."
    exit 1
fi

if [ ! -f "$CRT_DEST" ] || [ ! -f "$KEY_DEST" ]; then
    echo "Error: Destination certificate or key file not found. Aborting."
    exit 1
fi

# Backup current cert and key
cp "$CRT_DEST" "${CRT_DEST}.${BACKUP_SUFFIX}.bak"
cp "$KEY_DEST" "${KEY_DEST}.${BACKUP_SUFFIX}.bak"
echo "Backup of existing cert and key created."

# Validate the given cert and key match
CERT_MODULUS=$(openssl x509 -noout -modulus -in "$CERT_FILE" | openssl md5)
KEY_MODULUS=$(openssl rsa -noout -modulus -in "$KEY_FILE" | openssl md5)
if [ "$CERT_MODULUS" != "$KEY_MODULUS" ]; then
    echo "Error: Certificate and key do not match!"
    exit 1
fi
echo "Given certificate and key match."


# Check if httpd is running
HTTPD_STATUS=$(tmsh show sys service httpd)
if [[ "$HTTPD_STATUS" == *"is running"* ]]; then
    echo "httpd service is running."
else
    echo "Error: httpd service is not running. Aborting."
    exit 1
fi

# Replace with new cert and key
cp "$CERT_FILE" "$CRT_DEST"
cp "$KEY_FILE" "$KEY_DEST"

# Restore permissions and ownership
chmod --reference="${CRT_DEST}.${BACKUP_SUFFIX}.bak" "$CRT_DEST"
chmod --reference="${KEY_DEST}.${BACKUP_SUFFIX}.bak" "$KEY_DEST"
chown --reference="${CRT_DEST}.${BACKUP_SUFFIX}.bak" "$CRT_DEST"
chown --reference="${KEY_DEST}.${BACKUP_SUFFIX}.bak" "$KEY_DEST"

echo "New cert and key installed with correct permissions."

# Restart httpd
echo "Restarting httpd..."
tmsh restart sys service httpd
sleep 3
NEW_STATUS=$(tmsh show sys service httpd)
if [[ "$NEW_STATUS" == *"is running"* ]]; then
    echo "httpd service restarted successfully."
else
    echo "httpd restart failed! Status: $NEW_STATUS"
    exit 1
fi

# Append cert to big3d and gtm if not already present
append_if_missing "$CRT_DEST" "/config/big3d/client.crt"
append_if_missing "$CRT_DEST" "/config/gtm/server.crt"

echo "SSL certificate and key updated and propagated successfully."
