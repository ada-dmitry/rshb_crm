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

ActiveRecord::Schema[8.1].define(version: 2026_10_14_190000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "consents", force: :cascade do |t|
    t.bigint "customer_id", null: false
    t.string "channel", null: false
    t.boolean "granted", default: false, null: false
    t.datetime "changed_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index [ "customer_id", "channel" ], name: "index_consents_on_customer_id_and_channel", unique: true
    t.index [ "customer_id" ], name: "index_consents_on_customer_id"
    t.check_constraint "channel::text = ANY (ARRAY['email'::character varying, 'sms'::character varying]::text[])", name: "consents_channel_valid"
  end

  create_table "customers", force: :cascade do |t|
    t.string "external_id", null: false
    t.string "name", null: false
    t.string "email"
    t.string "phone"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index [ "external_id" ], name: "index_customers_on_external_id", unique: true
    t.check_constraint "btrim(external_id::text) <> ''::text", name: "customers_external_id_present"
    t.check_constraint "btrim(name::text) <> ''::text", name: "customers_name_present"
  end

  create_table "orders", force: :cascade do |t|
    t.bigint "customer_id", null: false
    t.string "external_id", null: false
    t.bigint "total_cents", null: false
    t.string "status", null: false
    t.datetime "ordered_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index [ "customer_id", "ordered_at" ], name: "index_orders_on_customer_id_and_ordered_at"
    t.index [ "customer_id" ], name: "index_orders_on_customer_id"
    t.index [ "external_id" ], name: "index_orders_on_external_id", unique: true
    t.check_constraint "btrim(external_id::text) <> ''::text", name: "orders_external_id_present"
    t.check_constraint "status::text = ANY (ARRAY['completed'::character varying, 'cancelled'::character varying]::text[])", name: "orders_status_valid"
    t.check_constraint "total_cents >= 0", name: "orders_amount_nonnegative"
  end

  create_table "sessions", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "ip_address"
    t.string "user_agent"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index [ "user_id" ], name: "index_sessions_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "email_address", null: false
    t.string "password_digest", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index [ "email_address" ], name: "index_users_on_email_address", unique: true
  end

  add_foreign_key "consents", "customers"
  add_foreign_key "orders", "customers"
  add_foreign_key "sessions", "users"
end
