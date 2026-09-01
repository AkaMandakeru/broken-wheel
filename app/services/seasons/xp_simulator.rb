# frozen_string_literal: true

module Seasons
  # Reports what the season's content is actually worth against its level curve.
  #
  # A battle pass whose top level is unreachable — or trivially reachable — is a
  # tuning bug you only discover after players have spent a month on it. This
  # turns that into something checkable before launch.
  class XpSimulator
    # Share of each content type a realistically engaged (not completionist)
    # player finishes.
    ENGAGED_RATES = {
      dailies: 0.6,
      weeklies: 0.75,
      monthlies: 0.5,
      legacy: 0.8,
      elite: 0.0,
      hidden: 0.2
    }.freeze

    def initialize(season)
      @season = season
      @curve = season.level_curve_object
    end

    def report
      lines = [ "", "#{@season.name} — XP budget vs. level curve", "=" * 58 ]

      lines << format_row("Source", "Max", "Engaged")
      lines << "-" * 58
      budget.each { |label, (max, engaged)| lines << format_row(label, max, engaged) }
      lines << "-" * 58
      lines << format_row("TOTAL", totals[:max], totals[:engaged])
      lines << ""
      lines << "Level curve: 1..#{@curve.max_level}, top level at #{@curve.floor_for(@curve.max_level)} XP"
      lines << "  completionist reaches level #{@curve.level_for(totals[:max])}"
      lines << "  engaged player reaches level #{@curve.level_for(totals[:engaged])}"
      lines << "  without elite content:      level #{@curve.level_for(totals[:max] - budget['Elite challenges'].first)}"
      lines << ""
      lines.concat(warnings)
      lines
    end

    private

    def budget
      @budget ||= {
        "Daily challenges" => pair(daily_max, ENGAGED_RATES[:dailies]),
        "Weekly challenges" => pair(category_xp("weekly"), ENGAGED_RATES[:weeklies]),
        "Monthly challenges" => pair(category_xp("monthly"), ENGAGED_RATES[:monthlies]),
        "Elite challenges" => pair(category_xp("elite"), ENGAGED_RATES[:elite]),
        "Hidden challenges" => pair(category_xp("hidden"), ENGAGED_RATES[:hidden]),
        "Legacy missions" => pair(@season.season_objectives.legacy.sum(:xp_reward), ENGAGED_RATES[:legacy]),
        "Other objectives" => pair(@season.season_objectives.standard.sum(:xp_reward), 0.5),
        "Workouts & bonuses" => pair(baseline_xp, 0.8)
      }
    end

    def pair(max, rate)
      [ max.to_i, (max.to_i * rate).round ]
    end

    def totals
      @totals ||= {
        max: budget.values.sum(&:first),
        engaged: budget.values.sum(&:last)
      }
    end

    def category_xp(category)
      @season.season_challenges.of_category(category).sum(:xp_reward)
    end

    # Three dailies a day for every day of the season — but the draw can never
    # hand out more distinct templates than the pool holds, so a season with one
    # template offers one a day. Budgeting the full three there overstated the
    # XP ceiling threefold and made an unreachable top level look reachable.
    def daily_max
      templates = DailyChallengeTemplate.active.for_season(@season)
      return 0 if templates.empty?

      per_day = [ DailyChallenges::Assigner::PER_DAY, templates.count ].min
      average = templates.average(:xp_reward).to_f
      (average * per_day * season_days).round
    end

    def season_days
      return 30 unless @season.starts_at && @season.ends_at

      (@season.ends_at.to_date - @season.starts_at.to_date).to_i + 1
    end

    # Workout XP for a committed month, plus streak, consistency and club bonuses.
    def baseline_xp
      workouts = 25
      (workouts * SeasonProgressService::WORKOUT_XP) +
        (SeasonProgressService::STREAK_CAP_WEEKS * SeasonProgressService::STREAK_XP_PER_WEEK) +
        (5 * SeasonProgressService::CONSISTENCY_XP_PER_WEEK) +
        SeasonProgressService::CLUB_BONUS
    end

    def warnings
      messages = []
      top = @curve.floor_for(@curve.max_level)
      without_elite = totals[:max] - budget["Elite challenges"].first

      if without_elite < top
        messages << "⚠️  Top level is unreachable without elite content " \
                    "(#{without_elite} XP available vs #{top} needed). " \
                    "Elite unlocks at level 20 and carries its own reward, so the pass should " \
                    "top out without it — raise weekly/monthly XP or lower the curve."
      end

      if totals[:engaged] >= top
        messages << "⚠️  An engaged, non-completionist player maxes the pass. Consider a steeper curve."
      end

      messages << "✅ Curve looks balanced." if messages.empty?
      messages
    end

    def format_row(label, max, engaged)
      format("%-26s %14s %14s", label, max, engaged)
    end
  end
end
