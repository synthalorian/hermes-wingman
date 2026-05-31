class CreateCachedSkills < ActiveRecord::Migration[8.1]
  def change
    create_table :cached_skills do |t|
      t.string :name
      t.text :description
      t.string :category
      t.boolean :enabled
      t.string :version
      t.string :path

      t.timestamps
    end
  end
end
