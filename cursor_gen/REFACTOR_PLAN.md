# Refactor Plan: Environment Variable Integration

## Issues Identified

### 1. **Terraform Variables Not Reading from .env**
   - **Problem**: Terraform variables have hardcoded defaults and don't read from environment variables
   - **Impact**: Users must manually edit `terraform.tfvars` even when `.env` is properly configured
   - **Location**: 
     - `infra/aws/terraform/variables.tf` - `aws_region` doesn't read from `AWS_REGION`
     - `infra/gcp/terraform/variables.tf` - `project_id`, `region`, `zone` don't read from `GCP_PROJECT_ID`, `GCP_REGION`, `GCP_ZONE`

### 2. **Setup Scripts Don't Pass Env Vars to Terraform**
   - **Problem**: `setup.sh` and `teardown.sh` load `.env` files but don't convert them to `TF_VAR_*` format
   - **Impact**: Environment variables are loaded but Terraform doesn't see them
   - **Location**: `scripts/setup.sh`, `scripts/teardown.sh`

### 3. **Missing .env.example Template**
   - **Problem**: No template showing what variables should be in `.env`
   - **Impact**: Users don't know what to put in their `.env` file
   - **Location**: Root directory

### 4. **generate_aws_env_from_dotenv.sh Issues**
   - **Problem**: Creates `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` but they're commented out
   - **Impact**: Confusing output, variables not actually exported
   - **Location**: `scripts/generate_aws_env_from_dotenv.sh` lines 47-52

### 5. **GCP Environment Variable Extraction**
   - **Problem**: `generate_gcp_env_from_dotenv.sh` is minimal and may miss variables
   - **Impact**: GCP deployment may not work properly with `.env` file
   - **Location**: `scripts/generate_gcp_env_from_dotenv.sh`

### 6. **Inconsistent Variable Naming**
   - **Problem**: AWS uses `AWS_REGION` but Terraform expects `var.aws_region` (no automatic mapping)
   - **Impact**: Manual conversion needed
   - **Solution**: Use Terraform's `TF_VAR_*` convention or update variable defaults

## Refactor Solutions

### Solution 1: Update Terraform Variables to Read from Environment
- Modify `variables.tf` files to use `TF_VAR_*` convention OR
- Update defaults to read from environment variables using `coalesce()` or locals

### Solution 2: Update Setup Scripts to Export TF_VAR_* Variables
- After loading `.env`, export variables as `TF_VAR_*` format
- Map common env vars: `AWS_REGION` → `TF_VAR_aws_region`, etc.

### Solution 3: Create .env.example Template
- Document all required and optional variables
- Include examples for both AWS and GCP

### Solution 4: Fix generate_aws_env_from_dotenv.sh
- Uncomment and properly format `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`
- Remove confusing comments

### Solution 5: Enhance GCP Environment Script
- Ensure all GCP variables are properly extracted
- Match the quality of AWS script

## Implementation Priority

1. **High Priority**: Fix Terraform variable defaults (Solution 1)
2. **High Priority**: Update setup scripts (Solution 2)
3. **Medium Priority**: Create .env.example (Solution 3)
4. **Medium Priority**: Fix generate scripts (Solutions 4 & 5)

