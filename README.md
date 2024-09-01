# Ubuntu 24.04 VPS Hardening Guide

This guide summarizes the steps to harden an Ubuntu 24.04 VPS, including an automated script for the process.

## Table of Contents
1. [Update and Upgrade](#1-update-and-upgrade)
2. [Firewall Configuration (UFW)](#2-firewall-configuration-ufw)
3. [SSH Hardening](#3-ssh-hardening)
4. [Fail2Ban Installation and Configuration](#4-fail2ban-installation-and-configuration)
5. [Automatic Security Updates](#5-automatic-security-updates)
6. [OSSEC Installation and Configuration](#6-ossec-installation-and-configuration)
7. [Logwatch and Slack Notifications](#7-logwatch-and-slack-notifications)
8. [Glances with Slack Notifications](#8-glances-with-slack-notifications)
9. [Lynis Security Audit](#9-lynis-security-audit)
10. [Kopia Backup System with Backblaze B2](#10-kopia-backup-system-with-backblaze-b2)
11. [Regular Maintenance](#11-regular-maintenance)
12. [Automated Configuration Script](#12-automated-configuration-script)
13. [Using the Configuration File](#13-using-the-configuration-file)

## 1. Update and Upgrade

```bash
sudo apt update && sudo apt upgrade -y
```

## 2. Firewall Configuration (UFW)

```bash
sudo apt install ufw
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 22/tcp
sudo ufw allow in on lo to any port 53
sudo ufw allow in on lo to any port 61209
sudo ufw enable
sudo ufw reload
```

## 3. SSH Hardening

Edit `/etc/ssh/sshd_config`:

```
PermitRootLogin no
PubkeyAuthentication yes
PasswordAuthentication no
AllowUsers yourusername
LoginGraceTime 30
PermitEmptyPasswords no
MaxAuthTries 3
StrictModes yes
```

Restart SSH: `sudo systemctl restart ssh`

### SSH Login Notifications

Create a script at `/etc/ssh/login-notify.sh`:

```bash
#!/bin/bash
SUBJECT="SSH Login: $PAM_USER from $PAM_RHOST"
BODY="
User: $PAM_USER
User IP: $PAM_RHOST
Service: $PAM_SERVICE
TTY: $PAM_TTY
Date: $(date)
Server: $(hostname)
"
echo "$SUBJECT\n\n$BODY" | /usr/local/bin/slack-notify.sh
```

Make it executable:

```bash
sudo chmod +x /etc/ssh/login-notify.sh
```

Add to SSH's PAM configuration (`/etc/pam.d/sshd`):

```
session optional pam_exec.so /etc/ssh/login-notify.sh
```

## 4. Fail2Ban Installation and Configuration

```bash
sudo apt install fail2ban
sudo cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
```

Edit `/etc/fail2ban/jail.local`:

```ini
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
```

Start and enable Fail2Ban:

```bash
sudo systemctl start fail2ban
sudo systemctl enable fail2ban
```

## 5. Automatic Security Updates

```bash
sudo apt install unattended-upgrades
sudo dpkg-reconfigure --priority=low unattended-upgrades
```

Edit `/etc/apt/apt.conf.d/50unattended-upgrades`:

```
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}";
    "${distro_id}:${distro_codename}-security";
    "${distro_id}ESMApps:${distro_codename}-apps-security";
    "${distro_id}ESM:${distro_codename}-infra-security";
};

Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "true";
Unattended-Upgrade::Automatic-Reboot-Time "02:00";
```

## 6. OSSEC Installation and Configuration

```bash
sudo apt install build-essential make gcc libevent-dev libpcre2-dev libssl-dev zlib1g-dev libsystemd-dev
wget https://github.com/ossec/ossec-hids/archive/3.7.0.tar.gz
tar -xvzf 3.7.0.tar.gz
cd ossec-hids-3.7.0
sudo ./install.sh
```

Configure OSSEC to use Slack for notifications by editing `/var/ossec/etc/ossec.conf`.

## 7. Logwatch and Slack Notifications

Install Logwatch:

```bash
sudo apt install logwatch
```

Create a Slack notification script at `/usr/local/bin/slack-notify.sh`:

```bash
#!/bin/bash

# Source the Slack webhook URL
source /etc/slack_config

# Function to send message to Slack
send_to_slack() {
    local message="$1"
    curl -X POST -H 'Content-type: application/json' --data "{\"text\":\"$message\"}" "$SLACK_WEBHOOK_URL"
}

# Read from stdin (for piping)
if [ -p /dev/stdin ]; then
    message=$(cat -)
    send_to_slack "$message"
else
    echo "No input provided"
    exit 1
fi
```

Make it executable:

```bash
sudo chmod +x /usr/local/bin/slack-notify.sh
```

Configure Logwatch to use Slack by editing `/etc/cron.daily/00logwatch`:

```bash
#!/bin/bash
/usr/sbin/logwatch --output stdout --format text --detail high | /usr/local/bin/slack-notify.sh
```

## 8. Glances with Slack Notifications

Install Glances:

```bash
sudo apt install glances
```

Create a script to send Glances data to Slack at `/usr/local/bin/glances-to-slack.sh`:

```bash
#!/bin/bash

source /etc/slack_config

while true; do
    output=$(glances --stdout-csv cpu.user,mem,load,network_total)
    curl -X POST -H 'Content-type: application/json' --data "{\"text\":\"Glances Report:\n$output\"}" "$SLACK_WEBHOOK_URL"
    sleep 3600  # Send report every hour
done
```

Make it executable:

```bash
sudo chmod +x /usr/local/bin/glances-to-slack.sh
```

Set up a systemd service for this script by creating `/etc/systemd/system/glances-slack.service`:

```
[Unit]
Description=Glances to Slack Reporter
After=network.target

[Service]
ExecStart=/usr/local/bin/glances-to-slack.sh
Restart=always

[Install]
WantedBy=multi-user.target
```

Enable and start the service:

```bash
sudo systemctl enable glances-slack.service
sudo systemctl start glances-slack.service
```

## 9. Lynis Security Audit

Install Lynis:

```bash
sudo apt install lynis
```

Run a system audit:

```bash
sudo lynis audit system
```

Consider setting up a cron job to run Lynis regularly and send results to Slack.

## 10. Kopia Backup System with Backblaze B2

### Installation

1. Download and install Kopia:

```bash
curl -s https://kopia.io/signing-key | sudo gpg --dearmor -o /usr/share/keyrings/kopia-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/kopia-keyring.gpg] http://packages.kopia.io/apt/ stable main" | sudo tee /etc/apt/sources.list.d/kopia.list
sudo apt update
sudo apt install kopia
```

### Configuration with Backblaze B2

2. Create a Backblaze B2 bucket for your backups.

3. Create a repository in Backblaze B2 (replace placeholders with your actual values):

```bash
kopia repository create b2 \
    --bucket=your-bucket-name \
    --key-id=your-key-id \
    --key=your-application-key
```

4. Set a repository password when prompted.

5. Create a backup policy:

```bash
kopia policy set --global --compression=zstd --keep-latest 30 --keep-hourly 24 --keep-daily 7 --keep-weekly 4 --keep-monthly 12 --keep-annual 3
```

### Backup Recommendations

Here are key directories and files to consider backing up:

1. Configuration files:
   ```bash
   kopia snapshot create /etc
   ```

2. User home directories:
   ```bash
   kopia snapshot create /home
   ```

3. Docker configurations (excluding images):
   ```bash
   kopia snapshot create /etc/docker
   kopia snapshot create /root/.docker
   ```

4. Docker volumes:
   ```bash
   kopia snapshot create /var/lib/docker/volumes
   ```

5. Docker Compose files (if stored in a specific directory, e.g., /opt/docker-compose):
   ```bash
   kopia snapshot create /opt/docker-compose
   ```

6. Custom application data:
   ```bash
   kopia snapshot create /opt
   ```

7. System logs:
   ```bash
   kopia snapshot create /var/log
   ```

8. Installed packages list:
   ```bash
   dpkg --get-selections > /root/package_list.txt
   kopia snapshot create /root/package_list.txt
   ```

Note: Docker images are not included in the backup. If you need to backup specific images, consider pushing them to a container registry.

### Automating Backups

6. Create a backup script at `/usr/local/bin/kopia-backup.sh`:

```bash
#!/bin/bash

source /etc/slack_config

directories=(
    "/etc"
    "/home"
    "/etc/docker"
    "/root/.docker"
    "/var/lib/docker/volumes"
    "/opt/docker-compose"
    "/opt"
    "/var/log"
)

for dir in "${directories[@]}"; do
    kopia snapshot create "$dir"
    if [ $? -ne 0 ]; then
        /usr/local/bin/slack-notify.sh "Kopia backup failed for directory: $dir"
    fi
done

dpkg --get-selections > /root/package_list.txt
kopia snapshot create /root/package_list.txt

if [ $? -eq 0 ]; then
    /usr/local/bin/slack-notify.sh "Kopia backup to Backblaze B2 completed successfully"
else
    /usr/local/bin/slack-notify.sh "Kopia backup to Backblaze B2 failed"
fi
```

7. Make the script executable:

```bash
sudo chmod +x /usr/local/bin/kopia-backup.sh
```

8. Set up a cron job to run the backup daily:

```bash
sudo crontab -e
```

Add the following line:

```
0 2 * * * /usr/local/bin/kopia-backup.sh
```

This will run the backup every day at 2 AM.

### Restoring from Backup

To restore a file or directory:

```bash
kopia snapshot restore <snapshot-id>:/path/to/file /path/to/restore
```

Replace `<snapshot-id>` with the ID of the snapshot you want to restore from.

### Maintenance

- Regularly verify the integrity of your backups:

```bash
kopia snapshot verify --all
```

- Periodically check the repository for errors:

```bash
kopia repository validate-provider
```

Remember to replace placeholder values with your actual Backblaze B2 credentials and bucket name.

## 11. Regular Maintenance

- Regularly update and upgrade your system
- Monitor Slack notifications for security events
- Periodically review and adjust security configurations
- Keep backups of important data and configurations
- Regularly review Lynis audit results and address any issues

## 12. Automated Configuration Script

This repository includes a bash script named `configure.sh` that automates the VPS hardening and configuration process. The script implements all the hardening steps described in this README.

To use the script:

1. Download the script:
   ```
   wget https://raw.githubusercontent.com/your-repo/configure.sh
   ```

2. Make the script executable:
   ```
   chmod +x configure.sh
   ```

3. Run the script as root:
   ```
   sudo ./configure.sh
   ```

The script will use the configuration file to set up your VPS according to the steps outlined in this guide.

Remember to review the script and understand each step before running it on your production server. It's recommended to test it in a safe environment first.

## 13. Using the Configuration File

The `configure.sh` script uses a configuration file to read input values. This makes it easier to automate the process and keep your settings consistent. Here's how to use it:

1. Copy the configuration template:
   ```
   cp vps_config.template vps_config.env
   ```

2. Edit the configuration file and fill in your values:
   ```
   nano vps_config.env
   ```

3. Run the script as before:
   ```
   sudo ./configure.sh
   ```

Make sure `vps_config.env` and `configure.sh` are in the same directory when you run the script.

**Important:** Keep your `vps_config.env` file secure, as it contains sensitive information. Do not commit it to version control or share it publicly.

## Conclusion

By following these steps and using the provided script, you can significantly enhance the security of your Ubuntu 24.04 VPS. Remember that security is an ongoing process, and it's important to stay informed about new vulnerabilities and best practices.

For any questions, issues, or contributions, please open an issue or pull request in this repository.

Stay secure!