# frozen_string_literal: true

require 'net/http'
require 'json'
require 'uri'
require 'time'

# OpenStack Swift client for storage operations
class OpenStackStorageClient
  def initialize(region)
    @region = region
    @auth_url = region.credentials[:auth_url] # e.g., 'https://identity.example.com:5000/v3'
    @username = region.credentials[:username]
    @password = region.credentials[:password]
    @project_name = region.credentials[:project_name] || region.credentials[:tenant_name]
    @domain_name = region.credentials[:domain_name] || 'default'
    @swift_endpoint = region.endpoint # Swift storage endpoint
    
    @auth_token = nil
    @token_expires_at = nil
  end

  # List all objects in a container (Swift equivalent of bucket)
  def list_objects(container = nil)
    authenticate! unless valid_token?
    
    container ||= 'default-container'
    path = "/v1/AUTH_#{get_account_id}/#{container}"
    
    response = make_request(:get, path, {
      'X-Auth-Token' => @auth_token,
      'Accept' => 'application/json'
    })
    
    objects_data = JSON.parse(response)
    
    objects_data.map do |obj|
      {
        key: obj['name'],
        container: container,
        size: obj['bytes'],
        last_modified: Time.parse(obj['last_modified']),
        etag: obj['hash'],
        content_type: obj['content_type']
      }
    end
  rescue StandardError => e
    puts "Error listing objects: #{e.message}"
    []
  end

  # Get metadata for a specific object
  def get_object_metadata(object_key, container = nil)
    authenticate! unless valid_token?
    
    container ||= 'default-container'
    path = "/v1/AUTH_#{get_account_id}/#{container}/#{object_key}"
    
    response = make_request(:head, path, {
      'X-Auth-Token' => @auth_token
    })
    
    {
      key: object_key,
      container: container,
      size: response.headers['Content-Length'].to_i,
      last_modified: Time.parse(response.headers['Last-Modified']),
      etag: response.headers['Etag'],
      content_type: response.headers['Content-Type']
    }
  rescue StandardError => e
    puts "Error getting object metadata: #{e.message}"
    nil
  end

  # Check if an object exists
  def object_exists?(object_key, container = nil)
    authenticate! unless valid_token?
    
    container ||= 'default-container'
    path = "/v1/AUTH_#{get_account_id}/#{container}/#{object_key}"
    
    begin
      make_request(:head, path, {
        'X-Auth-Token' => @auth_token
      })
      true
    rescue StandardError => e
      # 404 means object doesn't exist
      if e.message.include?('404')
        false
      else
        puts "Error checking object existence: #{e.message}"
        false
      end
    end
  end

  # Get storage service health status
  def health_check
    start_time = Time.now
    
    begin
      authenticate!
      response_time = ((Time.now - start_time) * 1000).round(2)
      
      {
        status: 'healthy',
        response_time: response_time,
        last_check: Time.now,
        swift_version: get_swift_version
      }
    rescue StandardError => e
      {
        status: 'unhealthy',
        error: e.message,
        last_check: Time.now,
        response_time: ((Time.now - start_time) * 1000).round(2)
      }
    end
  end

  # Upload/write an object to Swift storage (in-memory, no filesystem writes)
  def put_object(object_key, content, container = nil, content_type = 'application/octet-stream')
    authenticate! unless valid_token?
    
    container ||= 'default-container'
    
    # Ensure container exists
    create_container(container)
    
    path = "/v1/AUTH_#{get_account_id}/#{container}/#{object_key}"
    
    uri = URI.join(@swift_endpoint, path)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == 'https'
    
    request = Net::HTTP::Put.new(uri.path)
    request['X-Auth-Token'] = @auth_token
    request['Content-Type'] = content_type
    request['Content-Length'] = content.bytesize.to_s
    request.body = content
    
    response = http.request(request)
    
    case response.code
    when '201', '202'
      {
        success: true,
        etag: response['Etag'],
        container: container,
        object: object_key,
        size: content.bytesize
      }
    else
      raise "Failed to upload object: HTTP #{response.code} - #{response.body}"
    end
  rescue StandardError => e
    puts "Error uploading object: #{e.message}"
    { success: false, error: e.message }
  end

  # Get object content as string (in-memory, no filesystem writes)
  def get_object_content(object_key, container = nil)
    authenticate! unless valid_token?
    
    container ||= 'default-container'
    path = "/v1/AUTH_#{get_account_id}/#{container}/#{object_key}"
    
    make_request(:get, path, {
      'X-Auth-Token' => @auth_token
    })
  end

  # Delete an object from Swift storage
  def delete_object(object_key, container = nil)
    authenticate! unless valid_token?
    
    container ||= 'default-container'
    path = "/v1/AUTH_#{get_account_id}/#{container}/#{object_key}"
    
    make_request(:delete, path, {
      'X-Auth-Token' => @auth_token
    })
    
    { success: true, deleted: object_key }
  rescue StandardError => e
    puts "Error deleting object: #{e.message}"
    { success: false, error: e.message }
  end

  # Create a container if it doesn't exist
  def create_container(container)
    authenticate! unless valid_token?
    
    path = "/v1/AUTH_#{get_account_id}/#{container}"
    
    begin
      make_request(:put, path, {
        'X-Auth-Token' => @auth_token,
        'Content-Length' => '0'
      })
      true
    rescue StandardError => e
      # Container might already exist (202 response)
      if e.message.include?('202')
        puts "Container #{container} already exists"
        true
      else
        puts "Error creating container: #{e.message}"
        false
      end
    end
  end

  private

  def authenticate!
    auth_data = {
      auth: {
        identity: {
          methods: ['password'],
          password: {
            user: {
              name: @username,
              domain: { name: @domain_name },
              password: @password
            }
          }
        },
        scope: {
          project: {
            name: @project_name,
            domain: { name: @domain_name }
          }
        }
      }
    }

    uri = URI.join(@auth_url, '/auth/tokens')
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == 'https'

    request = Net::HTTP::Post.new(uri.path)
    request['Content-Type'] = 'application/json'
    request.body = auth_data.to_json

    response = http.request(request)
    
    case response.code
    when '201'
      @auth_token = response['X-Subject-Token']
      
      # Parse token expiry from response body
      token_data = JSON.parse(response.body)
      expires_at = token_data['token']['expires_at']
      @token_expires_at = Time.parse(expires_at)
      
    else
      raise "Authentication failed: HTTP #{response.code} - #{response.body}"
    end
  end

  def valid_token?
    return false unless @auth_token && @token_expires_at
    
    # Check if token expires in the next 5 minutes
    @token_expires_at > (Time.now + 300)
  end

  def get_account_id
    # Extract account ID from Swift endpoint or use project name
    # This might need adjustment based on your OpenStack setup
    @project_name.gsub(/[^a-zA-Z0-9]/, '_')
  end

  def get_swift_version
    # Get Swift version from cluster info
    begin
      response = make_request(:get, '/info', {})
      info_data = JSON.parse(response)
      info_data.dig('swift', 'version') || 'unknown'
    rescue
      'unknown'
    end
  end

  def make_request(method, path, headers = {})
    uri = URI.join(@swift_endpoint, path)
    
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == 'https'
    
    request_class = case method
    when :get then Net::HTTP::Get
    when :post then Net::HTTP::Post
    when :put then Net::HTTP::Put
    when :delete then Net::HTTP::Delete
    when :head then Net::HTTP::Head
    else
      raise "Unsupported HTTP method: #{method}"
    end
    
    request = request_class.new(uri.path + (uri.query ? "?#{uri.query}" : ''))
    headers.each { |key, value| request[key] = value }
    
    response = http.request(request)
    
    case response.code
    when '200', '201', '204'
      response.body || response
    when '404'
      raise "Not found: #{path}"
    else
      raise "HTTP #{response.code}: #{response.body}"
    end
  end
end
