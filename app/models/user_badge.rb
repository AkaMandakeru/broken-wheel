class UserBadge < ApplicationRecord
  belongs_to :user
  belongs_to :badge
  belongs_to :challenge, optional: true

  after_create_commit :push_achievement_notification

  private

  def push_achievement_notification
    PushNotifier.notify(
      user,
      title: I18n.t("push.achievement.title"),
      body: I18n.t("push.achievement.body", name: badge.display_name),
      path: Rails.application.routes.url_helpers.achievements_path,
      tag: "achievement-#{id}"
    )
  end
end
