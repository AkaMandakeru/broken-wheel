# frozen_string_literal: true

# Community milestones belong to the whole season, not to any one runner.
# Attributing them to an arbitrary participant would misreport who did what.
class AllowCommunitySeasonActivities < ActiveRecord::Migration[8.1]
  def change
    change_column_null :season_activities, :user_id, true
  end
end
