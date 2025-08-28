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
        bidirectional_conflicts: source_status[:bidirectional_conflicts],
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
        bidirectional_conflicts: 0,
        last_sync_time: nil,
        issues: ["Failed to check replication: #{e.message}"],
        checked_at: Time.now
      }
    end
  end

  # Enhanced bidirectional sync with conflict resolution
  def perform_bidirectional_sync(region_a, region_b, options = {})
    dry_run = options[:dry_run] || false
    conflict_strategy = options[:conflict_strategy] || 'newest_wins' # 'newest_wins', 'region_a_wins', 'region_b_wins', 'manual'
    
    puts "\n🔄 PERFORMING BIDIRECTIONAL SYNC with #{conflict_strategy.upcase} strategy"
    puts "=" * 60
    
    if dry_run
      puts "DRY RUN MODE - No actual changes will be made"
    end
    
    start_time = Time.now
    sync_results = {
      a_to_b: { synced_objects: [], conflicts: [], errors: [] },
      b_to_a: { synced_objects: [], conflicts: [], errors: [] },
      conflicts_detected: [],
      conflicts_resolved: []
    }
    
    begin
      # Step 1: Detect bidirectional conflicts first
      conflicts = detect_bidirectional_conflicts(region_a, region_b)
      sync_results[:conflicts_detected] = conflicts
      
      if conflicts.any?
        puts "\n⚠️  DETECTED #{conflicts.length} BIDIRECTIONAL CONFLICTS:"
        conflicts.each do |conflict|
          puts "  - #{conflict[:key]}: #{conflict[:conflict_type]} (#{conflict[:details]})"
        end
        
        # Resolve conflicts based on strategy
        resolved_conflicts = resolve_conflicts(conflicts, conflict_strategy, dry_run)
        sync_results[:conflicts_resolved] = resolved_conflicts
        
        puts "\n✅ RESOLVED #{resolved_conflicts.length} conflicts using #{conflict_strategy} strategy"
      end
      
      # Step 2: Perform sync A → B (excluding resolved conflicts)
      puts "\n📁 Syncing A → B (#{region_a.name} → #{region_b.name})"
      puts "-" * 30
      
      a_to_b_result = perform_directional_sync_with_conflicts(
        region_a, region_b, resolved_conflicts, 'a_to_b', 
        dry_run: dry_run, force: options[:force]
      )
      sync_results[:a_to_b] = a_to_b_result
      
      # Step 3: Perform sync B → A (excluding resolved conflicts)
      puts "\n📁 Syncing B → A (#{region_b.name} → #{region_a.name})"
      puts "-" * 30
      
      b_to_a_result = perform_directional_sync_with_conflicts(
        region_b, region_a, resolved_conflicts, 'b_to_a', 
        dry_run: dry_run, force: options[:force]
      )
      sync_results[:b_to_a] = b_to_a_result
      
      duration = Time.now - start_time
      
      # Summary
      total_synced = a_to_b_result[:synced_count] + b_to_a_result[:synced_count]
      total_errors = a_to_b_result[:error_count] + b_to_a_result[:error_count]
      
      {
        success: true,
        total_synced_count: total_synced,
        total_error_count: total_errors,
        conflicts_detected: conflicts.length,
        conflicts_resolved: resolved_conflicts.length,
        a_to_b_synced: a_to_b_result[:synced_count],
        b_to_a_synced: b_to_a_result[:synced_count],
        duration: duration,
        detailed_results: sync_results
      }
      
    rescue StandardError => e
      {
        success: false,
        error: "Bidirectional sync failed: #{e.message}",
        duration: Time.now - start_time,
        detailed_results: sync_results
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

  # Detect conflicts in bidirectional sync
  def detect_bidirectional_conflicts(region_a, region_b)
    conflicts = []
    
    # Get objects from both regions
    objects_a = region_a.list_objects
    objects_b = region_b.list_objects
    
    # Find common objects (exist in both regions)
    common_objects = find_common_objects(objects_a, objects_b)
    
    common_objects.each do |obj_a, obj_b|
      conflict = analyze_bidirectional_conflict(obj_a, obj_b, region_a, region_b)
      conflicts << conflict if conflict
    end
    
    conflicts
  end

  def find_common_objects(objects_a, objects_b)
    common = []
    
    objects_a.each do |obj_a|
      obj_b = objects_b.find { |o| o[:key] == obj_a[:key] }
      common << [obj_a, obj_b] if obj_b
    end
    
    common
  end

  def analyze_bidirectional_conflict(obj_a, obj_b, region_a, region_b)
    key = obj_a[:key]
    
    # Compare timestamps
    time_a = parse_time(obj_a[:last_modified])
    time_b = parse_time(obj_b[:last_modified])
    time_diff = (time_a - time_b).abs
    
    # Compare content hashes
    etag_a = obj_a[:etag]
    etag_b = obj_b[:etag]
    content_differs = etag_a != etag_b
    
    # Compare sizes
    size_a = obj_a[:size]
    size_b = obj_b[:size]
    size_differs = size_a != size_b
    
    # Determine conflict type
    if content_differs || size_differs
      if time_diff < 60 # Same timestamp (within 1 minute) but different content
        {
          key: key,
          conflict_type: 'same_timestamp_different_content',
          details: "Modified simultaneously in both regions",
          region_a_etag: etag_a,
          region_b_etag: etag_b,
          region_a_size: size_a,
          region_b_size: size_b,
          region_a_time: time_a,
          region_b_time: time_b,
          time_diff: time_diff,
          requires_resolution: true
        }
      elsif content_differs
        newer_region = time_a > time_b ? 'region_a' : 'region_b'
        {
          key: key,
          conflict_type: 'content_mismatch_with_time_diff',
          details: "Different content, #{newer_region} is newer",
          region_a_etag: etag_a,
          region_b_etag: etag_b,
          region_a_size: size_a,
          region_b_size: size_b,
          region_a_time: time_a,
          region_b_time: time_b,
          newer_region: newer_region,
          time_diff: time_diff,
          requires_resolution: true
        }
      end
    else
      # Content is the same, no conflict
      nil
    end
  end

  def resolve_conflicts(conflicts, strategy, dry_run)
    resolved = []
    
    conflicts.each do |conflict|
      resolution = case strategy
      when 'newest_wins'
        resolve_conflict_newest_wins(conflict)
      when 'region_a_wins'
        resolve_conflict_region_wins(conflict, 'region_a')
      when 'region_b_wins'
        resolve_conflict_region_wins(conflict, 'region_b')
      when 'largest_wins'
        resolve_conflict_largest_wins(conflict)
      when 'manual'
        resolve_conflict_manual(conflict, dry_run)
      else
        resolve_conflict_newest_wins(conflict) # Default fallback
      end
      
      resolved << resolution if resolution
    end
    
    resolved
  end

  def resolve_conflict_newest_wins(conflict)
    if conflict[:conflict_type] == 'same_timestamp_different_content'
      # If timestamps are the same, fall back to size or region priority
      winner = conflict[:region_a_size] >= conflict[:region_b_size] ? 'region_a' : 'region_b'
    else
      winner = conflict[:newer_region] || 'region_a'
    end
    
    {
      key: conflict[:key],
      resolution_strategy: 'newest_wins',
      winner: winner,
      action: "Use #{winner} version as source of truth",
      conflict_details: conflict
    }
  end

  def resolve_conflict_region_wins(conflict, winning_region)
    {
      key: conflict[:key],
      resolution_strategy: "#{winning_region}_wins",
      winner: winning_region,
      action: "Use #{winning_region} version as source of truth",
      conflict_details: conflict
    }
  end

  def resolve_conflict_largest_wins(conflict)
    winner = conflict[:region_a_size] >= conflict[:region_b_size] ? 'region_a' : 'region_b'
    
    {
      key: conflict[:key],
      resolution_strategy: 'largest_wins',
      winner: winner,
      action: "Use #{winner} version (larger file) as source of truth",
      conflict_details: conflict
    }
  end

  def resolve_conflict_manual(conflict, dry_run)
    if dry_run
      return {
        key: conflict[:key],
        resolution_strategy: 'manual',
        winner: 'region_a', # Default for dry run
        action: "Would prompt user for manual resolution",
        conflict_details: conflict
      }
    end
    
    # Interactive conflict resolution
    puts "\n🔥 CONFLICT REQUIRES MANUAL RESOLUTION:"
    puts "  File: #{conflict[:key]}"
    puts "  Conflict: #{conflict[:conflict_type]}"
    puts "  Details: #{conflict[:details]}"
    puts ""
    puts "  Region A: size=#{conflict[:region_a_size]}, modified=#{conflict[:region_a_time]}, etag=#{conflict[:region_a_etag]}"
    puts "  Region B: size=#{conflict[:region_b_size]}, modified=#{conflict[:region_b_time]}, etag=#{conflict[:region_b_etag]}"
    puts ""
    puts "  Choose resolution:"
    puts "  1) Use Region A version"
    puts "  2) Use Region B version"
    puts "  3) Skip this file"
    print "  Enter choice (1-3): "
    
    choice = gets.chomp
    
    case choice
    when '1'
      { key: conflict[:key], resolution_strategy: 'manual', winner: 'region_a', action: "User chose Region A", conflict_details: conflict }
    when '2'
      { key: conflict[:key], resolution_strategy: 'manual', winner: 'region_b', action: "User chose Region B", conflict_details: conflict }
    when '3'
      { key: conflict[:key], resolution_strategy: 'manual', winner: 'skip', action: "User chose to skip", conflict_details: conflict }
    else
      puts "Invalid choice, defaulting to Region A"
      { key: conflict[:key], resolution_strategy: 'manual', winner: 'region_a', action: "Default to Region A", conflict_details: conflict }
    end
  end

  def perform_directional_sync_with_conflicts(source_region, target_region, resolved_conflicts, direction, options = {})
    dry_run = options[:dry_run] || false
    force = options[:force] || false
    
    start_time = Time.now
    synced_objects = []
    errors = []
    skipped_count = 0
    
    # Get objects that need syncing
    replication_status = source_region.get_replication_status(target_region)
    objects_needing_sync = get_objects_needing_sync(replication_status[:detailed_status])
    
    # Apply conflict resolutions
    objects_needing_sync = apply_conflict_resolutions(objects_needing_sync, resolved_conflicts, direction)
    
    if objects_needing_sync.empty?
      return {
        success: true,
        synced_count: 0,
        skipped_count: 0,
        error_count: 0,
        synced_objects: [],
        errors: [],
        duration: Time.now - start_time,
        message: "All objects are already in sync or resolved via conflict resolution"
      }
    end
    
    puts "Found #{objects_needing_sync.length} objects that need syncing (after conflict resolution)"
    
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
  end

  def apply_conflict_resolutions(objects_needing_sync, resolved_conflicts, direction)
    # Remove objects that were resolved as conflicts and should be handled differently
    conflict_keys = resolved_conflicts.map { |c| c[:key] }
    
    # Filter out objects that are handled by conflict resolution
    filtered_objects = objects_needing_sync.reject do |obj|
      conflict_keys.include?(obj[:key])
    end
    
    # Add back objects where this direction should win based on conflict resolution
    resolved_conflicts.each do |resolution|
      next if resolution[:winner] == 'skip'
      
      should_sync = case direction
      when 'a_to_b'
        resolution[:winner] == 'region_a'
      when 'b_to_a'
        resolution[:winner] == 'region_b'
      else
        false
      end
      
      if should_sync
        # Add this object back to sync list with special handling
        filtered_objects << {
          key: resolution[:key],
          status: 'conflict_resolved',
          issue: "Resolved conflict using #{resolution[:resolution_strategy]} strategy",
          resolution_details: resolution
        }
      end
    end
    
    filtered_objects
  end

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
    when 'conflict_resolved'
      sync_conflict_resolved_object(source_region, target_region, obj_detail, dry_run)
    else
      {
        success: false,
        reason: "Unknown sync status: #{obj_detail[:status]}"
      }
    end
  end

  def sync_conflict_resolved_object(source_region, target_region, obj_detail, dry_run)
    if dry_run
      return {
        success: true,
        action: "Would sync conflict-resolved object",
        object_info: { key: obj_detail[:key] }
      }
    end
    
    # Get object content from source
    content = source_region.client.get_object_content(obj_detail[:key])
    
    # Upload to target
    upload_result = target_region.client.put_object(
      obj_detail[:key], 
      content
    )
    
    if upload_result[:success]
      {
        success: true,
        action: "Synced conflict-resolved object",
        object_info: {
          key: obj_detail[:key],
          size: upload_result[:size],
          resolution: obj_detail[:resolution_details][:resolution_strategy]
        }
      }
    else
      {
        success: false,
        reason: "Upload failed: #{upload_result[:error]}"
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

  def parse_time(time_obj)
    return time_obj if time_obj.is_a?(Time)
    return Time.parse(time_obj) if time_obj.is_a?(String)
    time_obj
  rescue StandardError
    Time.at(0) # Fallback for unparseable times
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
    
    # Bidirectional conflicts
    if source_status[:bidirectional_conflicts] > 0
      issues << "#{source_status[:bidirectional_conflicts]} bidirectional conflicts detected"
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
