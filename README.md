# AWS Ubuntu GUI VM (Terraform/Terragrunt) + Idempotent Setup/Teardown

This repo provisions an **Ubuntu EC2 VM with GUI via RDP (xRDP + XFCE)** and installs a configurable toolchain:
- Git
- Python (via pyenv)
- Node + npm (via nvm)
- Cursor (Linux AppImage)
- Docker Engine
- AWS CLI v2
- psql (PostgreSQL client)

> Note on **Cursor version pinning**: Cursor provides Linux downloads (.deb/.AppImage), but stable, version-pinned, direct URLs are not consistently documented.
This setup installs Cursor via AppImage and verifies the installed version. If you must pin an exact version, you can replace the downloaded AppImage in `/opt/cursor/`.

## Quick start (Terraform only)

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars (especially allowed_cidr + rdp_password)
terraform init
terraform apply
```

Outputs will include:
- `public_ip`
- `rdp_host` (use with Microsoft Remote Desktop)
- `ssh_command`

## Quick start (Setup script, Terragrunt)

```bash
# AWS
./scripts/setup/setup.sh aws
# later
./scripts/teardown/teardown.sh aws

# GCP
./scripts/setup/setup.sh gcp
./scripts/teardown/teardown.sh gcp
```

**Or use the combined setup-monitor-show-installpost script:**
```bash
# AWS - Setup, monitor installation, install dev tools + GUI tools, and show access info
./scripts/setup-monitor-show-installpost.sh aws

# Teardown and monitor termination
./scripts/teardown-and-monitor.sh aws
```

This script will:
1. Provision the VM infrastructure (Terraform/Terragrunt)
2. Monitor the VM's cloud-init installation progress
3. Install dev tools (Python, Node.js, Docker, AWS CLI, PostgreSQL) and GUI tools (Chrome, Cursor)
4. Display SSH and RDP access information

## RDP
Open Microsoft Remote Desktop and connect to:
- Host: `<public_ip>:3389`
- User: `dev`
- Password: value of `rdp_password`

## Security
- Restrict `allowed_cidr` to your public IP (recommended).
- Consider using an SSM Session Manager pattern instead of opening 3389 to the world.

## Spot / persistence
If you set `use_spot = true`, EC2 Spot interruption behavior is set to **stop** (not terminate), so your **EBS volumes persist** while stopped. You are charged for EBS while stopped. (See AWS docs.) 


## Using your existing `.env` (extract AWS keys safely)

You uploaded/maintain a larger `.env` that includes AWS keys like `AWS_ADMIN_ACCESS_KEY_ID`, `AWS_REGION`, Bedrock IDs, etc. fileciteturn0file0L1-L80

The setup scripts automatically load `.env` files and convert environment variables to Terraform variables. You can:

**Option 1: Use .env directly**
```bash
# Copy and edit the template
cp .env.example .env
# Edit .env with your values, then:
./scripts/setup/setup.sh aws   # or: ./scripts/setup/setup.sh gcp
```

**Option 2: Extract from existing .env**
```bash
# Extract AWS-related variables from your main .env
./scripts/env_tools/generate_aws_env_from_dotenv.sh /path/to/your/.env .env.aws.local
# The setup script will automatically use .env.aws.local
./scripts/setup/setup.sh aws
```

**Option 3: Extract GCP variables**
```bash
# Extract GCP-related variables
./scripts/env_tools/generate_gcp_env_from_dotenv.sh /path/to/your/.env .env.gcp.local
./scripts/setup/setup.sh gcp
```

This keeps secrets out of git history and makes runs repeatable.
A comprehensive template is provided at `.env.example` showing all available configuration options.

## Multi-cloud (AWS + GCP)

Infra is split by cloud:
- `infra/aws/...`
- `infra/gcp/...`

Run:
- AWS: `./scripts/setup/setup.sh aws`
- GCP: `./scripts/setup/setup.sh gcp`

### AWS Authentication (Profile-based)

This project uses AWS profiles for authentication (recommended). Set up AWS profiles before running setup:

1. **Add AWS credentials to `.env`**:
   ```bash
   AWS_ADMIN_ACCESS_KEY_ID=your-access-key-id
   AWS_ADMIN_SECRET_ACCESS_KEY=your-secret-access-key
   AWS_REGION=us-east-1
   AWS_PROFILE=admin
   ```

2. **Run the AWS profile setup script**:
   ```bash
   ./scripts/env_tools/aws/setup-aws-profiles.sh
   ```
   This syncs credentials from `.env` to `~/.aws/credentials` as the `[admin]` profile.

3. **Verify the profile**:
   ```bash
   aws sts get-caller-identity --profile admin
   ```

Terraform will automatically use the `AWS_PROFILE` environment variable to authenticate with AWS.

### GCP Authentication

GCP auth (recommended):
- `gcloud auth application-default login`
Or set `GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json`.
