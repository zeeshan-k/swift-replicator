# frozen_string_literal: true

require 'net/http'
require 'json'
require 'uri'

# Client for interacting with storage services in a region
class StorageClient
  def initialize(region)
    @region = region
    @endpoint = region.endpoint
    @credentials = region.credentials
  end

  # List all objects in the storage (or specific bucket)
  def list_objects(bucket = nil)
    # This is a mock implementation - replace with actual API calls
    # to your storage service (AWS S3, Azure Blob, GCP Cloud Storage, etc.)
    
    mock_objects_for_region(@region.name, bucket)
  end

  # Get metadata for a specific object
  def get_object_metadata(object_key, bucket = nil)
    objects = list_objects(bucket)
    objects.find { |obj| obj[:key] == object_key }
  end

  # Check if an object exists
  def object_exists?(object_key, bucket = nil)
    !get_object_metadata(object_key, bucket).nil?
  end

  # Get object content as string (for sync operations)
  def get_object_content(object_key, bucket = nil)
    # Mock implementation - returns simulated content
    # In real implementation, this would fetch the actual object data
    
    metadata = get_object_metadata(object_key, bucket)
    return nil unless metadata
    
    # Generate mock content based on object size
    mock_content_for_object(object_key, metadata[:size])
  end

  # Upload/write an object (for sync operations)
  def put_object(object_key, content, bucket = nil, content_type = 'application/octet-stream')
    # Mock implementation - simulates uploading content
    # In real implementation, this would upload to actual storage service
    
    bucket ||= 'default-bucket'
    
    puts "    📤 Mock upload: #{object_key} (#{content.bytesize} bytes) to #{bucket}"
    
    # Simulate upload delay
    sleep(0.1) unless ENV['FAST_MOCK']
    
    # Mock success response
    {
      success: true,
      etag: "\"#{generate_mock_etag}\"",
      bucket: bucket,
      object: object_key,
      size: content.bytesize,
      uploaded_at: Time.now
    }
  rescue StandardError => e
    {
      success: false,
      error: e.message
    }
  end

  # Delete an object (for cleanup operations)
  def delete_object(object_key, bucket = nil)
    # Mock implementation
    bucket ||= 'default-bucket'
    
    puts "    🗑️  Mock delete: #{object_key} from #{bucket}"
    
    {
      success: true,
      deleted: object_key,
      bucket: bucket
    }
  rescue StandardError => e
    {
      success: false,
      error: e.message
    }
  end

  # Get storage service health status
  def health_check
    begin
      # Mock health check - replace with actual endpoint health check
      start_time = Time.now
      
      # Simulate health check by trying to list objects
      list_objects('health-check-bucket')
      
      response_time = ((Time.now - start_time) * 1000).round(2)
      
      {
        status: 'healthy',
        response_time: response_time,
        last_check: Time.now,
        endpoint: @endpoint
      }
    rescue StandardError => e
      {
        status: 'unhealthy',
        error: e.message,
        last_check: Time.now,
        response_time: nil
      }
    end
  end

  private

  def mock_content_for_object(object_key, size)
    # Generate deterministic content based on object key
    # This ensures consistent content for the same object across calls
    
    base_content = "Mock content for #{object_key}\n"
    base_content += "Generated at: #{Time.now}\n"
    base_content += "Size target: #{size} bytes\n"
    base_content += "-" * 40 + "\n"
    
    # Pad content to reach approximate target size
    while base_content.bytesize < size
      base_content += "Data block #{base_content.bytesize / 100}: " + ("x" * 50) + "\n"
    end
    
    # Truncate to exact size if needed
    base_content[0, size]
  end

  # Mock data generator - replace with actual API calls
  def mock_objects_for_region(region_name, bucket = nil)
    base_time = Time.now - rand(3600..86400) # Random time within last 24 hours
    
    objects = []
    
    # Generate some sample objects
    (1..rand(10..50)).each do |i|
      objects << {
        key: "data/file_#{region_name.gsub('-', '_')}_#{i}.dat",
        bucket: bucket || 'default-bucket',
        size: rand(1024..10240), # bytes
        last_modified: base_time + rand(3600), # Within an hour of base_time
        etag: "\"#{generate_mock_etag}\"",
        storage_class: 'STANDARD'
      }
    end
    
    # Add some shared objects that should exist in both regions (for testing replication)
    shared_objects = [
      {
        key: 'shared/config.json',
        bucket: bucket || 'default-bucket', 
        size: 2048,
        last_modified: base_time,
        etag: '"shared-config-etag"',
        storage_class: 'STANDARD'
      },
      {
        key: 'shared/data.csv',
        bucket: bucket || 'default-bucket',
        size: 15360,
        last_modified: base_time + 1800, # 30 minutes later
        etag: '"shared-data-etag"',
        storage_class: 'STANDARD'
      }
    ]
    
    objects.concat(shared_objects)
    
    # Simulate some replication lag by making some objects not appear in target regions
    if region_name.include?('west') # Target region simulation
      # Remove some objects to simulate incomplete replication
      objects = objects.select.with_index { |_, index| index % 4 != 0 } # Remove every 4th object
      
      # Make some objects appear older (replication lag)
      objects.each do |obj|
        if obj[:key].include?('shared')
          obj[:last_modified] = obj[:last_modified] - rand(300..1800) # 5-30 minutes older
        end
      end
    end
    
    objects.sort_by { |obj| obj[:last_modified] }.reverse
  end

  def generate_mock_etag
    # Generate a mock etag (hash-like identifier)
    chars = ('a'..'f').to_a + ('0'..'9').to_a
    32.times.map { chars.sample }.join
  end
end
