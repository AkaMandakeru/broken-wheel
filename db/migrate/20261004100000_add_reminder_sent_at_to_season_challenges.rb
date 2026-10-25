class AddReminderSentAtToSeasonChallenges < ActiveRecord::Migration[8.1]
  def change
    add_column :season_challenges, :reminder_sent_at, :datetime
  end
end
