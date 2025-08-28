#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'lib/replication_monitor'
require_relative 'lib/region'
require_relative 'lib/storage_client'
require_relative 'lib/openstack_storage_client'

# Configuration - supports both generic storage and OpenStack Swift
STORAGE_TYPE = ENV['STORAGE_TYPE'] || 'generic' # 'generic' or 'openstack'

if STORAGE_TYPE == 'openstack'
  # OpenStack Swift configuration
  REGIONS_CONFIG = {
    region_a: {
      name: ENV['REGION_A_NAME'] || 'regionA',
      endpoint: ENV['REGION_A_SWIFT_ENDPOINT'], # e.g., 'https://swift.regionA.example.com:8080'
      storage_type: 'openstack',
      credentials: {
        auth_url: ENV['REGION_A_AUTH_URL'], # e.g., 'https://keystone.regionA.example.com:5000/v3'
        username: ENV['REGION_A_USERNAME'],
        password: ENV['REGION_A_PASSWORD'],
        project_name: ENV['REGION_A_PROJECT_NAME'],
        domain_name: ENV['REGION_A_DOMAIN_NAME'] || 'default'
      }
    },
    region_b: {
      name: ENV['REGION_B_NAME'] || 'regionB',
      endpoint: ENV['REGION_B_SWIFT_ENDPOINT'], # e.g., 'https://swift.regionB.example.com:8080'
      storage_type: 'openstack',
      credentials: {
        auth_url: ENV['REGION_B_AUTH_URL'], # e.g., 'https://keystone.regionB.example.com:5000/v3'
        username: ENV['REGION_B_USERNAME'],
        password: ENV['REGION_B_PASSWORD'],
        project_name: ENV['REGION_B_PROJECT_NAME'],
        domain_name: ENV['REGION_B_DOMAIN_NAME'] || 'default'
      }
    }
  }.freeze
else
  # Generic storage configuration (AWS S3, Azure, GCP, etc.)
  REGIONS_CONFIG = {
    region_a: {
      name: 'us-east-1',
      endpoint: 'https://storage.us-east-1.example.com',
      storage_type: 'generic',
      credentials: {
        access_key: ENV['REGION_A_ACCESS_KEY'],
        secret_key: ENV['REGION_A_SECRET_KEY']
      }
    },
    region_b: {
      name: 'us-west-2', 
      endpoint: 'https://storage.us-west-2.example.com',
      storage_type: 'generic',
      credentials: {
        access_key: ENV['REGION_B_ACCESS_KEY'],
        secret_key: ENV['REGION_B_SECRET_KEY']
      }
    }
  }.freeze
end

def main
  puts "Storage Replication Monitor - #{Time.now}"
  puts "=" * 50

  # Initialize regions
  region_a = Region.new(REGIONS_CONFIG[:region_a])
  region_b = Region.new(REGIONS_CONFIG[:region_b])

  # Create replication monitor
  monitor = ReplicationMonitor.new

  # Add bidirectional replication pairs
  monitor.add_replication_pair(region_a, region_b)
  monitor.add_replication_pair(region_b, region_a)

  # Run replication checks
  results = monitor.check_all_replications

  # Display results
  results.each do |result|
    puts "\n#{result[:source].name} -> #{result[:target].name}:"
    puts "  Status: #{result[:status]}"
    puts "  Last Sync: #{result[:last_sync_time]}"
    puts "  Objects in Sync: #{result[:objects_in_sync]}/#{result[:total_objects]} (#{result[:sync_percentage]}%)"
    
    # Show detailed breakdown if available
    if result[:missing_objects] || result[:content_mismatches] || result[:stale_objects] || result[:size_mismatches]
      puts "  Breakdown:"
      puts "    - Missing: #{result[:missing_objects] || 0}"
      puts "    - Content mismatches: #{result[:content_mismatches] || 0}" 
      puts "    - Stale objects: #{result[:stale_objects] || 0}"
      puts "    - Size mismatches: #{result[:size_mismatches] || 0}"
    end
    
    if result[:status] != 'healthy'
      puts "  Issues:"
      result[:issues].each { |issue| puts "    - #{issue}" }
      
      # Show detailed status for critical issues (optional)
      if ENV['VERBOSE'] && result[:detailed_status]
        problem_objects = result[:detailed_status].select { |detail| detail[:status] != 'replicated' }
        if problem_objects.any?
          puts "  Problem Objects:"
          problem_objects.first(5).each do |obj|
            puts "    - #{obj[:key]}: #{obj[:status]} (#{obj[:issue]})"
          end
          puts "    ... and #{problem_objects.length - 5} more" if problem_objects.length > 5
        end
      end
    end
  end

  # Summary
  healthy_count = results.count { |r| r[:status] == 'healthy' }
  total_count = results.length
  
  puts "\n" + "=" * 50
  puts "Summary: #{healthy_count}/#{total_count} replication pairs are healthy"
  
  exit(healthy_count == total_count ? 0 : 1)
rescue StandardError => e
  puts "Error: #{e.message}"
  puts e.backtrace if ENV['DEBUG']
  exit(1)
end

main if __FILE__ == $PROGRAM_NAME
