# RDP Connection Information

## Current Status

**VM IP Address:** `34.205.29.132`  
**RDP Port:** `3389`  
**RDP Host:** `34.205.29.132:3389`

## Login Credentials

**Username:** `dev`  
**Password:** (Set in your `.env` file as `RDP_PASSWORD` or via `TF_VAR_rdp_password`)

The user `dev` has:
- SSH access (via `ubuntu` user initially)
- RDP access (via `dev` user)
- `sudo` privileges (can run `sudo` commands)

## How to Connect via RDP

### macOS
1. Open Microsoft Remote Desktop from the App Store (or use any RDP client)
2. Click "Add PC" or "Add Desktop"
3. Enter:
   - **PC name:** `34.205.29.132`
   - **User account:** `dev`
   - **Password:** (from your `.env` file)
4. Click "Add" and connect

### Windows
1. Press `Win + R`, type `mstsc`, press Enter
2. Enter:
   - **Computer:** `34.205.29.132`
   - **Username:** `dev`
3. Click "Connect"
4. Enter the password when prompted

### Linux
```bash
# Using Remmina
remmina rdp://dev@34.205.29.132:3389

# Or using rdesktop
rdesktop -u dev -p <password> 34.205.29.132:3389

# Or using freerdp
xfreerdp /u:dev /p:<password> /v:34.205.29.132
```

## Installation Status

**Current Status:** Installation in progress (cloud-init may still be running)

**Installed:**
- ✅ Git (version 2.34.1)
- ✅ Python 3.10.12
- ✅ xRDP service (running)
- ✅ XFCE Desktop Environment

**Pending Installation:**
- ⏳ Node.js (via nvm)
- ⏳ npm
- ⏳ Docker
- ⏳ AWS CLI v2
- ⏳ PostgreSQL client
- ⏳ Cursor IDE

## Monitor Installation Progress

To monitor the installation in real-time:

```bash
./scripts/monitor/monitor-installation.sh aws
```

Or manually check via SSH:

```bash
# Check cloud-init status
ssh -i ~/.ssh/auto_clouds/ubuntu-gui-key.pem ubuntu@34.205.29.132 'cloud-init status'

# View installation logs
ssh -i ~/.ssh/auto_clouds/ubuntu-gui-key.pem ubuntu@34.205.29.132 'tail -f /var/log/cloud-init-output.log'

# Check if installation is complete
ssh -i ~/.ssh/auto_clouds/ubuntu-gui-key.pem ubuntu@34.205.29.132 'test -f /var/local/bootstrap_done_v1 && echo "Complete" || echo "In Progress"'
```

## Verify Installed Tools

After installation completes, verify tools via SSH:

```bash
ssh -i ~/.ssh/auto_clouds/ubuntu-gui-key.pem ubuntu@34.205.29.132

# Then run:
git --version
python3 --version
node --version
npm --version
docker --version
aws --version
psql --version
cursor --version
```

## Troubleshooting

### RDP Connection Issues

1. **Firewall:** Ensure your security group allows inbound traffic on port `3389` from your IP
2. **Service Status:** xRDP should be running. Check via SSH:
   ```bash
   ssh -i ~/.ssh/auto_clouds/ubuntu-gui-key.pem ubuntu@34.205.29.132 'sudo systemctl status xrdp'
   ```
3. **Password:** Ensure `RDP_PASSWORD` is set correctly in your `.env` file

### Installation Not Complete

If tools are still installing:
- Wait for cloud-init to finish (typically 10-15 minutes)
- Monitor logs: `./scripts/monitor/monitor-installation.sh aws`
- Check cloud-init status: `ssh ... 'cloud-init status'`

## Next Steps

1. Wait for installation to complete (check with monitor script)
2. Connect via RDP using credentials above
3. Once logged in, verify all tools are installed and working
4. The desktop environment (XFCE) should be available immediately

