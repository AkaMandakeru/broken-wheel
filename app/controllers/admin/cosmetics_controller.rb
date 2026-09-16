# frozen_string_literal: true

module Admin
  # The catalogue behind profile banners and avatar frames. A cosmetic becomes a
  # season reward by key: add a `cosmetic` reward to a season whose reward_key
  # matches, and SeasonRewardGranter hands it out.
  class CosmeticsController < BaseController
    before_action :set_cosmetic, only: [ :edit, :update, :destroy ]

    def index
      @cosmetics = Cosmetic.ordered.with_artwork.group_by(&:kind)
    end

    def new
      @cosmetic = Cosmetic.new(kind: "banner", rarity: "common")
    end

    def edit
    end

    def create
      @cosmetic = Cosmetic.new(cosmetic_params)

      if @cosmetic.save
        redirect_to admin_cosmetics_path, notice: t("admin.flashes.cosmetics.created")
      else
        render :new, status: :unprocessable_entity
      end
    end

    def update
      if @cosmetic.update(cosmetic_params)
        redirect_to admin_cosmetics_path, notice: t("admin.flashes.cosmetics.updated")
      else
        render :edit, status: :unprocessable_entity
      end
    end

    # Destroying takes the item off every profile wearing it: user_cosmetics
    # cascade, but equipped_cosmetics is a jsonb blob no association reaches.
    def destroy
      key = @cosmetic.key
      kind = @cosmetic.kind
      @cosmetic.destroy
      unequip_everywhere(kind, key)
      redirect_to admin_cosmetics_path, notice: t("admin.flashes.cosmetics.destroyed")
    end

    private

    def set_cosmetic
      @cosmetic = Cosmetic.find(params[:id])
    end

    def unequip_everywhere(kind, key)
      User.wearing(kind, key).find_each { |user| user.unequip_cosmetic!(kind) }
    end

    def cosmetic_params
      params.require(:cosmetic).permit(:key, :kind, :name, :rarity, :position,
                                       :renderable, :animated, :css_class, :icon, :image)
    end
  end
end
