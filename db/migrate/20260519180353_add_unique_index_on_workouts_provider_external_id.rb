class AddUniqueIndexOnWorkoutsProviderExternalId < ActiveRecord::Migration[8.1]
  def change
    add_index :workouts,
              [:user_id, :provider, :external_id],
              unique: true,
              where: "provider IS NOT NULL AND external_id IS NOT NULL",
              name: "index_workouts_on_user_provider_external_id"
  end
end
