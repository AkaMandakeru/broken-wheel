# frozen_string_literal: true

module Strava
  class ActivityImporter
    PROVIDER = "strava"

    SPORT_MAP = {
      "Run"              => "run",
      "TrailRun"         => "run",
      "VirtualRun"       => "run",
      "Ride"             => "bike",
      "VirtualRide"      => "bike",
      "EBikeRide"        => "bike",
      "MountainBikeRide" => "bike",
      "Soccer"           => "soccer"
    }.freeze

    Result = Struct.new(:imported, :skipped, :achievements, keyword_init: true)

    def initialize(user, client: nil, after: nil)
      @user = user
      @client = client || StravaService.new(user)
      @after = after
    end

    def call
      imported = 0
      skipped = 0

      @client.activities(after: @after) do |activity|
        if upsert(activity)
          imported += 1
        else
          skipped += 1
        end
      end

      achievements = finalize!

      Result.new(imported: imported, skipped: skipped, achievements: achievements)
    end

    def import_one(activity)
      return false unless upsert(activity)

      finalize!
      true
    end

    # Imports a batch and recomputes progress exactly once at the end, rather
    # than once per activity. A 40-activity import used to fan out 40 recalcs.
    def import_many(activities)
      imported = activities.count { |activity| upsert(activity) }
      achievements = finalize!
      Result.new(imported: imported, skipped: activities.size - imported, achievements: achievements)
    end

    private

    def upsert(activity)
      external_id = activity.id.to_s
      return false if external_id.blank?

      sport = SPORT_MAP[activity.sport_type]
      return false if sport.nil?

      workout = @user.workouts.find_or_initialize_by(provider: PROVIDER, external_id: external_id)
      workout.assign_attributes(
        sport: sport,
        distance_km: distance_km(activity),
        duration_minutes: duration_minutes(activity),
        workout_date: workout_date(activity),
        started_at_local: started_at_local(activity),
        started_at: started_at_utc(activity),
        start_time_known: started_at_local(activity).present?,
        start_minute_of_day: Workout.minute_of_day_from(started_at_local(activity)),
        elevation_gain_m: field(activity, :total_elevation_gain),
        calories: field(activity, :calories),
        moving_time_seconds: field(activity, :moving_time),
        elapsed_time_seconds: field(activity, :elapsed_time),
        route_signature: route_signature(activity),
        raw_data: activity.to_h
      )

      auto_assign_challenge!(workout) if workout.challenge_participation_id.nil?

      workout.save!
      true
    rescue ActiveRecord::RecordNotUnique
      false
    end

    def auto_assign_challenge!(workout)
      participation = @user.challenge_participations
                           .joins(:challenge)
                           .where(challenges: { status: "active", sport: workout.sport })
                           .where(completed_at: nil)
                           .first
      workout.challenge_participation = participation if participation
    end

    def finalize!
      recompute_active_challenges!
      Season.active.find_each { |season| SeasonRecalcJob.enqueue_debounced(@user.id, season.id) }
      AchievementChecker.new(@user).check_all!
    end

    def recompute_active_challenges!
      @user.challenge_participations
           .joins(:challenge)
           .where(challenges: { status: "active" })
           .where(completed_at: nil)
           .find_each do |participation|
        RecomputeChallengeProgress.new(participation).call
      end
    end

    def distance_km(activity)
      meters = activity.distance.to_f
      (meters / 1000.0).round(3)
    end

    def duration_minutes(activity)
      seconds = activity.moving_time.to_i
      return 0 if seconds.zero?

      (seconds / 60.0).round
    end

    def workout_date(activity)
      (raw_time(activity, :start_date_local) || raw_time(activity, :start_date))&.to_date || Date.current
    end

    def started_at_local(activity)
      @started_at_local ||= {}
      @started_at_local[activity.id] ||= raw_time(activity, :start_date_local) || raw_time(activity, :start_date)
    end

    def started_at_utc(activity)
      raw_time(activity, :start_date) || started_at_local(activity)
    end

    def route_signature(activity)
      Seasons::RawPayload.route_signature(activity)
    end

    def raw_time(activity, key)
      Seasons::RawPayload.time(field(activity, key))
    end

    def field(activity, key)
      Seasons::RawPayload.field(activity, key)
    end
  end
end
