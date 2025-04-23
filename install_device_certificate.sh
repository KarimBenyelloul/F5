#!/bin/bash

# Default verbose mode is off
VERBOSE=0

# Function to print usage/help message
print_help() {
    echo "Usage: $0 <cert_file> <key_file> [options]"
    echo
    echo "Options:"
    echo "  -h, --help      Show this help message"
    echo "  -v, --verbose   Enable verbose output"
    echo
    echo "This script updates the SSL certificate and key on an F5 device."
    echo "It validates the given certificate and key, checks the service status,"
    echo "backs up the current certificate and key, installs the new ones,"
    echo "restores permissions, restarts the httpd service, and appends the cert to"
    echo "big3d/client.crt and gtm/server.crt if not already present."
    echo
    echo "Example usage:"
    echo "  $0 /path/to/certificate.crt /path/to/private.key"
    exit 0
}

# Function to handle verbose output
verbose_echo() {
    if [ "$VERBOSE" -eq 1 ]; then
        echo "$1"
    fi
}

# Parse command-line arguments for options
while [[ "$1" =~ ^- ]]; do
    case "$1" in
        -h|--help)
            print_help
            ;;
        -v|--verbose)
            VERBOSE=1
            shift
            ;;
        *)
            echo "Error: Unknown option $1"
            print_help
            ;;
    esac
done

# Ensure two arguments are passed (certificate and key files)
if [ "$#" -ne 2 ]; then
    echo "Error: Missing certificate or key file."
    print_help
fi

# Source files (provided by the user)
CERT_INPUT="$1"
KEY_INPUT="$2"

# Destination file paths
CRT_DEST="/config/httpd/conf/ssl.crt/server.crt"
KEY_DEST="/config/httpd/conf/ssl.key/server.key"
BACKUP_SUFFIX=$(date +%Y%m%d_%H%M%S)

# Function to check and append certificate CRT_TO_ADD only if not already present in CRT_LIST_FILE
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
if [ ! -f "$CERT_INPUT" ] || [ ! -f "$KEY_INPUT" ]; then
    echo "Error: Source certificate or key file not found. Aborting."
    exit 1
fi

# Check if CERT_INPUT is a valid certificate
if ! openssl x509 -in "$CERT_INPUT" -noout 2>/dev/null; then
    echo "Error: $CERT_INPUT is not a valid certificate file."
    exit 1
fi

# Check if KEY_INPUT is a valid private key
if ! openssl rsa -in "$KEY_INPUT" -noout 2>/dev/null; then
    echo "Error: $KEY_INPUT is not a valid private key file."
    exit 1
fi

# Validate the given cert and key match
CERT_MODULUS=$(openssl x509 -noout -modulus -in "$CERT_INPUT" | openssl md5)
KEY_MODULUS=$(openssl rsa -noout -modulus -in "$KEY_INPUT" | openssl md5)
if [ "$CERT_MODULUS" != "$KEY_MODULUS" ]; then
    echo "Error: Certificate and key do not match!"
    exit 1
fi
echo "Given certificate and key match."

# Check if destination files exist
if [ ! -f "$CRT_DEST" ] || [ ! -f "$KEY_DEST" ]; then
    echo "Error: Destination certificate or key file not found. Aborting."
    exit 1
fi

# Check if httpd is running
HTTPD_STATUS=$(tmsh show sys service httpd)
if [[ "$HTTPD_STATUS" == *"is running"* ]]; then
    verbose_echo "httpd service is running."
else
    echo "Error: httpd service is not running. Aborting."
    exit 1
fi

# Backup current cert and key
cp "$CRT_DEST" "${CRT_DEST}.${BACKUP_SUFFIX}.bak"
cp "$KEY_DEST" "${KEY_DEST}.${BACKUP_SUFFIX}.bak"
echo "Backup of existing cert and key created."


# Replace with new cert and key
echo "Replacing the current cert and key with new ones..."
cp "$CERT_INPUT" "$CRT_DEST"
cp "$KEY_INPUT" "$KEY_DEST"

# Restore permissions and ownership
verbose_echo "Restoring permissions and ownership..."
chmod --reference="${CRT_DEST}.${BACKUP_SUFFIX}.bak" "$CRT_DEST"
chmod --reference="${KEY_DEST}.${BACKUP_SUFFIX}.bak" "$KEY_DEST"
chown --reference="${CRT_DEST}.${BACKUP_SUFFIX}.bak" "$CRT_DEST"
chown --reference="${KEY_DEST}.${BACKUP_SUFFIX}.bak" "$KEY_DEST"

verbose_echo "New cert and key installed with correct permissions."

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
echo "Appending cert to big3d and gtm if not already present..."
append_if_missing "$CRT_DEST" "/config/big3d/client.crt"
append_if_missing "$CRT_DEST" "/config/gtm/server.crt"

echo "SSL certificate and key updated and propagated successfully."
