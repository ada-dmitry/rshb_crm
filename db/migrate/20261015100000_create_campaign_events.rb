class CreateCampaignEvents < ActiveRecord::Migration[8.1]
  def up
    create_table :campaign_events do |t|
      t.references :campaign_recipient, null: false, foreign_key: true
      t.string :event_type, null: false
      t.string :source, null: false, default: "simulated"
      t.integer :simulation_version, null: false, default: 1
      t.datetime :occurred_at, null: false
      t.timestamps
    end
    add_index :campaign_events, [ :campaign_recipient_id, :event_type ], unique: true
    add_check_constraint :campaign_events, "event_type IN ('delivered', 'clicked')", name: "campaign_events_type_valid"
    add_check_constraint :campaign_events, "source = 'simulated' AND simulation_version = 1", name: "campaign_events_simulated_only"

    execute <<~SQL
      CREATE FUNCTION protect_campaign_event() RETURNS trigger LANGUAGE plpgsql AS $$
      DECLARE
        campaign_status text;
        recipient_status text;
        contact_time timestamp;
      BEGIN
        IF TG_OP <> 'INSERT' THEN
          RAISE EXCEPTION 'Simulated events are immutable' USING ERRCODE = '23514';
        END IF;
        SELECT c.status, r.status, r.contacted_at
          INTO campaign_status, recipient_status, contact_time
          FROM campaigns c JOIN campaign_recipients r ON r.campaign_id = c.id
          WHERE r.id = NEW.campaign_recipient_id FOR UPDATE OF c;
        IF campaign_status IS DISTINCT FROM 'launched' OR recipient_status IS DISTINCT FROM 'simulated'
          OR contact_time IS NULL OR NEW.occurred_at < contact_time THEN
          RAISE EXCEPTION 'Events require a launched simulated contact and valid chronology' USING ERRCODE = '23514';
        END IF;
        IF NEW.event_type = 'clicked' AND NOT EXISTS (
          SELECT 1 FROM campaign_events WHERE campaign_recipient_id = NEW.campaign_recipient_id
            AND event_type = 'delivered' AND occurred_at <= NEW.occurred_at
        ) THEN
          RAISE EXCEPTION 'Click requires an earlier modeled delivery' USING ERRCODE = '23514';
        END IF;
        RETURN NEW;
      END;
      $$;
      CREATE TRIGGER protect_campaign_event BEFORE INSERT OR UPDATE OR DELETE ON campaign_events
        FOR EACH ROW EXECUTE FUNCTION protect_campaign_event();
    SQL
  end

  def down
    drop_table :campaign_events
    execute "DROP FUNCTION protect_campaign_event()"
  end
end
