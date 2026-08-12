# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::SeasonImports", type: :request do
  let(:admin) { build_user(admin: true) }

  let(:minimal) do
    <<~YAML
      key: spec_season
      name: Spec Season
      starts_at: 2026-10-01
      ends_at: 2026-10-31
      max_level: 8
      challenges:
        - key: spec_run_50
          title: Run 50 km
          category: monthly
          xp_reward: 500
          requirements:
            - { metric: distance_km, target: 50 }
      rewards:
        - { level: 1, track: free, reward_type: badge, reward_key: spec_badge, name: Spec Badge }
    YAML
  end

  before { sign_in admin }

  describe "GET /admin/season_imports/new" do
    it "renders with the bundled blueprints listed" do
      get new_admin_season_import_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("season_8_legacy_of_champions")
      expect(response.body).to include(ERB::Util.html_escape(I18n.t("admin.season_imports.paste.title")))
    end

    # The template is documentation, not an importable season.
    it "does not offer the template as a season to import" do
      get new_admin_season_import_path

      expect(response.body).not_to include(">TEMPLATE<")
    end

    # "Validate only" answers a POST with a 200 render. Turbo drops those unless
    # they redirect, so with Turbo enabled the button silently did nothing.
    it "opts the form out of Turbo so a 200 re-render reaches the browser" do
      get new_admin_season_import_path

      expect(response.body).to match(/<form[^>]*data-turbo="false"/)
    end
  end

  describe "GET /admin/season_imports/template" do
    it "downloads the annotated template" do
      get template_admin_season_imports_path

      expect(response).to have_http_status(:ok)
      expect(response.headers["Content-Disposition"]).to include("season_template.yml")
    end
  end

  describe "POST /admin/season_imports" do
    it "imports pasted YAML and redirects to the season" do
      expect { post admin_season_imports_path, params: { content: minimal } }
        .to change(Season, :count).by(1)

      season = Season.find_by(key: "spec_season")
      expect(response).to redirect_to(admin_season_path(season))
      expect(season.season_challenges.count).to eq(1)
      expect(season.max_level).to eq(8)
      expect(season.level_curve.size).to eq(8)
    end

    it "imports an uploaded file" do
      file = Rack::Test::UploadedFile.new(StringIO.new(minimal), "text/yaml", original_filename: "season.yml")

      expect { post admin_season_imports_path, params: { file: file } }.to change(Season, :count).by(1)
    end

    it "imports a bundled blueprint by key" do
      expect { post admin_season_imports_path, params: { blueprint_key: "season_8_legacy_of_champions" } }
        .to change(Season, :count).by(1)
    end

    # An edited paste must not be silently replaced by the file it came from.
    it "prefers pasted content over a selected blueprint" do
      post admin_season_imports_path, params: { content: minimal, blueprint_key: "season_8_legacy_of_champions" }

      expect(Season.find_by(key: "spec_season")).to be_present
      expect(Season.find_by(key: "season_8_legacy_of_champions")).to be_nil
    end

    it "asks for something to import when nothing was given" do
      post admin_season_imports_path, params: {}

      expect(response).to have_http_status(:unprocessable_entity)
      expect(flash.now[:alert]).to be_present
    end

    describe "validation" do
      it "reports problems and imports nothing" do
        bad = minimal.sub("metric: distance_km", "metric: distnce_km")

        expect { post admin_season_imports_path, params: { content: bad } }.not_to change(Season, :count)
        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include("is not a known metric")
      end

      it "reports a YAML syntax error rather than raising" do
        post admin_season_imports_path, params: { content: "key: [unclosed\nname: broken" }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include("YAML syntax error")
      end

      # An import writes across nine tables; a half-built season would be worse
      # than a rejected one.
      it "writes nothing at all when one entry deep in the file is wrong" do
        bad = minimal + <<~YAML
          daily_templates:
            - { key: ok_one, metric: distance_km, target: 3 }
            - { key: broken, metric: not_a_metric, target: 3 }
        YAML

        seasons = Season.count
        templates = DailyChallengeTemplate.count

        post admin_season_imports_path, params: { content: bad }

        expect(Season.count).to eq(seasons)
        expect(DailyChallengeTemplate.count).to eq(templates)
      end

      it "validates without importing when asked" do
        expect { post admin_season_imports_path, params: { content: minimal, validate_only: "1" } }
          .not_to change(Season, :count)

        expect(response).to have_http_status(:ok)
        expect(response.body).to include(ERB::Util.html_escape(I18n.t("admin.season_imports.valid")))
      end
    end

    it "is idempotent — importing the same blueprint twice updates in place" do
      post admin_season_imports_path, params: { content: minimal }
      expect { post admin_season_imports_path, params: { content: minimal } }.not_to change(Season, :count)

      expect(Season.where(key: "spec_season").count).to eq(1)
    end

    it "keeps player progress across a re-import" do
      post admin_season_imports_path, params: { content: minimal }
      season = Season.find_by(key: "spec_season")
      participation = SeasonProgressService.ensure_participation(build_user, season)
      participation.update!(xp: 900, level: 4)

      post admin_season_imports_path, params: { content: minimal }

      expect(participation.reload.xp).to eq(900)
    end

    # A crafted key must not read files outside the blueprint directory.
    it "ignores a traversing blueprint key" do
      expect { post admin_season_imports_path, params: { blueprint_key: "../../../config/database" } }
        .not_to change(Season, :count)

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "GET /admin/seasons/:id/export" do
    let!(:season) { Seasons::BlueprintImporter.call("season_8_legacy_of_champions") }

    it "downloads the season as a blueprint" do
      get export_admin_season_path(season)

      expect(response).to have_http_status(:ok)
      expect(response.headers["Content-Disposition"]).to include(".yml")
      expect(YAML.safe_load(response.body, permitted_classes: [ Date, Time ])["name"]).to eq(season.name)
    end

    it "applies a new key, name and date shift" do
      get export_admin_season_path(season), params: {
        new_key: "october", new_name: "October", shift_to: "2026-10-01"
      }

      data = YAML.safe_load(response.body, permitted_classes: [ Date, Time ])
      expect(data["key"]).to eq("october")
      expect(data["name"]).to eq("October")
      expect(data["starts_at"]).to eq("2026-10-01")
    end
  end

  describe "authorisation" do
    it "keeps non-admins out" do
      sign_out admin
      sign_in build_user(admin: false)

      get new_admin_season_import_path
      expect(response).not_to have_http_status(:ok)
    end
  end
end
