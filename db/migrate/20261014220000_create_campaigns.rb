class CreateCampaigns < ActiveRecord::Migration[8.1]
  def change
    create_table :campaigns do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false
      t.string :segment, null: false
      t.string :offer, null: false
      t.text :body, null: false
      t.string :channel, null: false
      t.datetime :scheduled_at, null: false
      t.date :reference_date, null: false
      t.integer :window_days, null: false
      t.string :status, null: false, default: "draft"
      t.timestamps
    end
    add_check_constraint :campaigns, "btrim(name) <> '' AND char_length(name) <= 120", name: "campaigns_name_valid"
    add_check_constraint :campaigns, "btrim(body) <> '' AND char_length(body) <= 2000", name: "campaigns_body_valid"
    add_check_constraint :campaigns, "segment IN ('no_purchases', 'champions', 'loyal', 'at_risk', 'sleeping', 'new_customers', 'active')", name: "campaigns_segment_valid"
    add_check_constraint :campaigns, "offer IN ('repeat_purchase', 'seasonal_preorder', 'cross_sell', 'catalog_introduction')", name: "campaigns_offer_valid"
    add_check_constraint :campaigns, "channel IN ('email', 'sms')", name: "campaigns_channel_valid"
    add_check_constraint :campaigns, "status IN ('draft', 'launched')", name: "campaigns_status_valid"
    add_check_constraint :campaigns, "window_days BETWEEN 1 AND 3650", name: "campaigns_window_valid"

    create_table :campaign_recipients do |t|
      t.references :campaign, null: false, foreign_key: true
      t.references :customer, null: false, foreign_key: true
      t.string :channel, null: false
      t.string :status, null: false, default: "pending"
      t.datetime :contacted_at
      t.timestamps
    end
    add_index :campaign_recipients, [ :campaign_id, :customer_id ], unique: true
    add_index :campaign_recipients, [ :customer_id, :contacted_at ]
    add_check_constraint :campaign_recipients, "channel IN ('email', 'sms')", name: "campaign_recipients_channel_valid"
    add_check_constraint :campaign_recipients, "status IN ('pending', 'simulated', 'failed')", name: "campaign_recipients_status_valid"
    add_check_constraint :campaign_recipients, "(status = 'simulated') = (contacted_at IS NOT NULL)", name: "campaign_recipients_contact_consistent"
  end
end
