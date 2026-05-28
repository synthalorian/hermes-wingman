class CreateOrchestrationRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :orchestration_runs do |t|
      t.string :name
      t.text :description
      t.string :status
      t.integer :agent_count
      t.text :agents
      t.text :tasks
      t.text :results
      t.datetime :started_at
      t.datetime :completed_at

      t.timestamps
    end
  end
end
