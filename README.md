# Ubuntu 24.04 VPS Hardening Guide

This guide provides an automated script for hardening an Ubuntu 24.04 VPS. The script implements various security measures to enhance the protection of your server.

## Table of Contents
1. [Introduction](#introduction)
2. [Prerequisites](#prerequisites)
3. [What the Script Does](#what-the-script-does)
4. [Configuration](#configuration)
5. [Post-Installation Steps](#post-installation-steps)
6. [Maintenance](#maintenance)
7. [Troubleshooting](#troubleshooting)

## Introduction

This project aims to automate the process of hardening a Ubuntu 24.04 VPS. It implements best practices for server security, including firewall configuration, intrusion detection, automatic updates, and secure backups. [Quick start guide &rarr;](https://medium.com/@hirefrank/you-can-do-hard-things-hardening-your-vps-e838af7dc3c9)


## Prerequisites

- A fresh Ubuntu 24.04 VPS (I used Minimal LTS but the full version should work too)
- Root or sudo access to the server (I found [Netcup's Root VPS](https://www.netcup.com/en/server/root-server?ref=244817) to be the best value for money)
- Basic knowledge of Linux command line
- A Slack workspace with a webhook URL
- Backblaze B2 credentials (Any S3-compatible storage should work with minor modifications)

## What the Script Does

The `configure.sh` script automates the following hardening measures:

1. **System Updates**: Ensures the system is up-to-date with the latest security patches.

2. **Firewall Configuration**: Sets up and configures UFW (Uncomplicated Firewall) to restrict incoming traffic.

3. **SSH Hardening**: Enhances SSH security by disabling root login, using key-based authentication, and other best practices.

4. **Fail2Ban**: Installs and configures Fail2Ban to protect against brute-force attacks.

5. **Automatic Security Updates**: Sets up unattended-upgrades for automatic security updates.

6. **OSSEC**: Installs and configures OSSEC, a Host-based Intrusion Detection System (HIDS).

7. **Logwatch**: Installs Logwatch for log analysis and reporting.

8. **System Monitoring**: Sets up Glances for system monitoring with Slack notifications.

9. **Security Auditing**: Installs Lynis for periodic security audits.

10. **Backups**: Configures Kopia for secure, encrypted backups to Backblaze B2.

11. **Time Synchronization**: Ensures the system clock is accurately set and maintained.

12. **Repository Optimization**: Selects the fastest mirror for package downloads.

## Configuration

Before running the script, edit the `vps_config.env` file to include your specific settings:

- Timezone
- Slack webhook URL for notifications
- Backblaze B2 credentials for backups
- Kopia repository passphrase

## Post-Installation Steps

After running the script:

1. Review the changes made to your system.
2. Set up SSH key-based authentication if not already configured.
3. Reboot the system to ensure all changes take effect.

## Maintenance

- Regularly review system logs and Slack notifications.
- Periodically run Lynis for security audits: `sudo lynis audit system`
- Keep the system updated: `sudo apt update && sudo apt upgrade`
- Verify backup integrity regularly using Kopia.

## Troubleshooting

If you encounter issues:

1. Check the script output for error messages.
2. Review system logs: `sudo journalctl -xe`
3. Ensure all prerequisites are met and the configuration file is correctly set up.
4. For persistent issues, please open an issue in this repository.

---

This script significantly enhances your VPS security, but remember that security is an ongoing process. Stay informed about the latest security practices and keep your system updated.