class AddTitlesToUsers < ActiveRecord::Migration[8.1]
  def up
    add_column :users, :titles, :jsonb, default: [], null: false

    defaults = YAML.safe_load_file(Rails.root.join("config", "titles.yml"), aliases: true)
                   .to_h
                   .select { |_key, attrs| attrs["default"] }
                   .keys

    if defaults.any?
      execute("UPDATE users SET titles = #{connection.quote(defaults.to_json)}::jsonb")
    end
  end

  def down
    remove_column :users, :titles
  end
end
