class CreateProfiles < ActiveRecord::Migration[8.1]
  def change
    create_table :profiles do |t|
      t.string :identifier
      t.string :name
      t.text :description
      t.string :default_model
      t.string :default_provider
      t.text :config_overrides
      t.text :skills
      t.string :theme

      t.timestamps
    end
  end
end
