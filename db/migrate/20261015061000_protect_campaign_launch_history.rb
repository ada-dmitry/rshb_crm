class ProtectCampaignLaunchHistory < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      CREATE FUNCTION protect_campaign_launch() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN
        IF OLD.status = 'launched' THEN
          RAISE EXCEPTION 'Launched campaigns are immutable' USING ERRCODE = '23514';
        END IF;
        IF TG_OP = 'DELETE' THEN
          RETURN OLD;
        END IF;
        IF ROW(NEW.name, NEW.segment, NEW.offer, NEW.body, NEW.channel,
               NEW.scheduled_at, NEW.reference_date, NEW.window_days, NEW.user_id)
          IS DISTINCT FROM
           ROW(OLD.name, OLD.segment, OLD.offer, OLD.body, OLD.channel,
               OLD.scheduled_at, OLD.reference_date, OLD.window_days, OLD.user_id) THEN
          NEW.confirmed_at := NULL;
          NEW.confirmed_by_id := NULL;
        END IF;
        NEW.lock_version := OLD.lock_version + 1;
        RETURN NEW;
      END;
      $$;
      CREATE TRIGGER protect_campaign_launch BEFORE UPDATE OR DELETE ON campaigns
        FOR EACH ROW EXECUTE FUNCTION protect_campaign_launch();

      CREATE FUNCTION protect_campaign_snapshot() RETURNS trigger LANGUAGE plpgsql AS $$
      DECLARE
        campaign_ids bigint[];
      BEGIN
        IF TG_OP = 'INSERT' THEN
          campaign_ids := ARRAY[NEW.campaign_id];
        ELSIF TG_OP = 'DELETE' THEN
          campaign_ids := ARRAY[OLD.campaign_id];
        ELSE
          campaign_ids := ARRAY[OLD.campaign_id, NEW.campaign_id];
        END IF;
        -- Serialize snapshot writes with the campaign state transition too.
        PERFORM id FROM campaigns WHERE id = ANY(campaign_ids) ORDER BY id FOR UPDATE;
        IF EXISTS (SELECT 1 FROM campaigns WHERE id = ANY(campaign_ids) AND status = 'launched') THEN
          RAISE EXCEPTION 'Launched recipient snapshots are immutable' USING ERRCODE = '23514';
        END IF;
        IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
        RETURN NEW;
      END;
      $$;
      CREATE TRIGGER protect_campaign_snapshot BEFORE INSERT OR UPDATE OR DELETE ON campaign_recipients
        FOR EACH ROW EXECUTE FUNCTION protect_campaign_snapshot();
    SQL
  end

  def down
    execute <<~SQL
      DROP TRIGGER protect_campaign_snapshot ON campaign_recipients;
      DROP FUNCTION protect_campaign_snapshot();
      DROP TRIGGER protect_campaign_launch ON campaigns;
      DROP FUNCTION protect_campaign_launch();
    SQL
  end
end
