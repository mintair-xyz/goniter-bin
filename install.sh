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

# FRP Configuration
FRP_INSTALL_DIR="/home/vm/frp"
FRP_BINARY_NAME="frpc"
FRP_SERVICE_NAME="frpc"
FRP_DOWNLOAD_URL="https://github.com/fatedier/frp/releases/download/v0.63.0/frp_0.63.0_linux_amd64.tar.gz"

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
Environment=FRP_ADDRESS=$FRP_ADDRESS
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

# Function to install FRP client
install_frp() {
    if [[ -z "$FRP_TOKEN" ]]; then
        return 0
    fi
    
    # Use FRP_ADDRESS environment variable
    if [[ -z "$FRP_ADDRESS" ]]; then
        print_error "FRP_ADDRESS environment variable not set"
        exit 1
    fi
    
    # Check if FRP is already installed
    if [[ -f "$FRP_INSTALL_DIR/$FRP_BINARY_NAME" ]]; then
        print_status "FRP client already exists. Updating..."
        
        # Stop the FRP service if it's running
        if sudo systemctl is-active --quiet "$FRP_SERVICE_NAME"; then
            print_status "Stopping existing FRP service..."
            sudo systemctl stop "$FRP_SERVICE_NAME"
        fi
        
        # Backup existing binary
        print_status "Backing up existing FRP binary..."
        sudo cp "$FRP_INSTALL_DIR/$FRP_BINARY_NAME" "$FRP_INSTALL_DIR/${FRP_BINARY_NAME}.backup"
        
        # Download and extract FRP
        print_status "Downloading updated FRP from: $FRP_DOWNLOAD_URL"
        cd /tmp
        wget -O frp.tar.gz "$FRP_DOWNLOAD_URL"
        tar -xzf frp.tar.gz
        
        # Copy frpc binary
        FRP_EXTRACTED_DIR=$(tar -tzf frp.tar.gz | head -1 | cut -f1 -d"/")
        sudo cp "$FRP_EXTRACTED_DIR/frpc" "$FRP_INSTALL_DIR/"
        sudo chmod +x "$FRP_INSTALL_DIR/frpc"
        
    else
        print_status "Installing FRP client..."
        
        # Create FRP directory
        print_status "Creating FRP directory: $FRP_INSTALL_DIR"
        sudo mkdir -p "$FRP_INSTALL_DIR"
        
        # Download and extract FRP
        print_status "Downloading FRP from: $FRP_DOWNLOAD_URL"
        cd /tmp
        wget -O frp.tar.gz "$FRP_DOWNLOAD_URL"
        tar -xzf frp.tar.gz
        
        # Copy frpc binary
        FRP_EXTRACTED_DIR=$(tar -tzf frp.tar.gz | head -1 | cut -f1 -d"/")
        sudo cp "$FRP_EXTRACTED_DIR/frpc" "$FRP_INSTALL_DIR/"
        sudo chmod +x "$FRP_INSTALL_DIR/frpc"
    fi
    
    # Create FRP configuration
    print_status "Creating FRP configuration..."
    cat > /tmp/frpc.yaml << EOF
serverAddr: "148.113.142.124"
serverPort: 7000
auth:
  token: "$FRP_TOKEN"

proxies:
  - name: "web-machine-1"
    type: "http"
    localPort: 40000
    customDomains: 
      - "148.113.142.124"
    locations:
      - "/$FRP_ADDRESS"
EOF
    
    sudo mv /tmp/frpc.yaml "$FRP_INSTALL_DIR/"
    
    # Create/update FRP systemd service
    print_status "Creating/updating FRP systemd service..."
    cat > /tmp/frpc.service << EOF
[Unit]
Description=FRP Client
After=network.target

[Service]
Type=simple
User=$SERVICE_USER
Group=$SERVICE_GROUP
WorkingDirectory=$FRP_INSTALL_DIR
ExecStart=$FRP_INSTALL_DIR/frpc -c $FRP_INSTALL_DIR/frpc.yaml
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=$FRP_SERVICE_NAME

[Install]
WantedBy=multi-user.target
EOF
    
    sudo mv /tmp/frpc.service "/etc/systemd/system/$FRP_SERVICE_NAME.service"
    
    # Set ownership
    sudo chown -R "$SERVICE_USER:$SERVICE_GROUP" "$FRP_INSTALL_DIR"
    
    # Reload systemd and enable service
    sudo systemctl daemon-reload
    sudo systemctl enable "$FRP_SERVICE_NAME"
    
    # Start or restart the service
    if [[ -f "$FRP_INSTALL_DIR/${FRP_BINARY_NAME}.backup" ]]; then
        # This is an update, restart the service
        print_status "Restarting FRP service..."
        sudo systemctl restart "$FRP_SERVICE_NAME"
        
        # Check if service started successfully
        if sudo systemctl is-active --quiet "$FRP_SERVICE_NAME"; then
            print_status "FRP client service updated and running successfully!"
            print_status "Your machine is accessible at: http://148.113.142.124/$FRP_ADDRESS"
            
            # Clean up backup on successful restart
            sudo rm -f "$FRP_INSTALL_DIR/${FRP_BINARY_NAME}.backup"
        else
            print_error "FRP service failed to start after update. Rolling back..."
            sudo cp "$FRP_INSTALL_DIR/${FRP_BINARY_NAME}.backup" "$FRP_INSTALL_DIR/$FRP_BINARY_NAME"
            sudo systemctl restart "$FRP_SERVICE_NAME"
            print_error "Rolled back to previous FRP version. Check logs with: sudo journalctl -u $FRP_SERVICE_NAME -f"
            exit 1
        fi
    else
        # This is a fresh install, start the service
        print_status "Starting FRP service..."
        sudo systemctl start "$FRP_SERVICE_NAME"
        
        # Check FRP service status
        if sudo systemctl is-active --quiet "$FRP_SERVICE_NAME"; then
            print_status "FRP client service is running successfully!"
            print_status "Your machine is accessible at: http://148.113.142.124/$FRP_ADDRESS"
        else
            print_error "FRP client service failed to start. Check logs with: sudo journalctl -u $FRP_SERVICE_NAME -f"
            exit 1
        fi
    fi
    
    # Clean up
    rm -f /tmp/frp.tar.gz
    rm -rf "/tmp/$FRP_EXTRACTED_DIR"
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

# Install FRP client if requested
install_frp

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
