# frozen_string_literal: true

# How a cosmetic is drawn when it is colour rather than a picture: name colours,
# borders, and the gradient a banner or frame shows before its art is uploaded.
#
# The web draws these with Tailwind classes (a cosmetic's `css_class`, or the
# rarity fallbacks below). A native app has no Tailwind, so the API sends
# `{ type: "solid" | "gradient", colors: ["#rrggbb", ...] }` instead — and both
# are read from here, so the page and the app cannot drift apart.
#
# PALETTE is the source of truth for the API's colours. Its values are the hex
# equivalents of Tailwind 4.3's default palette (theme.css defines them in
# oklch) and of the brand tokens in app/assets/tailwind/application.css. A new
# colour used in a season blueprint's `css_class` must be added here; the spec
# checks every seeded blueprint resolves.
#
# The class strings stay spelled out in full in this file on purpose: Tailwind
# only generates the classes it can find in the source.
module CosmeticStyle
  PALETTE = {
    "amber-300" => "#ffd230", "amber-400" => "#ffb900", "amber-500" => "#fe9a00", "amber-600" => "#e17100",
    "blue-500" => "#2b7fff", "blue-800" => "#193cb8", "blue-900" => "#1c398e",
    "cyan-400" => "#00d3f2", "cyan-800" => "#005f78",
    "emerald-700" => "#007a55",
    "fuchsia-500" => "#e12afb",
    "gray-300" => "#d1d5dc",
    "green-600" => "#00a63e", "green-800" => "#016630", "green-900" => "#0d542b",
    "indigo-500" => "#615fff", "indigo-900" => "#312c85",
    "orange-500" => "#ff6900",
    "purple-400" => "#c27aff", "purple-600" => "#9810fa",
    "sky-400" => "#00bcff", "sky-800" => "#00598a", "sky-900" => "#024a70",
    "slate-300" => "#cad5e2", "slate-700" => "#314158", "slate-800" => "#1d293d", "slate-900" => "#0f172b",
    "yellow-400" => "#fdc700", "yellow-500" => "#f0b100",
    # Brand tokens (application.css @theme, oklch(0.55 0.2 250) and oklch(0.65 0.18 145)).
    "primary" => "#0071df", "secondary" => "#31aa40"
  }.freeze

  # Keyed off rarity so the catalogue still reads as a ladder while art is pending.
  RARITY_FALLBACKS = {
    "common" => { gradient: "from-primary via-primary/90 to-secondary", border: "border-gray-300" },
    "rare" => { gradient: "from-sky-400 via-blue-500 to-indigo-500", border: "border-sky-400" },
    "epic" => { gradient: "from-purple-400 via-fuchsia-500 to-purple-600", border: "border-purple-400" },
    "legendary" => { gradient: "from-amber-400 via-orange-500 to-amber-600", border: "border-amber-400" }
  }.freeze

  GRADIENT_STOP = /\A(?:from|via|to)-(.+)\z/
  # `ring-offset-*` is the gap around a ring, not the ring, and `ring-4` /
  # `border-2` are widths — neither is the cosmetic's colour.
  SOLID_COLOR = /\A(?:text|ring|border|bg)-(?!offset-)(.+)\z/

  module_function

  # Tailwind classes for the gradient a slot shows without art.
  def fallback_gradient(rarity)
    rarity_fallback(rarity)[:gradient]
  end

  # Tailwind class for the ring of a frame without art, and the locker outline.
  def rarity_border(rarity)
    rarity_fallback(rarity)[:border]
  end

  # What the app needs to draw a cosmetic: its own `css_class` translated to
  # colours, or the rarity fallback when it has none (or none we know).
  #
  #   CosmeticStyle.render_data(cosmetic) # => { type: "gradient", colors: ["#00bcff", "#2b7fff", "#615fff"] }
  def render_data(cosmetic)
    from_classes(cosmetic.css_class) || fallback_render_data(cosmetic)
  end

  # nil when the classes name no colour in PALETTE.
  def from_classes(classes)
    tokens = classes.to_s.split
    stops = tokens.filter_map { |token| color(token[GRADIENT_STOP, 1]) }
    return { type: "gradient", colors: stops } if stops.size > 1

    solid = stops.first || tokens.filter_map { |token| color(token[SOLID_COLOR, 1]) }.first
    solid && { type: "solid", colors: [ solid ] }
  end

  # Hex for a palette name, ignoring an opacity suffix ("primary/90").
  def color(name)
    name && PALETTE[name.split("/").first]
  end

  def fallback_render_data(cosmetic)
    if cosmetic.kind.in?(%w[banner frame])
      from_classes(fallback_gradient(cosmetic.rarity))
    else
      from_classes(rarity_border(cosmetic.rarity))
    end
  end

  def rarity_fallback(rarity)
    RARITY_FALLBACKS.fetch(rarity.to_s, RARITY_FALLBACKS["common"])
  end
end
