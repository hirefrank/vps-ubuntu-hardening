#!/bin/bash

# configure.sh
# VPS Hardening and Configuration Script
# This script implements the hardening steps described in the README

# Exit immediately if a command exits with a non-zero status
set -e

# Function to print section headers
print_section() {
    echo "===================================="
    echo "$1"
    echo "===================================="
}

# Function to check if a package is installed
is_installed() {
    dpkg -s "$1" >/dev/null 2>&1
}

# Function to install a package if it's not already installed
install_if_not_exists() {
    if ! is_installed "$1"; then
        echo "Installing $1..."
        apt install -y "$1"
    else
        echo "$1 is already installed."
    fi
}

# Check if script is run as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root"
   exit 1
fi

# Check if config file exists
CONFIG_FILE="vps_config.env"
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Configuration file $CONFIG_FILE not found. Please create it from the template."
    exit 1
fi

# Copy the config file to /etc/vps_config.env
cp "$CONFIG_FILE" /etc/vps_config.env
chmod 600 /etc/vps_config.env

# Source the configuration file
source "$CONFIG_FILE"

# Validate required variables
required_vars=("TIMEZONE" "SLACK_WEBHOOK_URL" "B2_BUCKET_NAME" "B2_KEY_ID" "B2_APPLICATION_KEY")
for var in "${required_vars[@]}"; do
    if [ -z "${!var}" ]; then
        echo "Error: $var is not set in the configuration file."
        exit 1
    fi
done

# Function to connect to Kopia repository
connect_kopia_repository() {
    if ! kopia repository status &>/dev/null; then
        echo "Connecting to Kopia repository..."
        kopia repository connect b2 --bucket="$B2_BUCKET_NAME" --key-id="$B2_KEY_ID" --key="$B2_APPLICATION_KEY" --password="$KOPIA_REPOSITORY_PASSPHRASE"
    fi
}

# 1. Find the fastest mirror and update sources.list
print_section "Finding the fastest mirror"

# Backup the current sources.list
cp /etc/apt/sources.list /etc/apt/sources.list.bak

# Find the fastest mirror
echo "Finding the fastest mirror. This may take a moment..."
fastest_mirror=$(curl -s http://mirrors.ubuntu.com/mirrors.txt | xargs -I {} sh -c 'echo $(curl -r 0-102400 -s -w %{speed_download} -o /dev/null {}/ls-lR.gz) {}' | sort -g -r | head -1 | awk '{ print $2 }')

echo "Fastest mirror found: $fastest_mirror"

# Update sources.list with the fastest mirror, including country-specific mirrors
if [ -f "/etc/apt/sources.list" ]; then
    sed -i.bak -E "s@http://([a-z]{2}\.)?archive\.ubuntu\.com/ubuntu/?@$fastest_mirror@g" /etc/apt/sources.list
    sed -i -E "s@http://security\.ubuntu\.com/ubuntu/?@$fastest_mirror@g" /etc/apt/sources.list
fi

# Update ubuntu.sources with the fastest mirror
if [ -f "/etc/apt/sources.list.d/ubuntu.sources" ]; then
    sed -i.bak -E "s@http://([a-z]{2}\.)?archive\.ubuntu\.com/ubuntu/?@$fastest_mirror@g" /etc/apt/sources.list.d/ubuntu.sources
    sed -i -E "s@http://security\.ubuntu\.com/ubuntu/?@$fastest_mirror@g" /etc/apt/sources.list.d/ubuntu.sources
fi

# 2. Update and Upgrade
print_section "Updating and Upgrading System"
apt update
apt upgrade -y

# 3. Set server timezone
print_section "Setting Server Timezone"
if timedatectl set-timezone "$TIMEZONE"; then
    echo "Timezone set to $TIMEZONE"
else
    echo "Failed to set timezone. Please check if the entered timezone is correct."
    exit 1
fi
echo "Current server time:"
date

# 4. Install essential tools
print_section "Installing essential tools"
install_if_not_exists curl

# 5. Install Docker
print_section "Installing Docker"
if ! command -v docker &> /dev/null; then
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
    usermod -aG docker $SUDO_USER
    rm get-docker.sh
else
    echo "Docker is already installed."
fi

# 6. Install and Configure UFW
print_section "Installing and Configuring UFW"
install_if_not_exists ufw
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp
ufw allow in on lo to any port 53
ufw allow in on lo to any port 61209
echo "y" | ufw enable
ufw reload

# 7. SSH Hardening
print_section "Hardening SSH"
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak
sed -i 's/^#*PermitRootLogin .*/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/^#*PasswordAuthentication .*/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/^#*PubkeyAuthentication .*/PubkeyAuthentication yes/' /etc/ssh/sshd_config
sed -i 's/^#*LoginGraceTime .*/LoginGraceTime 30/' /etc/ssh/sshd_config
sed -i 's/^#*PermitEmptyPasswords .*/PermitEmptyPasswords no/' /etc/ssh/sshd_config
sed -i 's/^#*MaxAuthTries .*/MaxAuthTries 3/' /etc/ssh/sshd_config
sed -i 's/^#*StrictModes .*/StrictModes yes/' /etc/ssh/sshd_config
echo "AllowUsers $SUDO_USER" >> /etc/ssh/sshd_config
systemctl restart ssh

# 8. Install and Configure Fail2Ban
print_section "Installing and Configuring Fail2Ban"
echo "Installing fail2ban. This may take a few minutes..."
DEBIAN_FRONTEND=noninteractive apt install -y fail2ban

echo "Configuring fail2ban..."
cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
cat << EOF > /etc/fail2ban/jail.local
[DEFAULT]
bantime = 1h
findtime = 10m
maxretry = 5

[sshd]
enabled = true
port = 22
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 1d
EOF

echo "Starting and enabling fail2ban service..."
systemctl start fail2ban
systemctl enable fail2ban

echo "Checking fail2ban status..."
systemctl is-active --quiet fail2ban && echo "fail2ban is running" || echo "fail2ban failed to start"

# 9. Configure Automatic Security Updates
print_section "Configuring Automatic Security Updates"
install_if_not_exists unattended-upgrades
echo 'Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}";
    "${distro_id}:${distro_codename}-security";
    "${distro_id}ESMApps:${distro_codename}-apps-security";
    "${distro_id}ESM:${distro_codename}-infra-security";
};
Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "true";
Unattended-Upgrade::Automatic-Reboot-Time "02:00";' > /etc/apt/apt.conf.d/50unattended-upgrades

# 10. Install and Configure OSSEC
print_section "Installing and Configuring OSSEC"
if [ ! -d "/var/ossec" ]; then
    echo "OSSEC is not installed. Installing now..."
    apt install -y build-essential make gcc libevent-dev libpcre2-dev libssl-dev zlib1g-dev libsystemd-dev
    wget https://github.com/ossec/ossec-hids/archive/3.7.0.tar.gz
    tar -xvzf 3.7.0.tar.gz
    cd ossec-hids-3.7.0

    # Use a here-document to provide input to the install script
    ./install.sh << EOF
en

local

n
y
y
n
n
EOF

    cd ..
    rm -rf ossec-hids-3.7.0 3.7.0.tar.gz
else
    echo "OSSEC is already installed."
fi

# Start OSSEC if it's not already running
if [ -f "/var/ossec/bin/ossec-control" ]; then
    /var/ossec/bin/ossec-control start
fi

# 11. Install Logwatch and disable Postfix
print_section "Installing Logwatch and configuring Postfix"

# Pre-configure Postfix to avoid prompts
echo "postfix postfix/main_mailer_type select No configuration" | debconf-set-selections
echo "postfix postfix/mailname string $(hostname -f)" | debconf-set-selections

# Install Postfix and Logwatch non-interactively
DEBIAN_FRONTEND=noninteractive apt-get install -y postfix logwatch

# Disable Postfix
systemctl stop postfix
systemctl disable postfix

# Configure Logwatch to use Slack
cat << EOF > /etc/cron.daily/00logwatch
#!/bin/bash
/usr/sbin/logwatch --output stdout --format text --detail high | /usr/local/bin/slack-notify.sh
EOF

chmod +x /etc/cron.daily/00logwatch

# 12. Set up Glances with Slack Notifications
print_section "Setting up Glances with Slack Notifications"
install_if_not_exists glances

cat << 'EOF' > /usr/local/bin/glances-to-slack.sh
#!/bin/bash

source /etc/slack_config

while true; do
    output=$(glances --stdout-csv cpu.user,mem,load,network_total)
    curl -X POST -H 'Content-type: application/json' --data "{\"text\":\"Glances Report:\n$output\"}" "$SLACK_WEBHOOK_URL"
    sleep 3600  # Send report every hour
done
EOF

chmod +x /usr/local/bin/glances-to-slack.sh

# Create a systemd service for Glances to Slack reporting
cat << EOF > /etc/systemd/system/glances-slack.service
[Unit]
Description=Glances to Slack Reporter
After=network.target

[Service]
ExecStart=/usr/local/bin/glances-to-slack.sh
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable glances-slack.service
systemctl start glances-slack.service

# 13. Install Lynis
print_section "Installing Lynis"
install_if_not_exists lynis

# 14. Set up Slack Notifications
print_section "Setting up Slack Notifications"
echo "SLACK_WEBHOOK_URL=\"$SLACK_WEBHOOK_URL\"" > /etc/slack_config
chmod 600 /etc/slack_config

cat << 'EOF' > /usr/local/bin/slack-notify.sh
#!/bin/bash
source /etc/slack_config
message="$1"
curl -X POST -H 'Content-type: application/json' --data "{\"text\":\"$message\"}" "$SLACK_WEBHOOK_URL"
EOF
chmod +x /usr/local/bin/slack-notify.sh

# 15. Set up Kopia with Backblaze B2
print_section "Setting up Kopia with Backblaze B2"
if ! command -v kopia &> /dev/null; then
    curl -s https://kopia.io/signing-key | gpg --dearmor -o /usr/share/keyrings/kopia-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/kopia-keyring.gpg] http://packages.kopia.io/apt/ stable main" | tee /etc/apt/sources.list.d/kopia.list
    apt update
    apt install kopia -y
else
    echo "Kopia is already installed."
fi

if ! kopia repository status &>/dev/null; then
    echo "Creating Kopia repository..."
    kopia repository create b2 \
        --bucket="$B2_BUCKET_NAME" \
        --key-id="$B2_KEY_ID" \
        --key="$B2_APPLICATION_KEY" \
        --password="$KOPIA_REPOSITORY_PASSPHRASE"
else
    echo "Kopia repository already exists. Connecting..."
    connect_kopia_repository
fi

kopia policy set --global --compression=zstd --keep-latest 30 --keep-hourly 24 --keep-daily 7 --keep-weekly 4 --keep-monthly 12 --keep-annual 3

cat << 'EOF' > /usr/local/bin/kopia-backup.sh
#!/bin/bash

# Source the configuration file
source /etc/vps_config.env

# Function to connect to Kopia repository
connect_kopia_repository() {
    if ! kopia repository status &>/dev/null; then
        echo "Connecting to Kopia repository..."
        kopia repository connect b2 --bucket="$B2_BUCKET_NAME" --key-id="$B2_KEY_ID" --key="$B2_APPLICATION_KEY" --password="$KOPIA_REPOSITORY_PASSPHRASE"
    fi
}

# Ensure connection to Kopia repository
connect_kopia_repository

directories=(
    "/etc"
    "/home"
    "/etc/docker"
    "/root/.docker"
    "/var/lib/docker/volumes"
    "/opt/docker-compose"
    "/opt"
    "/var/log"
    "/etc/easypanel"
)

for dir in "${directories[@]}"; do
    if [ -d "$dir" ] || [ -f "$dir" ]; then
        echo "Backing up $dir..."
        kopia snapshot create "$dir"
        if [ $? -ne 0 ]; then
            echo "Kopia backup failed for: $dir" | /usr/local/bin/slack-notify.sh
        fi
    else
        echo "Directory or file not found: $dir. Skipping backup."
    fi
done

# Backup package list
echo "Backing up package list..."
dpkg --get-selections > /root/package_list.txt
kopia snapshot create /root/package_list.txt

if [ $? -eq 0 ]; then
    echo "Kopia backup to Backblaze B2 completed successfully" | /usr/local/bin/slack-notify.sh
else
    echo "Kopia backup to Backblaze B2 failed" | /usr/local/bin/slack-notify.sh
fi
EOF

chmod +x /usr/local/bin/kopia-backup.sh

# Schedule daily Kopia backup
print_section "Scheduling Daily Kopia Backup"

# Create a temporary file for the cron job
CRON_FILE=$(mktemp)

# Add the cron job to the temporary file
echo "# Daily Kopia backup at 2 AM
0 2 * * * /usr/local/bin/kopia-backup.sh 2>&1 | tee -a /var/log/kopia-backup.log" > "$CRON_FILE"

# Install the new crontab
crontab "$CRON_FILE"

# Remove the temporary file
rm "$CRON_FILE"

echo "Kopia backup scheduled to run daily at 2 AM as root, with output logged to /var/log/kopia-backup.log"

print_section "VPS Hardening Complete"

# Prompt to enable ESM Apps
echo "***"
echo "Enable ESM Apps to receive additional future security updates."
echo "See https://ubuntu.com/esm or run: sudo pro status"
echo "***"
echo "Please review the changes and reboot your system."
