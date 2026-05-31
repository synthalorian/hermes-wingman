class CreateCachedMemories < ActiveRecord::Migration[8.1]
  def change
    create_table :cached_memories do |t|
      t.string :entry_key
      t.text :content
      t.string :memory_type
      t.text :tags

      t.timestamps
    end
  end
end
