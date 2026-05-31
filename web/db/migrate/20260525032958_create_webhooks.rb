class CreateWebhooks < ActiveRecord::Migration[8.1]
  def change
    create_table :webhooks do |t|
      t.string :name
      t.string :url
      t.text :events
      t.string :secret
      t.boolean :active
      t.datetime :last_triggered_at

      t.timestamps
    end
  end
end
