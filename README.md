# Storage Replication Monitor

A Ruby script for monitoring bidirectional storage replication between two regions (A and B).

**Repository:** swift-replicator  
**Current Development Branch:** zeeshan  
**Owner:** Zeeshan Khan

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

## Project Structure

```
swift-replicator/
├── replication_monitor.rb          # Main entry point
├── config.yaml                     # Configuration file
├── demo_stdin_method.rb            # Demo script for advanced usage
├── lib/
│   ├── replication_monitor.rb      # Core monitoring logic
│   ├── region.rb                   # Region data model
│   ├── storage_client.rb           # Generic storage interface
│   └── openstack_storage_client.rb # OpenStack Swift client
├── README.md                       # This documentation
└── LICENSE                         # Project license
```

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
- ✅ YAML configuration file support
- ✅ Command-line argument parsing
- ✅ Mock data for testing
- ✅ Advanced configuration methods (stdin, in-memory operations)
- ✅ Security-focused configuration handling

## Configuration

The project supports two configuration methods:

1. **Environment Variables** (runtime configuration)
2. **YAML Configuration File** (persistent configuration)

### Method 1: Environment Variables

#### OpenStack Swift Configuration

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

### Method 2: YAML Configuration File

You can also use the provided `config.yaml` file for persistent configuration:

```yaml
# Storage Replication Monitor Configuration
storage_type: openstack

regions:
  region_a:
    name: "region-a"
    endpoint: "https://swift.region-a.example.com:8080"
    storage_type: "openstack"
    credentials:
      auth_url: "https://keystone.region-a.example.com:5000/v3"
      username: "monitoring_user"
      password: "secure_password"
      project_name: "storage_project"
      domain_name: "default"
  
  region_b:
    name: "region-b"
    endpoint: "https://swift.region-b.example.com:8080"
    storage_type: "openstack"
    credentials:
      auth_url: "https://keystone.region-b.example.com:5000/v3"
      username: "monitoring_user"
      password: "secure_password"
      project_name: "storage_project"
      domain_name: "default"

monitoring:
  health_thresholds:
    healthy: 95.0    # >= 95% sync rate
    warning: 80.0    # 80-94% sync rate
    critical: 0.0    # < 80% sync rate
  
  staleness_threshold: 3600  # seconds (1 hour)
  
  containers:
    - "primary-data"
    - "backup-data"
    - "shared-configs"

notifications:
  enabled: false
  email: "admin@example.com"
  webhook: "https://monitoring.example.com/webhook"
```

## Usage

### Basic Usage

Run the replication monitor:

```bash
ruby replication_monitor.rb
```

### Advanced Usage with Configuration

Run with YAML configuration file:

```bash
ruby replication_monitor.rb --config config.yaml
```

Run with environment variables (see Configuration section):

```bash
ruby replication_monitor.rb
```

### Demo and Testing

The project includes a demonstration script that shows advanced configuration techniques:

```bash
ruby demo_stdin_method.rb
```

This demo script showcases:
- Passing YAML configuration via stdin (Method 3)
- In-memory operations without filesystem writes
- OpenStack Swift operations with memory-only transfers
- Security benefits of avoiding temporary files

### Method 3: Advanced Configuration for Automation

The project supports advanced configuration methods ideal for automation scenarios:

#### Using stdin Configuration in Automation

**Cron Job Example:**
```bash
# /etc/crontab or crontab -e
# Check replication every 15 minutes using stdin config
*/15 * * * * /usr/bin/ruby /path/to/replication_monitor.rb < /secure/config.yaml 2>&1 | logger -t replication-monitor

# Or using environment variables (set in crontab or system-wide)
# First, set environment variables in crontab:
STORAGE_TYPE=openstack
REGION_A_NAME=region-a
REGION_A_SWIFT_ENDPOINT=https://swift.region-a.example.com:8080
REGION_A_AUTH_URL=https://keystone.region-a.example.com:5000/v3
REGION_A_USERNAME=monitoring_user
REGION_A_PASSWORD=secure_password_here
REGION_A_PROJECT_NAME=storage_project
REGION_B_NAME=region-b
REGION_B_SWIFT_ENDPOINT=https://swift.region-b.example.com:8080
REGION_B_AUTH_URL=https://keystone.region-b.example.com:5000/v3
REGION_B_USERNAME=monitoring_user
REGION_B_PASSWORD=secure_password_here
REGION_B_PROJECT_NAME=storage_project

# Then run the monitoring script (environment variables are automatically used)
*/15 * * * * cd /path/to/swift-replicator && /usr/bin/ruby replication_monitor.rb 2>&1 | logger -t replication-monitor
```

**CI/CD Pipeline Example (GitHub Actions, Jenkins, etc.):**
```bash
# Generate config dynamically and pass via stdin
echo "$MONITORING_CONFIG_YAML" | ruby replication_monitor.rb --stdin

# Or use environment variables (more secure for CI/CD)
export STORAGE_TYPE="openstack"
export REGION_A_NAME="$PROD_REGION_A"
export REGION_A_SWIFT_ENDPOINT="$PROD_ENDPOINT_A"
# ... other env vars
ruby replication_monitor.rb
```

**Docker Container Example:**
```dockerfile
# Dockerfile
FROM ruby:3.0-alpine
COPY . /app
WORKDIR /app
CMD ["ruby", "replication_monitor.rb"]
```

```bash
# Run with stdin config
docker run -i swift-replicator < config.yaml

# Run with environment variables
docker run -e STORAGE_TYPE=openstack -e REGION_A_NAME=east swift-replicator
```

**Kubernetes CronJob Example:**
```yaml
# k8s-cronjob.yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: replication-monitor
spec:
  schedule: "*/15 * * * *"  # Every 15 minutes
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: monitor
            image: swift-replicator:latest
            env:
            - name: STORAGE_TYPE
              value: "openstack"
            - name: REGION_A_NAME
              valueFrom:
                secretKeyRef:
                  name: swift-credentials
                  key: region-a-name
            - name: REGION_A_SWIFT_ENDPOINT
              valueFrom:
                secretKeyRef:
                  name: swift-credentials
                  key: region-a-endpoint
            # ... more env vars from secrets
          restartPolicy: OnFailure
```

#### Advanced Automation Patterns

**1. Configuration Management Integration:**
```bash
# Ansible playbook task
- name: Run replication monitoring
  shell: |
    echo "{{ monitoring_config | to_yaml }}" | ruby replication_monitor.rb --stdin
  vars:
    monitoring_config:
      storage_type: openstack
      regions:
        region_a: "{{ vault_region_a_config }}"
        region_b: "{{ vault_region_b_config }}"
```

**2. Alerting Integration:**
```bash
# Cron with alerting
*/15 * * * * cd /path/to/swift-replicator && ruby replication_monitor.rb || curl -X POST "$SLACK_WEBHOOK" -d '{"text":"Replication monitoring failed"}'

# With exit code handling
*/15 * * * * cd /path/to/swift-replicator && ruby replication_monitor.rb; if [ $? -ne 0 ]; then echo "Replication issues detected" | mail -s "Swift Replication Alert" admin@example.com; fi
```

**3. Multi-Environment Monitoring:**
```bash
#!/bin/bash
# monitor_all_envs.sh
environments=("production" "staging" "development")

for env in "${environments[@]}"; do
    echo "Monitoring $env environment..."
    
    # Load environment-specific config
    source "/etc/swift-monitor/${env}.env"
    
    # Run monitoring with environment variables
    ruby replication_monitor.rb
    
    if [ $? -ne 0 ]; then
        echo "Issues detected in $env environment" | logger -t "replication-$env"
    fi
done
```

#### Security Best Practices for Automation

- **Use environment variables for credentials** (not YAML files in automation)
- **Store sensitive configs in secure vaults** (HashiCorp Vault, AWS Secrets Manager, etc.)
- **Use stdin method to avoid writing sensitive data to disk**
- **Implement proper logging without exposing credentials**
- **Use dedicated service accounts with minimal permissions**

Example output:
```
Storage Replication Monitor - 2025-08-28 10:30:00
==================================================

region-a -> region-b:
  Status: warning
  Last Sync: 2025-08-28 09:45:00
  Objects in Sync: 42/50
  Issues:
    - 8 objects not replicated (16.0% missing)
    - 2 objects may be stale in target region

region-b -> region-a:
  Status: healthy
  Last Sync: 2025-08-28 10:15:00
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

- `replication_monitor.rb` - Main script entry point with command-line argument support
- `config.yaml` - YAML configuration file with all monitoring settings
- `demo_stdin_method.rb` - Demonstration script showing advanced configuration methods
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

---

**Last Updated:** August 28, 2025  
**Documentation Status:** ✅ Up to date with current codebase
