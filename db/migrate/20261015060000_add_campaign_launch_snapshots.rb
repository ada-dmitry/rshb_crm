class AddCampaignLaunchSnapshots < ActiveRecord::Migration[8.1]
  def change
    add_column :campaigns, :lock_version, :integer, null: false, default: 0
    add_column :campaigns, :confirmed_at, :datetime
    add_reference :campaigns, :confirmed_by, foreign_key: { to_table: :users }
    add_column :campaigns, :launched_at, :datetime
    add_check_constraint :campaigns, "(confirmed_at IS NULL) = (confirmed_by_id IS NULL)", name: "campaigns_confirmation_consistent"

    add_column :campaign_recipients, :contact, :string
    add_column :campaign_recipients, :customer_name, :string
    add_column :campaign_recipients, :customer_external_id, :string
    add_column :campaign_recipients, :reasons, :jsonb, null: false, default: []
    remove_check_constraint :campaign_recipients, name: "campaign_recipients_status_valid", expression: "status IN ('pending', 'simulated', 'failed')"
    add_check_constraint :campaign_recipients, "status IN ('pending', 'simulated', 'failed', 'excluded')", name: "campaign_recipients_status_valid"
  end
end
