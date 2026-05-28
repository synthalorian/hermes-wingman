# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_05_25_033002) do
  create_table "cached_memories", force: :cascade do |t|
    t.text "content"
    t.datetime "created_at", null: false
    t.string "entry_key"
    t.string "memory_type"
    t.text "tags"
    t.datetime "updated_at", null: false
  end

  create_table "cached_skills", force: :cascade do |t|
    t.string "category"
    t.datetime "created_at", null: false
    t.text "description"
    t.boolean "enabled"
    t.string "name"
    t.string "path"
    t.datetime "updated_at", null: false
    t.string "version"
  end

  create_table "missions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.datetime "last_run_at"
    t.integer "max_turns"
    t.string "name"
    t.datetime "next_run_at"
    t.text "output"
    t.text "prompt"
    t.string "schedule"
    t.string "status"
    t.datetime "updated_at", null: false
  end

  create_table "orchestration_runs", force: :cascade do |t|
    t.integer "agent_count"
    t.text "agents"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.text "description"
    t.string "name"
    t.text "results"
    t.datetime "started_at"
    t.string "status"
    t.text "tasks"
    t.datetime "updated_at", null: false
  end

  create_table "profiles", force: :cascade do |t|
    t.text "config_overrides"
    t.datetime "created_at", null: false
    t.string "default_model"
    t.string "default_provider"
    t.text "description"
    t.string "identifier"
    t.string "name"
    t.text "skills"
    t.string "theme"
    t.datetime "updated_at", null: false
  end

  create_table "usage_snapshots", force: :cascade do |t|
    t.text "active_models"
    t.datetime "created_at", null: false
    t.datetime "recorded_at"
    t.integer "session_count"
    t.integer "token_count"
    t.datetime "updated_at", null: false
  end

  create_table "webhooks", force: :cascade do |t|
    t.boolean "active"
    t.datetime "created_at", null: false
    t.text "events"
    t.datetime "last_triggered_at"
    t.string "name"
    t.string "secret"
    t.datetime "updated_at", null: false
    t.string "url"
  end
end
