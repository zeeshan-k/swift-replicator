#!/usr/bin/env ruby
# frozen_string_literal: true

require 'yaml'
require 'open3'
require 'json'

# Demo: Using stdin method to pass config to a Ruby script
# This shows Method 3 - no files written to filesystem, all in-memory

def demo_stdin_config_passing
  puts "=== Demo: Passing YAML config via stdin (Method 3) ==="
  
  # Read configuration from config.yaml file
  begin
    config = YAML.load_file('config.yaml')
    puts "✅ Loaded configuration from config.yaml"
  rescue Errno::ENOENT
    puts "❌ Error: config.yaml file not found"
    puts "Please ensure config.yaml exists in the current directory"
    return
  rescue => e
    puts "❌ Error reading config.yaml: #{e.message}"
    return
  end
  
  # Convert to YAML string (still in memory)
  yaml_content = config.to_yaml
  puts "Generated YAML config (#{yaml_content.bytesize} bytes):"
  puts yaml_content[0..200] + "..." # Show first 200 chars
  
  # Method 3: Pass via stdin to a hypothetical monitoring tool
  puts "\n--- Passing config via stdin to monitoring tool ---"
  
  # Simulate calling our replication monitor with stdin config
  demo_script = <<~'RUBY'
    require 'yaml'

    # Read YAML from stdin (no filesystem access)
    config_yaml = STDIN.read
    config = YAML.safe_load(config_yaml)

    puts "Received config via stdin:"
    puts "Storage type: #{config['storage_type']}"
    puts "Regions: #{config['regions'].keys.join(', ')}"
    puts "Containers to monitor: #{config.dig('monitoring', 'containers')&.join(', ')}"

    # Process the configuration
    config['regions'].each do |region_name, region_config|
      puts "\nRegion: #{region_config['name']}"
      puts "  Endpoint: #{region_config['endpoint']}"
      puts "  Auth URL: #{region_config.dig('credentials', 'auth_url')}"
      puts "  Project: #{region_config.dig('credentials', 'project_name')}"
    end

    puts "\nConfiguration processed successfully - no temp files created!"
    exit 0
  RUBY
  
  # Execute using Open3.popen3 (Method 3)
  Open3.popen3('ruby', '-e', demo_script) do |stdin, stdout, stderr, thread|
    # Write YAML config to stdin (in-memory transfer)
    stdin.write(yaml_content)
    stdin.close  # Signal end of input
    
    # Read results
    output = stdout.read
    errors = stderr.read
    exit_code = thread.value.exitstatus
    
    puts output
    puts "Errors: #{errors}" unless errors.empty?
    puts "Exit code: #{exit_code}"
  end
  
  puts "\n=== Benefits of Method 3 (stdin): ==="
  puts "✅ No temporary files created on filesystem"
  puts "✅ Configuration stays in memory only"
  puts "✅ More secure (no sensitive data on disk)"
  puts "✅ Works with containerized applications"
  puts "✅ Reduces I/O operations"
end

def demo_openstack_in_memory_operations
  puts "\n=== Demo: OpenStack operations without filesystem writes ==="
  
  # Simulate OpenStack Swift operations that work in-memory
  puts "1. Authentication: Tokens stored in memory only"
  puts "2. Object upload: put_object('config.json', json_data) - no local file"
  puts "3. Object download: get_object_content('config.json') - returns string"
  puts "4. Object listing: All metadata in Ruby objects"
  
  # Example: Create and upload JSON config without writing to disk
  json_config = {
    'replication_settings' => {
      'sync_interval' => 300,
      'retry_count' => 3,
      'timeout' => 60
    },
    'notification_endpoints' => [
      'https://webhook1.example.com',
      'https://webhook2.example.com'
    ]
  }
  
  json_content = JSON.pretty_generate(json_config)
  puts "\nJSON config created in memory (#{json_content.bytesize} bytes):"
  puts json_content
  
  puts "\nThis JSON could be uploaded to Swift using:"
  puts "client.put_object('replication-config.json', json_content, 'config-container')"
  puts "↑ No filesystem writes - direct memory to Swift transfer"
end

# Run the demos
if __FILE__ == $PROGRAM_NAME
  demo_stdin_config_passing
  demo_openstack_in_memory_operations
end
