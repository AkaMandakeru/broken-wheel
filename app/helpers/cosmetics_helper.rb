# frozen_string_literal: true

module CosmeticsHelper
  # A resized variant of a cosmetic's artwork, or nil when there isn't one.
  #
  # Mirrors `season_image_source`: an upload that cannot be transformed would
  # otherwise raise at render time and take the whole profile down, so a broken
  # blob degrades to the gradient fallback instead.
  #
  # Banners are cropped to fill their slot. Frames must not be — they are
  # transparent rings, and a fill crop eats the ornament.
  def cosmetic_image_source(cosmetic, resize:, crop: true)
    return nil unless cosmetic&.image&.attached?
    return cosmetic.image unless cosmetic.image.variable?

    cosmetic.image.variant(crop ? { resize_to_fill: resize } : { resize_to_limit: resize })
  rescue ActiveStorage::Error, ActiveStorage::FileNotFoundError
    nil
  end

  # What a banner slot shows before anyone has uploaded its picture. Keyed off
  # rarity so the catalogue still reads as a ladder while the art is pending.
  def cosmetic_fallback_gradient(cosmetic)
    case cosmetic&.rarity
    when "rare"      then "from-sky-400 via-blue-500 to-indigo-500"
    when "epic"      then "from-purple-400 via-fuchsia-500 to-purple-600"
    when "legendary" then "from-amber-400 via-orange-500 to-amber-600"
    else "from-primary via-primary/90 to-secondary"
    end
  end

  # The rarity pill, built once. Shaped like `medal_chip` in SeasonsHelper so
  # the two badge styles on a profile match. Nil-safe: an empty slot renders
  # nothing rather than a blank pill.
  def cosmetic_rarity_chip(cosmetic)
    return nil if cosmetic.nil?

    tag.span(cosmetic.rarity_label,
             class: "inline-flex items-center px-2 py-0.5 rounded-full " \
                    "text-[11px] font-semibold #{cosmetic_rarity_classes(cosmetic.rarity)}")
  end

  # Ring colour for a frame with no artwork yet, and for the rarity outline the
  # locker draws around a card.
  def cosmetic_rarity_border(rarity)
    case rarity
    when "rare"      then "border-sky-400"
    when "epic"      then "border-purple-400"
    when "legendary" then "border-amber-400"
    else "border-gray-300"
    end
  end
end
