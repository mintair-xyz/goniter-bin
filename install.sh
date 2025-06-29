#!/bin/bash

# Goniter Installation Script
# This script downloads the goniter binary and sets up a systemd service

set -e  # Exit on any error

# Configuration
BINARY_NAME="goniter"
INSTALL_DIR="/home/vm/goniter-bin"
SERVICE_NAME="goniter"
SERVICE_USER="vm"
SERVICE_GROUP="vm"
DOWNLOAD_URL="https://raw.githubusercontent.com/mintair-xyz/goniter-bin/main/goniter"

# Systemd service file content
SERVICE_FILE_CONTENT="[Unit]
Description=Goniter - Docker monitoring service
After=network.target docker.service
Wants=docker.service

[Service]
Type=simple
User=$SERVICE_USER
Group=$SERVICE_GROUP
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/$BINARY_NAME
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=$SERVICE_NAME

# Environment variables (customize as needed)
Environment=PORT=40000
# Environment=API_TOKEN=your_token_here

[Install]
WantedBy=multi-user.target"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to create/update service file
create_service_file() {
    print_status "Creating/updating systemd service file..."
    echo "$SERVICE_FILE_CONTENT" | sudo tee "/etc/systemd/system/$SERVICE_NAME.service" > /dev/null
    sudo systemctl daemon-reload
}

# Check if running as root
if [[ $EUID -eq 0 ]]; then
   print_error "This script should not be run as root"
   exit 1
fi

# Check if wget is installed
if ! command -v wget &> /dev/null; then
    print_error "wget is not installed. Please install it first."
    exit 1
fi

# Check if systemctl is available
if ! command -v systemctl &> /dev/null; then
    print_error "systemctl is not available. This script requires systemd."
    exit 1
fi

# Check if binary already exists
if [[ -f "$INSTALL_DIR/$BINARY_NAME" ]]; then
    print_status "Binary already exists. Updating..."
    
    # Stop the service if it's running
    if sudo systemctl is-active --quiet "$SERVICE_NAME"; then
        print_status "Stopping existing service..."
        sudo systemctl stop "$SERVICE_NAME"
    fi
    
    # Backup existing binary
    print_status "Backing up existing binary..."
    sudo cp "$INSTALL_DIR/$BINARY_NAME" "$INSTALL_DIR/${BINARY_NAME}.backup"
    
    # Download new binary
    print_status "Downloading updated binary from: $DOWNLOAD_URL"
    cd "$INSTALL_DIR"
    sudo wget -O "$BINARY_NAME" "$DOWNLOAD_URL"
    sudo chmod +x "$BINARY_NAME"
    cd - > /dev/null
    
    # Set ownership
    sudo chown "$SERVICE_USER:$SERVICE_GROUP" "$INSTALL_DIR/$BINARY_NAME"
    
    # Update service file
    create_service_file
    
    # Restart the service
    print_status "Restarting service..."
    sudo systemctl start "$SERVICE_NAME"
    
    # Check service status
    print_status "Checking service status..."
    if sudo systemctl is-active --quiet "$SERVICE_NAME"; then
        print_status "Service updated and running successfully!"
    else
        print_error "Service failed to start after update. Rolling back..."
        sudo cp "$INSTALL_DIR/${BINARY_NAME}.backup" "$INSTALL_DIR/$BINARY_NAME"
        sudo systemctl start "$SERVICE_NAME"
        print_error "Rolled back to previous version. Check the logs with: sudo journalctl -u $SERVICE_NAME -f"
        exit 1
    fi
    
    # Clean up backup
    sudo rm -f "$INSTALL_DIR/${BINARY_NAME}.backup"
    
else
    print_status "Starting fresh Goniter installation..."
    
    # Create installation directory
    print_status "Creating installation directory: $INSTALL_DIR"
    sudo mkdir -p "$INSTALL_DIR"
    
    # Download the binary
    print_status "Downloading binary from: $DOWNLOAD_URL"
    cd "$INSTALL_DIR"
    sudo wget -O "$BINARY_NAME" "$DOWNLOAD_URL"
    sudo chmod +x "$BINARY_NAME"
    cd - > /dev/null
    
    # Set ownership
    print_status "Setting ownership to $SERVICE_USER:$SERVICE_GROUP"
    sudo chown "$SERVICE_USER:$SERVICE_GROUP" "$INSTALL_DIR"
    sudo chown "$SERVICE_USER:$SERVICE_GROUP" "$INSTALL_DIR/$BINARY_NAME"
    
    # Create service file
    create_service_file
    
    # Enable the service
    print_status "Enabling $SERVICE_NAME service..."
    sudo systemctl enable "$SERVICE_NAME"
    
    # Start the service
    print_status "Starting $SERVICE_NAME service..."
    sudo systemctl start "$SERVICE_NAME"
    
    # Check service status
    print_status "Checking service status..."
    if sudo systemctl is-active --quiet "$SERVICE_NAME"; then
        print_status "Service is running successfully!"
    else
        print_error "Service failed to start. Check the logs with: sudo journalctl -u $SERVICE_NAME -f"
        exit 1
    fi
fi

# Display service information
echo ""
print_status "Installation/Update completed successfully!"
echo ""
echo "Service Information:"
echo "  Service Name: $SERVICE_NAME"
echo "  Binary Location: $INSTALL_DIR/$BINARY_NAME"
echo "  Service User: $SERVICE_USER"
echo ""
echo "Useful Commands:"
echo "  Check service status: sudo systemctl status $SERVICE_NAME"
echo "  View service logs: sudo journalctl -u $SERVICE_NAME -f"
echo "  Stop service: sudo systemctl stop $SERVICE_NAME"
echo "  Start service: sudo systemctl start $SERVICE_NAME"
echo "  Restart service: sudo systemctl restart $SERVICE_NAME"
echo "  Disable service: sudo systemctl disable $SERVICE_NAME"
echo ""
print_status "The service will start automatically on boot." 
