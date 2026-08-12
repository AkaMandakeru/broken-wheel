# frozen_string_literal: true

namespace :seasons do
  desc "Backfill workout start times, elevation and effort details from stored Strava payloads"
  task backfill_workout_details: :environment do
    updated = 0
    manual = 0

    Workout.find_each do |workout|
      raw = workout.raw_data
      if workout.provider == "strava" && raw.present?
        local = Seasons::RawPayload.time(raw["start_date_local"]) || Seasons::RawPayload.time(raw["start_date"])
        workout.assign_attributes(
          started_at_local: local,
          started_at: Seasons::RawPayload.time(raw["start_date"]) || local,
          start_time_known: local.present?,
          start_minute_of_day: Workout.minute_of_day_from(local),
          elevation_gain_m: raw["total_elevation_gain"],
          calories: raw["calories"],
          moving_time_seconds: raw["moving_time"],
          elapsed_time_seconds: raw["elapsed_time"],
          route_signature: Seasons::RawPayload.route_signature(raw)
        )
        updated += 1
      else
        # Manual entries have no clock time — stamp midday so ordering works but
        # leave start_time_known false so hour challenges skip them.
        next if workout.started_at_local.present?

        local = workout.workout_date&.to_time(:utc)&.+(12.hours)
        workout.assign_attributes(
          started_at_local: local,
          start_time_known: false,
          start_minute_of_day: Workout.minute_of_day_from(local),
          moving_time_seconds: workout.moving_time_seconds || (workout.duration_minutes.to_i * 60),
          elapsed_time_seconds: workout.elapsed_time_seconds || (workout.duration_minutes.to_i * 60)
        )
        manual += 1
      end

      workout.save!(validate: false)
    end

    puts "✅ Backfilled #{updated} Strava workouts and #{manual} manual workouts."
  end

  desc "Import a season blueprint: rails 'seasons:import[season_8_legacy_of_champions]'"
  task :import, [ :key ] => :environment do |_t, args|
    key = args[:key].presence || "season_8_legacy_of_champions"
    season = Seasons::BlueprintImporter.call(key)
    puts "✅ Imported season #{season.name} (#{season.key})"
    puts "   challenges: #{season.season_challenges.count} · rewards: #{season.season_rewards.count} · " \
         "objectives: #{season.season_objectives.count} · dailies: #{DailyChallengeTemplate.where(season: season).count}"
  end

  desc "Recalculate every participation for a season: rails 'seasons:recalc[season_8_legacy_of_champions]'"
  task :recalc, [ :key ] => :environment do |_t, args|
    season = args[:key].present? ? Season.find_by!(key: args[:key]) : Season.active.first
    abort "No season found" unless season

    season.season_participations.find_each do |participation|
      SeasonProgressService.new(participation).recalculate
    end
    puts "✅ Recalculated #{season.season_participations.count} participations for #{season.name}"
  end

  desc "Report the XP a completionist and a realistic player would earn, against the level curve"
  task :simulate, [ :key ] => :environment do |_t, args|
    season = args[:key].present? ? Season.find_by!(key: args[:key]) : Season.active.first
    abort "No season found" unless season

    Seasons::XpSimulator.new(season).report.each { |line| puts line }
  end
end
