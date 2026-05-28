class CreateMissions < ActiveRecord::Migration[8.1]
  def change
    create_table :missions do |t|
      t.string :name
      t.text :description
      t.text :prompt
      t.string :schedule
      t.string :status
      t.integer :max_turns
      t.datetime :last_run_at
      t.datetime :next_run_at
      t.text :output

      t.timestamps
    end
  end
end
