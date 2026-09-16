# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin cosmetics", type: :request do
  let(:admin) { build_user(admin: true) }

  def png_upload
    Rack::Test::UploadedFile.new(
      StringIO.new(Base64.decode64(
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
      )),
      "image/png",
      true,
      original_filename: "banner.png"
    )
  end

  before { sign_in admin }

  it "creates a banner with an uploaded picture" do
    expect {
      post admin_cosmetics_path, params: {
        cosmetic: { key: "legacy_of_champions", kind: "banner", name: "Legacy of Champions",
                    rarity: "legendary", position: 1, renderable: "1", image: png_upload }
      }
    }.to change(Cosmetic, :count).by(1)

    cosmetic = Cosmetic.find_by(key: "legacy_of_champions")
    expect(cosmetic.image).to be_attached
    expect(cosmetic.artwork?).to be(true)
    expect(response).to redirect_to(admin_cosmetics_path)
  end

  it "accepts a cosmetic with no picture yet, the way a blueprint import does" do
    post admin_cosmetics_path, params: {
      cosmetic: { key: "pending_art", kind: "frame", name: "Pending", rarity: "rare" }
    }

    cosmetic = Cosmetic.find_by(key: "pending_art")
    expect(cosmetic).to be_present
    expect(cosmetic.artwork?).to be(false)
  end

  it "rejects a duplicate key" do
    Cosmetic.create!(key: "taken", kind: "banner", name: "Taken")

    expect {
      post admin_cosmetics_path, params: { cosmetic: { key: "taken", kind: "banner", name: "Again" } }
    }.not_to change(Cosmetic, :count)

    expect(response).to have_http_status(:unprocessable_entity)
  end

  it "lists banners and frames" do
    Cosmetic.create!(key: "a_banner", kind: "banner", name: "A Banner")
    Cosmetic.create!(key: "a_frame", kind: "frame", name: "A Frame")

    get admin_cosmetics_path

    expect(response.body).to include("A Banner", "A Frame")
  end

  # Ownership cascades through user_cosmetics, but equipped_cosmetics is a jsonb
  # blob no association reaches — deleting has to clear it by hand or profiles
  # keep pointing at a row that is gone.
  it "takes a deleted cosmetic off the profiles wearing it" do
    cosmetic = Cosmetic.create!(key: "doomed", kind: "banner", name: "Doomed")
    wearer = build_user
    wearer.user_cosmetics.create!(cosmetic: cosmetic, unlocked_at: Time.current)
    wearer.equip_cosmetic!("banner", "doomed")
    bystander = build_user
    other = Cosmetic.create!(key: "safe", kind: "banner", name: "Safe")
    bystander.user_cosmetics.create!(cosmetic: other, unlocked_at: Time.current)
    bystander.equip_cosmetic!("banner", "safe")

    delete admin_cosmetic_path(cosmetic)

    expect(wearer.reload.equipped).to be_empty
    expect(bystander.reload.equipped["banner"]).to eq("safe")
    expect(Cosmetic.exists?(cosmetic.id)).to be(false)
  end

  it "renders the new and edit forms" do
    cosmetic = Cosmetic.create!(key: "editable", kind: "frame", name: "Editable")

    get new_admin_cosmetic_path
    expect(response).to have_http_status(:ok)

    get edit_admin_cosmetic_path(cosmetic)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Editable")
  end

  it "keeps a non-admin out" do
    sign_out admin
    sign_in build_user

    get admin_cosmetics_path

    expect(response).to redirect_to(root_path)
  end
end
