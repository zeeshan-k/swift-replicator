# Storage Replication Monitor

A Ruby script for monitoring bidirectional storage replication between two regions (A and B).

## Overview

This tool monitors storage replication between two regions where:
- Region A replicates data to Region B
- Region B replicates data to Region A (vice versa)

The script checks replication status, identifies missing or stale objects, and provides health reports.

**Supported Storage Services:**
- ✅ OpenStack Swift Object Storage
- ✅ AWS S3 (generic implementation)
- ✅ Azure Blob Storage (generic implementation) 
- ✅ Google Cloud Storage (generic implementation)
- ✅ Any S3-compatible storage (generic implementation)

## Architecture

### Data Objects

The project uses several Ruby classes to model the replication system:

1. **`Region`** - Represents a storage region with:
   - Configuration (name, endpoint, credentials)
   - Storage client interface
   - Methods to list objects and check replication status

2. **`ReplicationMonitor`** - Core monitoring logic that:
   - Manages replication pairs (source -> target relationships)
   - Checks replication status between regions
   - Calculates sync percentages and identifies issues
   - Provides summary reports

3. **`StorageClient`** - Handles storage API interactions:
   - Lists objects in storage
   - Checks object existence and metadata
   - Provides health check capabilities
   - Currently includes mock data for testing (replace with real API calls)

## Features

- ✅ Bidirectional replication monitoring
- ✅ Object sync percentage calculations
- ✅ Stale object detection (replication lag)
- ✅ Health status classification (healthy/warning/critical/error)
- ✅ Detailed issue reporting
- ✅ Environment variable configuration
- ✅ Mock data for testing

## Configuration

### OpenStack Swift Configuration

Set environment variables for OpenStack Object Storage:

```bash
# Storage type
export STORAGE_TYPE="openstack"

# Region A (OpenStack Swift)
export REGION_A_NAME="region-a"
export REGION_A_SWIFT_ENDPOINT="https://swift.region-a.example.com:8080"
export REGION_A_AUTH_URL="https://keystone.region-a.example.com:5000/v3"
export REGION_A_USERNAME="your_username"
export REGION_A_PASSWORD="your_password"
export REGION_A_PROJECT_NAME="your_project"
export REGION_A_DOMAIN_NAME="default"

# Region B (OpenStack Swift)
export REGION_B_NAME="region-b"
export REGION_B_SWIFT_ENDPOINT="https://swift.region-b.example.com:8080"
export REGION_B_AUTH_URL="https://keystone.region-b.example.com:5000/v3"
export REGION_B_USERNAME="your_username"
export REGION_B_PASSWORD="your_password"
export REGION_B_PROJECT_NAME="your_project"
export REGION_B_DOMAIN_NAME="default"
```

### Generic Storage Configuration

For AWS S3, Azure Blob, GCP Cloud Storage, or other S3-compatible services:

```bash
# Storage type (default)
export STORAGE_TYPE="generic"

# Region A credentials
export REGION_A_ACCESS_KEY="your_access_key"
export REGION_A_SECRET_KEY="your_secret_key"

# Region B credentials  
export REGION_B_ACCESS_KEY="your_access_key"
export REGION_B_SECRET_KEY="your_secret_key"
```

### Optional Settings

```bash
# Enable debug output
export DEBUG="true"
```

## Usage

Run the replication monitor:

```bash
ruby replication_monitor.rb
```

Example output:
```
Storage Replication Monitor - 2025-08-22 10:30:00
==================================================

region-a -> region-b:
  Status: warning
  Last Sync: 2025-08-22 09:45:00
  Objects in Sync: 42/50
  Issues:
    - 8 objects not replicated (16.0% missing)
    - 2 objects may be stale in target region

region-b -> region-a:
  Status: healthy
  Last Sync: 2025-08-22 10:15:00
  Objects in Sync: 38/38

==================================================
Summary: 1/2 replication pairs are healthy
```

## Customization

### Integrating with Real Storage Services

Replace the mock implementation in `StorageClient` with actual API calls for your storage service:

- **AWS S3**: Use AWS SDK with S3 client
- **Azure Blob Storage**: Use Azure SDK  
- **Google Cloud Storage**: Use Google Cloud SDK
- **Other services**: Implement HTTP API calls

### Health Thresholds

Modify the health status thresholds in `ReplicationMonitor#determine_replication_status`:

- **Healthy**: ≥95% objects in sync (default)
- **Warning**: 80-94% objects in sync  
- **Critical**: <80% objects in sync

### Staleness Detection

Adjust the staleness threshold in `ReplicationMonitor#stale_object?`:

- Current default: Objects older than 1 hour in target region
- Modify `time_diff > 3600` to change threshold

## Files

- `replication_monitor.rb` - Main script entry point
- `lib/region.rb` - Region data model and operations
- `lib/replication_monitor.rb` - Core monitoring logic
- `lib/storage_client.rb` - Generic storage service client interface
- `lib/openstack_storage_client.rb` - OpenStack Swift-specific client

## OpenStack Swift Features

The OpenStack integration provides:

- ✅ Keystone v3 authentication
- ✅ Token management with automatic renewal
- ✅ Container operations (Swift equivalent of buckets)
- ✅ Object listing, metadata retrieval, and existence checks
- ✅ Health monitoring with Swift cluster info
- ✅ Support for multi-tenant projects and domains

### OpenStack Authentication Flow

1. Authenticates with Keystone using username/password
2. Retrieves auth token and expiration time
3. Automatically renews tokens before expiry
4. Uses tokens for all Swift API operations

## Exit Codes

- `0` - All replication pairs are healthy
- `1` - One or more replication pairs have issues or errors occurred

## Requirements

- Ruby 2.7 or higher
- Network access to storage endpoints
- Valid storage service credentials

### Installing Ruby on Windows

1. Download Ruby from [rubyinstaller.org](https://rubyinstaller.org/)
2. Install Ruby with DevKit
3. Restart your terminal
4. Verify installation: `ruby --version`

### Required Gems (if using real API calls)

```bash
# For OpenStack Swift (if extending beyond mock)
gem install fog-openstack

# For AWS S3 (if extending beyond mock)  
gem install aws-sdk-s3

# For HTTP requests (already using built-in net/http)
# No additional gems required for the current implementation
```
