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

  # Get replication status for objects from this region
  def get_replication_status(target_region)
    objects = list_objects
    
    {
      total_objects: objects.length,
      replicated_objects: count_replicated_objects(objects, target_region),
      last_replication_check: Time.now,
      objects: objects
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
end
