# frozen_string_literal: true

# Represents a storage region with its configuration and capabilities
class Region
  attr_reader :name, :endpoint, :credentials, :client

  def initialize(config)
    @name = config[:name]
    @endpoint = config[:endpoint]
    @credentials = config[:credentials]
    @storage_type = config[:storage_type] || 'generic'
    
    # Use appropriate storage client based on type
    @client = case @storage_type
              when 'openstack'
                require_relative 'openstack_storage_client'
                OpenStackStorageClient.new(self)
              else
                StorageClient.new(self)
              end
    
    validate_config!
  end

  # Get all storage objects in this region
  def list_objects(container = nil)
    @client.list_objects(container)
  end

  # Get metadata for a specific object
  def get_object_metadata(object_key, container = nil)
    @client.get_object_metadata(object_key, container)
  end

  # Check if object exists in this region
  def object_exists?(object_key, container = nil)
    @client.object_exists?(object_key, container)
  end

  # Get comprehensive replication status including content verification and bidirectional conflicts
  def get_replication_status(target_region)
    objects = list_objects
    
    replication_details = objects.map do |obj|
      analyze_object_replication(obj, target_region)
    end
    
    # Categorize replication status
    missing_objects = replication_details.select { |detail| detail[:status] == 'missing' }
    content_mismatches = replication_details.select { |detail| detail[:status] == 'content_mismatch' }
    stale_objects = replication_details.select { |detail| detail[:status] == 'stale' }
    size_mismatches = replication_details.select { |detail| detail[:status] == 'size_mismatch' }
    replicated_objects = replication_details.select { |detail| detail[:status] == 'replicated' }
    
    # Detect bidirectional conflicts (objects that exist in both regions but differ)
    bidirectional_conflicts = detect_bidirectional_conflicts(target_region)
    
    {
      total_objects: objects.length,
      replicated_objects: replicated_objects.length,
      missing_objects: missing_objects.length,
      content_mismatches: content_mismatches.length,
      stale_objects: stale_objects.length,
      size_mismatches: size_mismatches.length,
      bidirectional_conflicts: bidirectional_conflicts.length,
      sync_percentage: calculate_sync_percentage(objects.length, replicated_objects.length),
      last_replication_check: Time.now,
      replication_health: determine_replication_health(replication_details),
      detailed_status: replication_details,
      conflict_details: bidirectional_conflicts
    }
  end

  # Get the last modification time of the most recently updated object
  def get_last_modification_time
    objects = list_objects
    return nil if objects.empty?
    
    objects.map { |obj| obj[:last_modified] }.max
  end

  def to_s
    "Region(#{@name})"
  end

  private

  def validate_config!
    raise ArgumentError, "Missing region name" if @name.nil? || @name.empty?
    raise ArgumentError, "Missing endpoint" if @endpoint.nil? || @endpoint.empty?
    raise ArgumentError, "Missing credentials" if @credentials.nil?
    
    if @storage_type == 'openstack'
      validate_openstack_config!
    else
      validate_generic_config!
    end
  end

  def validate_openstack_config!
    raise ArgumentError, "Missing auth_url" if @credentials[:auth_url].nil?
    raise ArgumentError, "Missing username" if @credentials[:username].nil?
    raise ArgumentError, "Missing password" if @credentials[:password].nil?
    raise ArgumentError, "Missing project_name" if @credentials[:project_name].nil?
  end

  def validate_generic_config!
    raise ArgumentError, "Missing access_key" if @credentials[:access_key].nil?
    raise ArgumentError, "Missing secret_key" if @credentials[:secret_key].nil?
  end

  def detect_bidirectional_conflicts(target_region)
    conflicts = []
    
    # Get objects from both regions
    source_objects = list_objects
    target_objects = target_region.list_objects
    
    # Find objects that exist in both regions
    source_objects.each do |source_obj|
      target_obj = target_objects.find { |t_obj| t_obj[:key] == source_obj[:key] }
      next unless target_obj # Skip if object doesn't exist in target
      
      # Analyze for conflicts
      conflict = analyze_bidirectional_conflict(source_obj, target_obj)
      conflicts << conflict if conflict
    end
    
    conflicts
  end

  def analyze_bidirectional_conflict(source_obj, target_obj)
    key = source_obj[:key]
    
    # Parse timestamps
    source_time = parse_time(source_obj[:last_modified])
    target_time = parse_time(target_obj[:last_modified])
    time_diff = (source_time - target_time).abs
    
    # Compare content hashes
    source_etag = normalize_etag(source_obj[:etag])
    target_etag = normalize_etag(target_obj[:etag])
    content_differs = source_etag != target_etag
    
    # Compare sizes
    source_size = source_obj[:size]
    target_size = target_obj[:size]
    size_differs = source_size != target_size
    
    # Only return conflict if content actually differs
    return nil unless content_differs || size_differs
    
    # Determine conflict type
    if time_diff < 60 && content_differs
      # Same timestamp (within 1 minute) but different content - true conflict!
      {
        key: key,
        conflict_type: 'simultaneous_modification',
        severity: 'high',
        source_etag: source_etag,
        target_etag: target_etag,
        source_size: source_size,
        target_size: target_size,
        source_time: source_time,
        target_time: target_time,
        time_diff: time_diff,
        description: "File modified simultaneously in both regions"
      }
    elsif content_differs
      # Different content with time difference
      newer_region = source_time > target_time ? 'source' : 'target'
      {
        key: key,
        conflict_type: 'content_divergence',
        severity: 'medium',
        source_etag: source_etag,
        target_etag: target_etag,
        source_size: source_size,
        target_size: target_size,
        source_time: source_time,
        target_time: target_time,
        newer_region: newer_region,
        time_diff: time_diff,
        description: "Different content versions (#{newer_region} is newer)"
      }
    else
      nil # No actual conflict
    end
  end

  def normalize_etag(etag)
    # Remove quotes and normalize etag format
    etag.to_s.gsub(/["']/, '').downcase
  end

  def analyze_object_replication(source_obj, target_region)
    key = source_obj[:key]
    container = get_container_name(source_obj)
    
    # Check if object exists in target
    unless target_region.object_exists?(key, container)
      return {
        key: key,
        container: container,
        status: 'missing',
        issue: 'Object does not exist in target region'
      }
    end
    
    # Get metadata from target region
    target_metadata = target_region.get_object_metadata(key, container)
    return handle_metadata_error(key, container) if target_metadata.nil?
    
    # Compare content integrity (ETag/checksum) - most important check
    source_etag = normalize_etag(source_obj[:etag])
    target_etag = normalize_etag(target_metadata[:etag])
    
    if source_etag != target_etag
      return {
        key: key,
        container: container,
        status: 'content_mismatch',
        issue: 'Content checksums differ - possible corruption or different versions',
        source_etag: source_etag,
        target_etag: target_etag,
        priority: 'high' # Content mismatches are high priority
      }
    end
    
    # Compare file sizes (secondary check)
    if source_obj[:size] != target_metadata[:size]
      return {
        key: key,
        container: container,
        status: 'size_mismatch',
        issue: 'File sizes differ despite matching checksums',
        source_size: source_obj[:size],
        target_size: target_metadata[:size],
        priority: 'medium'
      }
    end
    
    # Compare modification times (tertiary check for staleness)
    source_time = parse_time(source_obj[:last_modified])
    target_time = parse_time(target_metadata[:last_modified])
    
    if source_time > target_time
      time_diff = source_time - target_time
      # Only consider stale if time difference is significant (> 5 minutes)
      if time_diff > 300
        return {
          key: key,
          container: container,
          status: 'stale',
          issue: 'Target object timestamp is significantly older',
          replication_lag: time_diff.round(2),
          source_modified: source_time,
          target_modified: target_time,
          priority: 'low'
        }
      end
    end
    
    # Object is properly replicated
    {
      key: key,
      container: container,
      status: 'replicated',
      last_verified: Time.now,
      checksum_match: true,
      size_match: true,
      timestamp_current: true
    }
  rescue StandardError => e
    handle_comparison_error(key, container, e)
  end

  def get_container_name(obj)
    @storage_type == 'openstack' ? obj[:container] : obj[:bucket]
  end

  def handle_metadata_error(key, container)
    {
      key: key,
      container: container,
      status: 'error',
      issue: 'Failed to retrieve target object metadata'
    }
  end

  def handle_comparison_error(key, container, error)
    {
      key: key,
      container: container,
      status: 'error',
      issue: "Comparison failed: #{error.message}"
    }
  end

  def parse_time(time_obj)
    return time_obj if time_obj.is_a?(Time)
    return Time.parse(time_obj) if time_obj.is_a?(String)
    time_obj
  rescue StandardError
    Time.at(0) # Fallback for unparseable times
  end

  def calculate_sync_percentage(total, replicated)
    return 100.0 if total.zero?
    ((replicated.to_f / total) * 100).round(2)
  end

  def determine_replication_health(replication_details)
    total = replication_details.length
    return 'healthy' if total.zero?
    
    replicated = replication_details.count { |detail| detail[:status] == 'replicated' }
    content_mismatches = replication_details.count { |detail| detail[:status] == 'content_mismatch' }
    
    # Content mismatches are critical
    return 'critical' if content_mismatches > 0
    
    sync_percentage = calculate_sync_percentage(total, replicated)
    
    case sync_percentage
    when 95..100 then 'healthy'
    when 80...95 then 'warning'
    when 0...80 then 'critical'
    else 'unknown'
    end
  end
end
