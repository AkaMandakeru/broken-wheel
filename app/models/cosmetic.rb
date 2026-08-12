# frozen_string_literal: true

class Cosmetic < ApplicationRecord
  has_many :user_cosmetics, dependent: :destroy
  has_many :users, through: :user_cosmetics

  # Kinds we can draw today render on the profile; the rest are collectible now
  # and displayable once their art exists.
  KINDS = %w[banner avatar frame trail name_color effect emoji_pack outfit border].freeze
  RENDERABLE_KINDS = %w[banner frame name_color border].freeze
  RARITIES = %w[common rare epic legendary].freeze

  validates :key, presence: true, uniqueness: true
  validates :kind, inclusion: { in: KINDS }
  validates :rarity, inclusion: { in: RARITIES }

  scope :renderable, -> { where(renderable: true) }
  scope :of_kind, ->(kind) { where(kind: kind) }

  def display_name
    I18n.t("cosmetics.items.#{key}", default: name.presence || key.to_s.humanize)
  end

  def rarity_label
    I18n.t("cosmetics.rarities.#{rarity}", default: rarity.capitalize)
  end
end
