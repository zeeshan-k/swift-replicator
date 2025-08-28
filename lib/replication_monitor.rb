# frozen_string_literal: true

# Manages replication monitoring between multiple regions
class ReplicationMonitor
  def initialize
    @replication_pairs = []
  end

  # Add a replication pair (source -> target)
  def add_replication_pair(source_region, target_region)
    @replication_pairs << {
      source: source_region,
      target: target_region
    }
  end

  # Check all configured replication pairs
  def check_all_replications
    @replication_pairs.map do |pair|
      check_replication(pair[:source], pair[:target])
    end
  end

  # Check replication between a specific source and target region
  def check_replication(source_region, target_region)
    puts "Checking replication: #{source_region.name} -> #{target_region.name}"
    
    begin
      source_status = source_region.get_replication_status(target_region)
      
      # Extract metrics from enhanced status
      total_objects = source_status[:total_objects]
      replicated_objects = source_status[:replicated_objects]
      sync_percentage = source_status[:sync_percentage]
      
      # Determine overall status based on enhanced health assessment
      status = source_status[:replication_health] || determine_replication_status(sync_percentage, source_region, target_region)
      
      # Collect comprehensive issues
      issues = collect_enhanced_replication_issues(source_status)
      
      {
        source: source_region,
        target: target_region,
        status: status,
        total_objects: total_objects,
        objects_in_sync: replicated_objects,
        sync_percentage: sync_percentage,
        missing_objects: source_status[:missing_objects],
        content_mismatches: source_status[:content_mismatches],
        stale_objects: source_status[:stale_objects],
        size_mismatches: source_status[:size_mismatches],
        last_sync_time: get_last_sync_time(source_region, target_region),
        issues: issues,
        detailed_status: source_status[:detailed_status],
        checked_at: Time.now
      }
    rescue StandardError => e
      {
        source: source_region,
        target: target_region,
        status: 'error',
        total_objects: 0,
        objects_in_sync: 0,
        sync_percentage: 0.0,
        missing_objects: 0,
        content_mismatches: 0,
        stale_objects: 0,
        size_mismatches: 0,
        last_sync_time: nil,
        issues: ["Failed to check replication: #{e.message}"],
        checked_at: Time.now
      }
    end
  end

  # Get summary of all replication statuses
  def get_summary
    results = check_all_replications
    
    {
      total_pairs: results.length,
      healthy_pairs: results.count { |r| r[:status] == 'healthy' },
      warning_pairs: results.count { |r| r[:status] == 'warning' },
      critical_pairs: results.count { |r| r[:status] == 'critical' },
      error_pairs: results.count { |r| r[:status] == 'error' },
      overall_health: calculate_overall_health(results),
      last_check: Time.now
    }
  end

  private

  def determine_replication_status(sync_percentage, source_region, target_region)
    return 'error' if sync_percentage.nil?
    return 'healthy' if sync_percentage >= 95.0
    return 'warning' if sync_percentage >= 80.0
    
    'critical'
  end

  def collect_replication_issues(source_status, target_region, sync_percentage)
    issues = []
    
    if sync_percentage < 95.0
      missing_objects = source_status[:total_objects] - source_status[:replicated_objects]
      issues << "#{missing_objects} objects not replicated (#{(100 - sync_percentage).round(2)}% missing)"
    end
    
    # Check for stale replication (objects not updated recently)
    if source_status[:objects].any? { |obj| stale_object?(obj, target_region) }
      stale_count = source_status[:objects].count { |obj| stale_object?(obj, target_region) }
      issues << "#{stale_count} objects may be stale in target region"
    end
    
    issues
  end

  def collect_enhanced_replication_issues(source_status)
    issues = []
    
    # Missing objects
    if source_status[:missing_objects] > 0
      issues << "#{source_status[:missing_objects]} objects missing in target region"
    end
    
    # Content mismatches (data corruption/integrity issues)
    if source_status[:content_mismatches] > 0
      issues << "#{source_status[:content_mismatches]} objects have content mismatches (checksum differences)"
    end
    
    # Stale objects (replication lag)
    if source_status[:stale_objects] > 0
      issues << "#{source_status[:stale_objects]} objects are stale in target region"
    end
    
    # Size mismatches
    if source_status[:size_mismatches] > 0
      issues << "#{source_status[:size_mismatches]} objects have size mismatches"
    end
    
    # Overall sync percentage
    if source_status[:sync_percentage] < 95.0
      issues << "Overall sync rate: #{source_status[:sync_percentage]}% (below 95% threshold)"
    end
    
    issues
  end

  def stale_object?(source_obj, target_region)
    return false unless target_region.object_exists?(source_obj[:key], source_obj[:bucket])
    
    target_obj = target_region.get_object_metadata(source_obj[:key], source_obj[:bucket])
    return false unless target_obj
    
    # Consider object stale if target is more than 1 hour behind source
    time_diff = source_obj[:last_modified] - target_obj[:last_modified]
    time_diff > 3600 # 1 hour in seconds
  end

  def get_last_sync_time(source_region, target_region)
    # This would typically come from replication logs or metadata
    # For now, we'll use the most recent modification time from source
    source_region.get_last_modification_time
  end

  def calculate_overall_health(results)
    return 'healthy' if results.all? { |r| r[:status] == 'healthy' }
    return 'critical' if results.any? { |r| r[:status] == 'critical' || r[:status] == 'error' }
    
    'warning'
  end
end
