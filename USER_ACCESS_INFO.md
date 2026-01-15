# User Access Information

## SSH Access

### Default User: `ubuntu`

**Why can you use 'ubuntu' as the user?**

The `ubuntu` user is the **default user created by AWS Ubuntu AMIs**. This user:
- Comes pre-configured on all AWS Ubuntu EC2 instances
- Has SSH access via the EC2 key pair (the `.pem` file)
- Has `sudo` privileges by default
- Is automatically configured when AWS provisions the instance

Your user_data script creates a **separate user** (`dev_admin` based on your `.env` file) for:
- RDP access (remote desktop)
- Custom development work
- This user also has `sudo` privileges (added by the script)

### SSH Connection

```bash
# Connect as the default 'ubuntu' user
ssh -i ~/.ssh/auto_clouds/ubuntu-gui-key.pem ubuntu@<instance-ip>

# Or connect as your custom dev user (after it's created)
ssh -i ~/.ssh/auto_clouds/ubuntu-gui-key.pem dev_admin@<instance-ip>
```

**Note:** The `ubuntu` user works immediately because it's part of the AMI. The `dev_admin` user is created by your user_data script, so it may not exist immediately after instance launch (though it's created very early in the bootstrap process).

## RDP Access

### User: `dev_admin` (or whatever you set as `DEV_USERNAME` in `.env`)

**Connection Details:**
- **Host/IP:** `<instance-public-ip>:3389`
- **Username:** `dev_admin` (from your `.env` file: `DEV_USERNAME=dev_admin`)
- **Password:** Value of `RDP_PASSWORD` from your `.env` file

**How to Connect:**
- **macOS:** Microsoft Remote Desktop → Add PC → `instance-ip` → User: `dev_admin`
- **Windows:** `mstsc` → Computer: `instance-ip` → User: `dev_admin`
- **Linux:** `remmina rdp://dev_admin@instance-ip:3389`

## User Differences

| User | Created By | Purpose | SSH Key Access | RDP Access | Sudo Access |
|------|------------|---------|----------------|------------|-------------|
| `ubuntu` | AWS AMI | Default system user | ✅ Yes (via EC2 key pair) | ❌ No | ✅ Yes |
| `dev_admin` | user_data script | Development/RDP user | ✅ Yes (if key added) | ✅ Yes (password-based) | ✅ Yes |

## Notes

1. **Two Users, Two Purposes:**
   - `ubuntu` = System administration via SSH
   - `dev_admin` = Development work and RDP access

2. **SSH Key Access:**
   - The EC2 key pair (`.pem` file) grants access to the `ubuntu` user automatically
   - The `dev_admin` user can also use SSH with the same key if you configure it (the script doesn't currently do this, but you can add it manually)

3. **RDP Password:**
   - Only `dev_admin` has an RDP password set (required for RDP protocol)
   - The `ubuntu` user doesn't have a password set (SSH-only access)

4. **Sudo Access:**
   - Both users have `sudo` privileges
   - `ubuntu` has it by default (AWS AMI)
   - `dev_admin` gets it from the user_data script: `usermod -aG sudo "${DEV_USER}"`

## Common Issues

### "pyenv: cannot rehash: /opt/pyenv/shims isn't writable"

This warning appears because pyenv is installed system-wide in `/opt/pyenv`, but the `ubuntu` user's home directory may not have write access to pyenv's shim directory. This is harmless - Python will still work. To fix it, you can:

```bash
# Option 1: Make pyenv shims writable (if needed)
sudo chmod -R g+w /opt/pyenv/shims

# Option 2: Use the dev_admin user instead (which may have proper permissions)
# Or use pyenv via the dev_admin user
```

### Switching Between Users

If you want to switch to the `dev_admin` user while logged in as `ubuntu`:

```bash
# Switch user
sudo su - dev_admin

# Or just run a command as dev_admin
sudo -u dev_admin bash -l
```

