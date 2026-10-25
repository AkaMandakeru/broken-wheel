# frozen_string_literal: true

# One kind of the player's locker: a Locker::Catalogue.
class LockerResource < ApplicationResource
  attributes :kind, :equipped_key

  attribute(:kinds) { Locker::Catalogue::KINDS }

  attribute :owned do |catalogue|
    catalogue.owned.map do |cosmetic|
      CosmeticResource.new(cosmetic).serializable_hash.merge(equipped: cosmetic.key == catalogue.equipped_key)
    end
  end

  # Waiting to be taken with POST /me/locker/claim.
  attribute :claimable do |catalogue|
    catalogue.claimable.map do |cosmetic, reward|
      CosmeticResource.new(cosmetic).serializable_hash.merge(season: LockerResource.season(reward.season))
    end
  end

  # Not owned yet. `unlock` says where to earn it, or is null when no season
  # hands it out yet.
  attribute :locked do |catalogue|
    catalogue.locked.map do |cosmetic|
      reward = catalogue.unlock_hints[cosmetic.key]
      CosmeticResource.new(cosmetic).serializable_hash.merge(unlock: reward && LockerResource.unlock(reward))
    end
  end

  def self.season(season)
    { id: season.id, key: season.key, name: season.name }
  end

  def self.unlock(reward)
    {
      season: season(reward.season),
      unlock_kind: reward.unlock_kind,
      unlock_value: reward.unlock_value,
      label: I18n.t("seasons.unlock_kinds.#{reward.unlock_kind}", value: reward.unlock_value, default: reward.unlock_kind)
    }
  end
end
