# frozen_string_literal: true

class Cosmetic < ApplicationRecord
  has_many :user_cosmetics, dependent: :destroy
  has_many :users, through: :user_cosmetics

  # Profile banners and avatar frames are pictures an operator uploads.
  has_one_attached :image

  # Kinds we can draw today render on the profile; the rest are collectible now
  # and displayable once their art exists.
  KINDS = %w[banner avatar frame trail name_color effect emoji_pack outfit border].freeze
  RENDERABLE_KINDS = %w[banner frame name_color border].freeze
  RARITIES = %w[common rare epic legendary].freeze

  # The kinds whose art is an uploaded picture rather than a CSS class.
  PICTURE_KINDS = %w[banner frame].freeze

  IMAGE_CONTENT_TYPES = %w[image/png image/jpeg image/webp image/gif].freeze
  MAX_IMAGE_BYTES = 5.megabytes

  validates :key, presence: true, uniqueness: true
  validates :kind, inclusion: { in: KINDS }
  validates :rarity, inclusion: { in: RARITIES }
  validate :image_is_a_supported_picture

  scope :renderable, -> { where(renderable: true) }
  scope :of_kind, ->(kind) { where(kind: kind) }
  scope :banners, -> { of_kind("banner") }
  scope :frames, -> { of_kind("frame") }
  scope :ordered, -> { order(:position, :key) }
  scope :with_artwork, -> { includes(image_attachment: :blob) }

  def display_name
    I18n.t("cosmetics.items.#{key}", default: name.presence || key.to_s.humanize)
  end

  def rarity_label
    I18n.t("cosmetics.rarities.#{rarity}", default: rarity.capitalize)
  end

  def picture?
    PICTURE_KINDS.include?(kind)
  end

  # Deliberately not a validation. A season blueprint declares its cosmetics by
  # key long before anyone draws them (Seasons::BlueprintImporter creates the
  # rows straight from YAML), so a picture kind without a picture is a normal
  # intermediate state. Every surface that renders one falls back to the CSS
  # gradient instead, the same way a season without a cover does.
  def artwork?
    picture? && image.attached?
  end

  private

  def image_is_a_supported_picture
    return unless image.attached?

    unless IMAGE_CONTENT_TYPES.include?(image.blob.content_type)
      errors.add(:image, :invalid_type, types: "PNG, JPEG, WEBP, GIF")
    end

    return unless image.blob.byte_size > MAX_IMAGE_BYTES

    errors.add(:image, :too_large, size: "#{MAX_IMAGE_BYTES / 1.megabyte} MB")
  end
end
