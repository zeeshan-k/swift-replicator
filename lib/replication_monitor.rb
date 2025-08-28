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

  # Perform actual synchronization between regions
  def perform_sync(source_region, target_region, options = {})
    dry_run = options[:dry_run] || false
    force = options[:force] || false
    
    puts "#{dry_run ? 'DRY RUN: ' : ''}Syncing #{source_region.name} -> #{target_region.name}"
    
    start_time = Time.now
    synced_objects = []
    errors = []
    skipped_count = 0
    
    begin
      # Get replication status to identify objects that need syncing
      replication_status = source_region.get_replication_status(target_region)
      objects_needing_sync = get_objects_needing_sync(replication_status[:detailed_status])
      
      if objects_needing_sync.empty?
        return {
          success: true,
          synced_count: 0,
          skipped_count: 0,
          error_count: 0,
          synced_objects: [],
          errors: [],
          duration: Time.now - start_time,
          message: "All objects are already in sync"
        }
      end
      
      puts "Found #{objects_needing_sync.length} objects that need syncing"
      
      # Check if sync should proceed
      if requires_force_sync?(objects_needing_sync) && !force
        return {
          success: false,
          error: "Sync requires --force flag due to critical issues (content mismatches or large number of objects)",
          synced_count: 0,
          skipped_count: 0,
          error_count: 0,
          synced_objects: [],
          errors: []
        }
      end
      
      objects_needing_sync.each_with_index do |obj_detail, index|
        progress_percentage = ((index + 1).to_f / objects_needing_sync.length * 100).round(1)
        puts "  Progress: #{progress_percentage}% (#{index + 1}/#{objects_needing_sync.length})"
        
        begin
          sync_result = sync_single_object(
            source_region, 
            target_region, 
            obj_detail, 
            dry_run: dry_run
          )
          
          if sync_result[:success]
            synced_objects << sync_result[:object_info]
            puts "    ✅ #{sync_result[:action]}: #{obj_detail[:key]}"
          else
            skipped_count += 1
            puts "    ⏭️  Skipped: #{obj_detail[:key]} (#{sync_result[:reason]})"
          end
          
        rescue StandardError => e
          error_msg = "Failed to sync #{obj_detail[:key]}: #{e.message}"
          errors << error_msg
          puts "    ❌ #{error_msg}"
        end
      end
      
      duration = Time.now - start_time
      
      {
        success: true,
        synced_count: synced_objects.length,
        skipped_count: skipped_count,
        error_count: errors.length,
        synced_objects: synced_objects,
        errors: errors,
        duration: duration
      }
      
    rescue StandardError => e
      {
        success: false,
        error: "Sync operation failed: #{e.message}",
        synced_count: synced_objects.length,
        skipped_count: skipped_count,
        error_count: errors.length + 1,
        synced_objects: synced_objects,
        errors: errors + [e.message],
        duration: Time.now - start_time
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

  def get_objects_needing_sync(detailed_status)
    # Return objects that are not in 'replicated' status
    detailed_status.select { |detail| detail[:status] != 'replicated' }
  end

  def requires_force_sync?(objects_needing_sync)
    # Require --force if there are content mismatches or too many objects
    content_mismatches = objects_needing_sync.count { |obj| obj[:status] == 'content_mismatch' }
    large_sync = objects_needing_sync.length > 100
    
    content_mismatches > 0 || large_sync
  end

  def sync_single_object(source_region, target_region, obj_detail, options = {})
    dry_run = options[:dry_run] || false
    
    case obj_detail[:status]
    when 'missing'
      sync_missing_object(source_region, target_region, obj_detail, dry_run)
    when 'stale'
      sync_stale_object(source_region, target_region, obj_detail, dry_run)
    when 'content_mismatch'
      sync_content_mismatch(source_region, target_region, obj_detail, dry_run)
    when 'size_mismatch'
      sync_size_mismatch(source_region, target_region, obj_detail, dry_run)
    else
      {
        success: false,
        reason: "Unknown sync status: #{obj_detail[:status]}"
      }
    end
  end

  def sync_missing_object(source_region, target_region, obj_detail, dry_run)
    if dry_run
      return {
        success: true,
        action: "Would copy missing object",
        object_info: { key: obj_detail[:key], container: obj_detail[:container] }
      }
    end
    
    # Get object content from source
    content = source_region.client.get_object_content(obj_detail[:key], obj_detail[:container])
    
    # Upload to target
    upload_result = target_region.client.put_object(
      obj_detail[:key], 
      content, 
      obj_detail[:container]
    )
    
    if upload_result[:success]
      {
        success: true,
        action: "Copied missing object",
        object_info: {
          key: obj_detail[:key],
          container: obj_detail[:container],
          size: upload_result[:size]
        }
      }
    else
      {
        success: false,
        reason: "Upload failed: #{upload_result[:error]}"
      }
    end
  end

  def sync_stale_object(source_region, target_region, obj_detail, dry_run)
    if dry_run
      lag_info = obj_detail[:replication_lag] ? " (#{obj_detail[:replication_lag]}s behind)" : ""
      return {
        success: true,
        action: "Would update stale object#{lag_info}",
        object_info: { key: obj_detail[:key], container: obj_detail[:container] }
      }
    end
    
    # Update stale object with latest version from source
    content = source_region.client.get_object_content(obj_detail[:key], obj_detail[:container])
    
    upload_result = target_region.client.put_object(
      obj_detail[:key], 
      content, 
      obj_detail[:container]
    )
    
    if upload_result[:success]
      {
        success: true,
        action: "Updated stale object",
        object_info: {
          key: obj_detail[:key],
          container: obj_detail[:container],
          size: upload_result[:size]
        }
      }
    else
      {
        success: false,
        reason: "Update failed: #{upload_result[:error]}"
      }
    end
  end

  def sync_content_mismatch(source_region, target_region, obj_detail, dry_run)
    if dry_run
      etag_info = " (source: #{obj_detail[:source_etag]}, target: #{obj_detail[:target_etag]})"
      return {
        success: true,
        action: "Would fix content mismatch#{etag_info}",
        object_info: { key: obj_detail[:key], container: obj_detail[:container] }
      }
    end
    
    # Replace target object with source version
    content = source_region.client.get_object_content(obj_detail[:key], obj_detail[:container])
    
    upload_result = target_region.client.put_object(
      obj_detail[:key], 
      content, 
      obj_detail[:container]
    )
    
    if upload_result[:success]
      {
        success: true,
        action: "Fixed content mismatch",
        object_info: {
          key: obj_detail[:key],
          container: obj_detail[:container],
          size: upload_result[:size]
        }
      }
    else
      {
        success: false,
        reason: "Content fix failed: #{upload_result[:error]}"
      }
    end
  end

  def sync_size_mismatch(source_region, target_region, obj_detail, dry_run)
    if dry_run
      size_info = " (source: #{obj_detail[:source_size]}, target: #{obj_detail[:target_size]})"
      return {
        success: true,
        action: "Would fix size mismatch#{size_info}",
        object_info: { key: obj_detail[:key], container: obj_detail[:container] }
      }
    end
    
    # Replace target object with source version
    content = source_region.client.get_object_content(obj_detail[:key], obj_detail[:container])
    
    upload_result = target_region.client.put_object(
      obj_detail[:key], 
      content, 
      obj_detail[:container]
    )
    
    if upload_result[:success]
      {
        success: true,
        action: "Fixed size mismatch",
        object_info: {
          key: obj_detail[:key],
          container: obj_detail[:container],
          size: upload_result[:size]
        }
      }
    else
      {
        success: false,
        reason: "Size fix failed: #{upload_result[:error]}"
      }
    end
  end

  def determine_replication_status(sync_percentage, source_region, target_region)
    return 'error' if sync_percentage.nil?
    return 'healthy' if sync_percentage >= 95.0
    return 'warning' if sync_percentage >= 80.0
    
    'critical'
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
