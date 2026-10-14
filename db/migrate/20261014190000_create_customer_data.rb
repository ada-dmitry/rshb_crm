class CreateCustomerData < ActiveRecord::Migration[8.1]
  def change
    create_table :customers do |t|
      t.string :external_id, null: false
      t.string :name, null: false
      t.string :email
      t.string :phone
      t.timestamps
    end
    add_index :customers, :external_id, unique: true
    add_check_constraint :customers, "btrim(external_id) <> ''", name: "customers_external_id_present"
    add_check_constraint :customers, "btrim(name) <> ''", name: "customers_name_present"

    create_table :orders do |t|
      t.references :customer, null: false, foreign_key: true
      t.string :external_id, null: false
      t.bigint :total_cents, null: false
      t.string :status, null: false
      t.datetime :ordered_at, null: false
      t.timestamps
    end
    add_index :orders, :external_id, unique: true
    add_index :orders, [ :customer_id, :ordered_at ]
    add_check_constraint :orders, "btrim(external_id) <> ''", name: "orders_external_id_present"
    add_check_constraint :orders, "total_cents >= 0", name: "orders_amount_nonnegative"
    add_check_constraint :orders, "status IN ('completed', 'cancelled')", name: "orders_status_valid"

    create_table :consents do |t|
      t.references :customer, null: false, foreign_key: true
      t.string :channel, null: false
      t.boolean :granted, null: false, default: false
      t.datetime :changed_at, null: false
      t.timestamps
    end
    add_index :consents, [ :customer_id, :channel ], unique: true
    add_check_constraint :consents, "channel IN ('email', 'sms')", name: "consents_channel_valid"
  end
end
