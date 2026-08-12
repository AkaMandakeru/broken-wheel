# frozen_string_literal: true

module Admin
  # Creates a season from a YAML blueprint: pasted, uploaded, or picked from the
  # blueprints shipped in db/seeds/seasons.
  class SeasonImportsController < BaseController
    def new
      @blueprints = Seasons::BlueprintImporter.available
      @content = params[:content]
    end

    # Validation runs whether or not the operator asked for it — an invalid
    # blueprint never reaches the database.
    def create
      @content = blueprint_content
      @blueprints = Seasons::BlueprintImporter.available

      if @content.blank?
        flash.now[:alert] = t("admin.season_imports.errors.empty")
        return render :new, status: :unprocessable_entity
      end

      @validation = Seasons::BlueprintImporter.validate_yaml(@content)

      if @validation.errors.any?
        flash.now[:alert] = t("admin.season_imports.errors.invalid", count: @validation.errors.size)
        return render :new, status: :unprocessable_entity
      end

      return render :new, status: :ok if params[:validate_only].present?

      import
    end

    # Serves the annotated template so an operator can start from it.
    def template
      path = Seasons::BlueprintImporter.template_path
      return redirect_to new_admin_season_import_path, alert: t("admin.season_imports.errors.no_template") unless path.exist?

      send_file path, filename: "season_template.yml", type: "text/yaml", disposition: "attachment"
    end

    private

    def import
      season = Seasons::BlueprintImporter.from_yaml(@content)
      redirect_to admin_season_path(season), notice: t("admin.season_imports.imported", name: season.name)
    rescue Seasons::BlueprintImporter::InvalidBlueprint => e
      @validation = Seasons::BlueprintImporter.validate_yaml(@content)
      flash.now[:alert] = t("admin.season_imports.errors.invalid", count: e.errors.size)
      render :new, status: :unprocessable_entity
    rescue ActiveRecord::RecordInvalid, ActiveRecord::StatementInvalid => e
      # The importer runs in a transaction, so nothing was written.
      flash.now[:alert] = t("admin.season_imports.errors.failed", message: e.message)
      render :new, status: :unprocessable_entity
    end

    # A pasted blueprint wins over a bundled one, so an edited paste is never
    # silently replaced by the file it came from.
    def blueprint_content
      return params[:content] if params[:content].present?

      if params[:file].respond_to?(:read)
        params[:file].read.force_encoding("UTF-8")
      elsif params[:blueprint_key].present?
        read_bundled(params[:blueprint_key])
      end
    end

    def read_bundled(key)
      # Guard against a crafted key reaching outside the blueprint directory.
      safe_key = File.basename(key.to_s, ".yml")
      path = Seasons::BlueprintImporter::BLUEPRINT_DIR.join("#{safe_key}.yml")
      path.exist? ? path.read : nil
    end
  end
end
