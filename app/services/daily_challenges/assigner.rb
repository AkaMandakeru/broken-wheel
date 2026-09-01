# frozen_string_literal: true

module DailyChallenges
  # Picks the three challenges a user is offered on a given day.
  #
  # The draw is deterministic: seeded from (user, season, date), so the job and a
  # lazy page visit always produce the same set. That means assignment can run
  # twice without ever changing what a user was already shown.
  class Assigner
    PER_DAY = 3

    def self.call(user, season, date: nil)
      new(user, season, date: date).call
    end

    def initialize(user, season, date: nil)
      @user = user
      @season = season
      @date = date || season.current_date
    end

    def call
      return existing if existing.size >= PER_DAY
      return [] if outside_season?

      picks = draw
      picks.each { |template| assign(template) }
      reload
    end

    private

    def outside_season?
      window = @season.date_window
      window.present? && !window.cover?(@date)
    end

    def existing
      @existing ||= reload
    end

    def reload
      @existing = DailyChallengeAssignment.where(user_id: @user.id, season_id: @season.id, challenge_date: @date)
                                          .includes(:daily_challenge_template)
                                          .to_a
    end

    def draw
      pool = eligible_templates - existing.map(&:daily_challenge_template)
      return [] if pool.empty?

      weighted = pool.flat_map { |template| Array.new(template.weight, template) }
      random = Random.new(seed)

      picks = []
      remaining = PER_DAY - existing.size
      while picks.size < remaining && weighted.any?
        chosen = weighted.sample(random: random)
        picks << chosen
        weighted.reject! { |t| t.id == chosen.id }
      end
      picks
    end

    # Stable per (user, season, day) — the same three challenges no matter how
    # many times this runs.
    def seed
      Digest::MD5.hexdigest("#{@user.id}-#{@season.id}-#{@date}").to_i(16)
    end

    # Users whose workouts carry no clock time can never satisfy an hour-based
    # daily, so those templates are withheld rather than handed out unwinnable.
    def eligible_templates
      scope = DailyChallengeTemplate.active.for_season(@season)
      scope = scope.timeless unless timed_workouts?
      scope.order(:id).to_a
    end

    def timed_workouts?
      return @timed_workouts if defined?(@timed_workouts)

      @timed_workouts = @user.workouts.with_known_start_time.exists?
    end

    def assign(template)
      DailyChallengeAssignment.create!(
        user: @user,
        season: @season,
        daily_challenge_template: template,
        challenge_date: @date
      )

      SeasonAnalytics.track(
        user: @user, event: "season_daily_assigned", season: @season,
        template_key: template.key, challenge_date: @date.to_s
      )
    rescue ActiveRecord::RecordNotUnique
      nil # already assigned by a concurrent request
    end
  end
end
