class CreateUsageSnapshots < ActiveRecord::Migration[8.1]
  def change
    create_table :usage_snapshots do |t|
      t.integer :session_count
      t.integer :token_count
      t.text :active_models
      t.datetime :recorded_at

      t.timestamps
    end
  end
end
