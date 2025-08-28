#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'lib/replication_monitor'
require_relative 'lib/region'
require_relative 'lib/storage_client'
require_relative 'lib/openstack_storage_client'
require 'optparse'

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

class StorageReplicationTool
  def initialize
    @options = {}
    @region_a = Region.new(REGIONS_CONFIG[:region_a])
    @region_b = Region.new(REGIONS_CONFIG[:region_b])
    @monitor = ReplicationMonitor.new
    
    # Add bidirectional replication pairs
    @monitor.add_replication_pair(@region_a, @region_b)
    @monitor.add_replication_pair(@region_b, @region_a)
  end

  def parse_options
    OptionParser.new do |opts|
      opts.banner = "Usage: #{$PROGRAM_NAME} [options]"
      opts.separator ""
      opts.separator "Storage Replication Tool - Monitor and sync storage between regions"
      opts.separator ""
      
      opts.on("-m", "--monitor", "Monitor replication status") do
        @options[:action] = :monitor
      end
      
      opts.on("-s", "--sync", "Perform synchronization") do
        @options[:action] = :sync
      end
      
      opts.on("-c", "--check", "Health check of storage regions") do
        @options[:action] = :health_check
      end
      
      opts.on("-b", "--bidirectional", "Perform bidirectional sync (A↔B)") do
        @options[:bidirectional] = true
      end
      
      opts.on("--conflict-strategy STRATEGY", 
              ["newest_wins", "region_a_wins", "region_b_wins", "largest_wins", "manual"],
              "Conflict resolution strategy (newest_wins, region_a_wins, region_b_wins, largest_wins, manual)") do |strategy|
        @options[:conflict_strategy] = strategy
      end
      
      opts.on("--dry-run", "Show what would be synced without actually syncing") do
        @options[:dry_run] = true
      end
      
      opts.on("-v", "--verbose", "Enable verbose output") do
        @options[:verbose] = true
      end
      
      opts.on("-f", "--force", "Force sync even with warnings") do
        @options[:force] = true
      end
      
      opts.on("-h", "--help", "Show this help message") do
        puts opts
        exit
      end
      
      opts.separator ""
      opts.separator "Conflict Resolution Strategies:"
      opts.separator "  newest_wins    - Use the most recently modified version (default)"
      opts.separator "  region_a_wins  - Always use Region A as source of truth"
      opts.separator "  region_b_wins  - Always use Region B as source of truth"  
      opts.separator "  largest_wins   - Use the version with larger file size"
      opts.separator "  manual         - Prompt user to resolve each conflict"
      opts.separator ""
      opts.separator "Examples:"
      opts.separator "  #{$PROGRAM_NAME} --monitor                                    # Monitor replication status"
      opts.separator "  #{$PROGRAM_NAME} --sync --dry-run                           # Show what would be synced"
      opts.separator "  #{$PROGRAM_NAME} --sync --bidirectional                     # Smart bidirectional sync"
      opts.separator "  #{$PROGRAM_NAME} --sync --bidirectional --conflict-strategy=manual  # Manual conflict resolution"
      opts.separator "  #{$PROGRAM_NAME} --check                                    # Check storage health"
    end.parse!
  end

  def run
    puts "Storage Replication Tool - #{Time.now}"
    puts "=" * 60
    
    if @options[:action].nil?
      show_interactive_menu
    else
      execute_action(@options[:action])
    end
  end

  private

  def show_interactive_menu
    loop do
      puts "\nSelect an option:"
      puts "1. Monitor replication status"
      puts "2. Perform synchronization"
      puts "3. Health check"
      puts "4. Smart bidirectional sync"
      puts "5. Dry run sync"
      puts "6. Configure conflict resolution"
      puts "7. Exit"
      print "\nEnter choice (1-7): "
      
      choice = gets.chomp
      
      case choice
      when '1'
        execute_action(:monitor)
      when '2'
        @options[:dry_run] = false
        execute_action(:sync)
      when '3'
        execute_action(:health_check)
      when '4'
        @options[:bidirectional] = true
        @options[:dry_run] = false
        @options[:conflict_strategy] ||= 'newest_wins'
        execute_action(:sync)
      when '5'
        @options[:dry_run] = true
        execute_action(:sync)
      when '6'
        configure_conflict_resolution
      when '7'
        puts "Goodbye!"
        exit(0)
      else
        puts "Invalid choice. Please enter 1-7."
      end
    end
  end

  def configure_conflict_resolution
    puts "\n⚙️  CONFLICT RESOLUTION CONFIGURATION"
    puts "-" * 40
    puts "Choose default conflict resolution strategy:"
    puts "1. Newest Wins (use most recently modified version)"
    puts "2. Region A Wins (always prefer Region A)"
    puts "3. Region B Wins (always prefer Region B)"
    puts "4. Largest Wins (use version with larger file size)"
    puts "5. Manual (prompt for each conflict)"
    print "\nEnter choice (1-5): "
    
    choice = gets.chomp
    
    @options[:conflict_strategy] = case choice
    when '1' then 'newest_wins'
    when '2' then 'region_a_wins'
    when '3' then 'region_b_wins'
    when '4' then 'largest_wins'
    when '5' then 'manual'
    else 'newest_wins' # Default
    end
    
    puts "✅ Conflict resolution set to: #{@options[:conflict_strategy]}"
  end

  def execute_action(action)
    case action
    when :monitor
      monitor_replication
    when :sync
      perform_sync
    when :health_check
      perform_health_check
    else
      puts "Unknown action: #{action}"
    end
  end

  def monitor_replication
    puts "\n📊 MONITORING REPLICATION STATUS"
    puts "-" * 40
    
    results = @monitor.check_all_replications
    
    results.each do |result|
      puts "\n#{result[:source].name} -> #{result[:target].name}:"
      puts "  Status: #{colorize_status(result[:status])}"
      puts "  Last Sync: #{result[:last_sync_time] || 'Unknown'}"
      puts "  Objects in Sync: #{result[:objects_in_sync]}/#{result[:total_objects]} (#{result[:sync_percentage]}%)"
      
      # Show detailed breakdown if available
      if result[:missing_objects] || result[:content_mismatches] || result[:stale_objects] || result[:size_mismatches] || result[:bidirectional_conflicts]
        puts "  Breakdown:"
        puts "    - Missing: #{result[:missing_objects] || 0}"
        puts "    - Content mismatches: #{result[:content_mismatches] || 0}" 
        puts "    - Stale objects: #{result[:stale_objects] || 0}"
        puts "    - Size mismatches: #{result[:size_mismatches] || 0}"
        puts "    - Bidirectional conflicts: #{result[:bidirectional_conflicts] || 0}" if result[:bidirectional_conflicts]
      end
      
      if result[:status] != 'healthy'
        puts "  Issues:"
        result[:issues].each { |issue| puts "    - #{issue}" }
        
        # Show detailed status for critical issues (optional)
        if @options[:verbose] && result[:detailed_status]
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
    
    puts "\n" + "=" * 40
    puts "Summary: #{healthy_count}/#{total_count} replication pairs are healthy"
  end

  def perform_sync
    puts "\n🔄 PERFORMING SYNCHRONIZATION"
    puts "-" * 40
    
    if @options[:dry_run]
      puts "DRY RUN MODE - No actual changes will be made"
    end
    
    if @options[:bidirectional]
      # Enhanced bidirectional sync with conflict resolution
      conflict_strategy = @options[:conflict_strategy] || 'newest_wins'
      puts "Using conflict resolution strategy: #{conflict_strategy.upcase}"
      
      sync_result = @monitor.perform_bidirectional_sync(
        @region_a, 
        @region_b,
        dry_run: @options[:dry_run],
        conflict_strategy: conflict_strategy,
        force: @options[:force]
      )
      
      display_bidirectional_sync_results(sync_result)
    else
      # Unidirectional sync (A → B)
      sync_pairs = [
        { source: @region_a, target: @region_b, direction: "A → B" }
      ]
      
      sync_pairs.each do |pair|
        puts "\n📁 Syncing #{pair[:direction]} (#{pair[:source].name} → #{pair[:target].name})"
        puts "-" * 30
        
        sync_result = @monitor.perform_sync(
          pair[:source], 
          pair[:target], 
          dry_run: @options[:dry_run],
          force: @options[:force]
        )
        
        display_sync_results(sync_result)
      end
    end
  end

  def perform_health_check
    puts "\n🏥 HEALTH CHECK"
    puts "-" * 40
    
    puts "\nChecking Region A (#{@region_a.name}):"
    health_a = @region_a.client.health_check
    display_health_status(health_a)
    
    puts "\nChecking Region B (#{@region_b.name}):"
    health_b = @region_b.client.health_check
    display_health_status(health_b)
    
    overall_healthy = health_a[:status] == 'healthy' && health_b[:status] == 'healthy'
    puts "\n" + "=" * 40
    puts "Overall Health: #{overall_healthy ? '✅ HEALTHY' : '❌ UNHEALTHY'}"
  end

  def display_bidirectional_sync_results(result)
    if result[:success]
      puts "\n✅ BIDIRECTIONAL SYNC COMPLETED SUCCESSFULLY"
      puts "  📊 Overall Statistics:"
      puts "    - Total objects synced: #{result[:total_synced_count]}"
      puts "    - Conflicts detected: #{result[:conflicts_detected]}"
      puts "    - Conflicts resolved: #{result[:conflicts_resolved]}"
      puts "    - A→B synced: #{result[:a_to_b_synced]}"
      puts "    - B→A synced: #{result[:b_to_a_synced]}"
      puts "    - Total errors: #{result[:total_error_count]}"
      puts "    - Total time: #{result[:duration]&.round(2)}s"
      
      # Show conflict details if any
      if result[:detailed_results][:conflicts_resolved].any?
        puts "\n  🔥 Resolved Conflicts:"
        result[:detailed_results][:conflicts_resolved].each do |conflict|
          puts "    - #{conflict[:key]}: #{conflict[:action]} (#{conflict[:resolution_strategy]})"
        end
      end
      
    else
      puts "\n❌ BIDIRECTIONAL SYNC FAILED"
      puts "  Error: #{result[:error]}"
    end
  end

  def display_sync_results(result)
    if result[:success]
      puts "✅ Sync completed successfully"
      puts "  📊 Statistics:"
      puts "    - Objects synced: #{result[:synced_count]}"
      puts "    - Objects skipped: #{result[:skipped_count]}"
      puts "    - Errors: #{result[:error_count]}"
      puts "    - Total time: #{result[:duration]&.round(2)}s"
      
      if result[:synced_objects].any?
        puts "  📁 Synced objects:"
        result[:synced_objects].first(5).each do |obj|
          puts "    - #{obj[:key]} (#{obj[:size]} bytes)"
        end
        if result[:synced_objects].length > 5
          puts "    ... and #{result[:synced_objects].length - 5} more"
        end
      end
      
      if result[:errors].any?
        puts "  ⚠️  Errors:"
        result[:errors].each do |error|
          puts "    - #{error}"
        end
      end
    else
      puts "❌ Sync failed"
      puts "  Error: #{result[:error]}"
    end
  end

  def display_health_status(health)
    status_icon = health[:status] == 'healthy' ? '✅' : '❌'
    puts "  Status: #{status_icon} #{health[:status].upcase}"
    puts "  Response Time: #{health[:response_time]}ms" if health[:response_time]
    puts "  Last Check: #{health[:last_check]}"
    puts "  Error: #{health[:error]}" if health[:error]
  end

  def colorize_status(status)
    case status
    when 'healthy'
      "✅ #{status}"
    when 'warning'
      "⚠️  #{status}"
    when 'critical'
      "🔥 #{status}"
    when 'error'
      "❌ #{status}"
    else
      status
    end
  end
end

def main
  tool = StorageReplicationTool.new
  tool.parse_options
  tool.run
rescue StandardError => e
  puts "Error: #{e.message}"
  puts e.backtrace if ENV['DEBUG']
  exit(1)
end

main if __FILE__ == $PROGRAM_NAME
