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

  # Get comprehensive replication status including content verification
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
    
    {
      total_objects: objects.length,
      replicated_objects: replicated_objects.length,
      missing_objects: missing_objects.length,
      content_mismatches: content_mismatches.length,
      stale_objects: stale_objects.length,
      size_mismatches: size_mismatches.length,
      sync_percentage: calculate_sync_percentage(objects.length, replicated_objects.length),
      last_replication_check: Time.now,
      replication_health: determine_replication_health(replication_details),
      detailed_status: replication_details
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

  def count_replicated_objects(objects, target_region)
    objects.count do |obj|
      # Use appropriate identifier based on storage type
      key = obj[:key]
      container = @storage_type == 'openstack' ? obj[:container] : obj[:bucket]
      target_region.object_exists?(key, container)
    end
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
    
    # Compare content integrity (ETag/checksum)
    if source_obj[:etag] != target_metadata[:etag]
      return {
        key: key,
        container: container,
        status: 'content_mismatch',
        issue: 'Content checksums differ',
        source_etag: source_obj[:etag],
        target_etag: target_metadata[:etag]
      }
    end
    
    # Compare file sizes
    if source_obj[:size] != target_metadata[:size]
      return {
        key: key,
        container: container,
        status: 'size_mismatch',
        issue: 'File sizes differ',
        source_size: source_obj[:size],
        target_size: target_metadata[:size]
      }
    end
    
    # Compare modification times (detect stale objects)
    source_time = parse_time(source_obj[:last_modified])
    target_time = parse_time(target_metadata[:last_modified])
    
    if source_time > target_time
      time_diff = source_time - target_time
      return {
        key: key,
        container: container,
        status: 'stale',
        issue: 'Target object is outdated',
        replication_lag: time_diff.round(2),
        source_modified: source_time,
        target_modified: target_time
      }
    end
    
    # Object is properly replicated
    {
      key: key,
      container: container,
      status: 'replicated',
      last_verified: Time.now
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
    sync_percentage = calculate_sync_percentage(total, replicated)
    
    case sync_percentage
    when 95..100 then 'healthy'
    when 80...95 then 'warning'
    when 0...80 then 'critical'
    else 'unknown'
    end
  end
end
