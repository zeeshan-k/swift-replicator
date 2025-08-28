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
      
      # Calculate metrics
      total_objects = source_status[:total_objects]
      replicated_objects = source_status[:replicated_objects]
      sync_percentage = total_objects > 0 ? (replicated_objects.to_f / total_objects * 100).round(2) : 100.0
      
      # Determine overall status
      status = determine_replication_status(sync_percentage, source_region, target_region)
      
      # Collect any issues
      issues = collect_replication_issues(source_status, target_region, sync_percentage)
      
      {
        source: source_region,
        target: target_region,
        status: status,
        total_objects: total_objects,
        objects_in_sync: replicated_objects,
        sync_percentage: sync_percentage,
        last_sync_time: get_last_sync_time(source_region, target_region),
        issues: issues,
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
