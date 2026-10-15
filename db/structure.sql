SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: protect_campaign_event(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.protect_campaign_event() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
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


--
-- Name: protect_campaign_launch(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.protect_campaign_launch() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
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


--
-- Name: protect_campaign_snapshot(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.protect_campaign_snapshot() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
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


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: ar_internal_metadata; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ar_internal_metadata (
    key character varying NOT NULL,
    value character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: campaign_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.campaign_events (
    id bigint NOT NULL,
    campaign_recipient_id bigint NOT NULL,
    event_type character varying NOT NULL,
    source character varying DEFAULT 'simulated'::character varying NOT NULL,
    simulation_version integer DEFAULT 1 NOT NULL,
    occurred_at timestamp(6) without time zone NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT campaign_events_simulated_only CHECK ((((source)::text = 'simulated'::text) AND (simulation_version = 1))),
    CONSTRAINT campaign_events_type_valid CHECK (((event_type)::text = ANY ((ARRAY['delivered'::character varying, 'clicked'::character varying])::text[])))
);


--
-- Name: campaign_events_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.campaign_events_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: campaign_events_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.campaign_events_id_seq OWNED BY public.campaign_events.id;


--
-- Name: campaign_recipients; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.campaign_recipients (
    id bigint NOT NULL,
    campaign_id bigint NOT NULL,
    customer_id bigint NOT NULL,
    channel character varying NOT NULL,
    status character varying DEFAULT 'pending'::character varying NOT NULL,
    contacted_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    contact character varying,
    customer_name character varying,
    customer_external_id character varying,
    reasons jsonb DEFAULT '[]'::jsonb NOT NULL,
    CONSTRAINT campaign_recipients_channel_valid CHECK (((channel)::text = ANY ((ARRAY['email'::character varying, 'sms'::character varying])::text[]))),
    CONSTRAINT campaign_recipients_contact_consistent CHECK ((((status)::text = 'simulated'::text) = (contacted_at IS NOT NULL))),
    CONSTRAINT campaign_recipients_status_valid CHECK (((status)::text = ANY ((ARRAY['pending'::character varying, 'simulated'::character varying, 'failed'::character varying, 'excluded'::character varying])::text[])))
);


--
-- Name: campaign_recipients_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.campaign_recipients_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: campaign_recipients_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.campaign_recipients_id_seq OWNED BY public.campaign_recipients.id;


--
-- Name: campaigns; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.campaigns (
    id bigint NOT NULL,
    user_id bigint NOT NULL,
    name character varying NOT NULL,
    segment character varying NOT NULL,
    offer character varying NOT NULL,
    body text NOT NULL,
    channel character varying NOT NULL,
    scheduled_at timestamp(6) without time zone NOT NULL,
    reference_date date NOT NULL,
    window_days integer NOT NULL,
    status character varying DEFAULT 'draft'::character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    lock_version integer DEFAULT 0 NOT NULL,
    confirmed_at timestamp(6) without time zone,
    confirmed_by_id bigint,
    launched_at timestamp(6) without time zone,
    CONSTRAINT campaigns_body_valid CHECK (((btrim(body) <> ''::text) AND (char_length(body) <= 2000))),
    CONSTRAINT campaigns_channel_valid CHECK (((channel)::text = ANY ((ARRAY['email'::character varying, 'sms'::character varying])::text[]))),
    CONSTRAINT campaigns_confirmation_consistent CHECK (((confirmed_at IS NULL) = (confirmed_by_id IS NULL))),
    CONSTRAINT campaigns_name_valid CHECK (((btrim((name)::text) <> ''::text) AND (char_length((name)::text) <= 120))),
    CONSTRAINT campaigns_offer_valid CHECK (((offer)::text = ANY ((ARRAY['repeat_purchase'::character varying, 'seasonal_preorder'::character varying, 'cross_sell'::character varying, 'catalog_introduction'::character varying])::text[]))),
    CONSTRAINT campaigns_segment_valid CHECK (((segment)::text = ANY ((ARRAY['no_purchases'::character varying, 'champions'::character varying, 'loyal'::character varying, 'at_risk'::character varying, 'sleeping'::character varying, 'new_customers'::character varying, 'active'::character varying])::text[]))),
    CONSTRAINT campaigns_status_valid CHECK (((status)::text = ANY ((ARRAY['draft'::character varying, 'launched'::character varying])::text[]))),
    CONSTRAINT campaigns_window_valid CHECK (((window_days >= 1) AND (window_days <= 3650)))
);


--
-- Name: campaigns_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.campaigns_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: campaigns_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.campaigns_id_seq OWNED BY public.campaigns.id;


--
-- Name: consents; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.consents (
    id bigint NOT NULL,
    customer_id bigint NOT NULL,
    channel character varying NOT NULL,
    granted boolean DEFAULT false NOT NULL,
    changed_at timestamp(6) without time zone NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT consents_channel_valid CHECK (((channel)::text = ANY ((ARRAY['email'::character varying, 'sms'::character varying])::text[])))
);


--
-- Name: consents_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.consents_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: consents_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.consents_id_seq OWNED BY public.consents.id;


--
-- Name: customers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.customers (
    id bigint NOT NULL,
    external_id character varying NOT NULL,
    name character varying NOT NULL,
    email character varying,
    phone character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT customers_external_id_present CHECK ((btrim((external_id)::text) <> ''::text)),
    CONSTRAINT customers_name_present CHECK ((btrim((name)::text) <> ''::text))
);


--
-- Name: customers_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.customers_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: customers_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.customers_id_seq OWNED BY public.customers.id;


--
-- Name: orders; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.orders (
    id bigint NOT NULL,
    customer_id bigint NOT NULL,
    external_id character varying NOT NULL,
    total_cents bigint NOT NULL,
    status character varying NOT NULL,
    ordered_at timestamp(6) without time zone NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT orders_amount_nonnegative CHECK ((total_cents >= 0)),
    CONSTRAINT orders_external_id_present CHECK ((btrim((external_id)::text) <> ''::text)),
    CONSTRAINT orders_status_valid CHECK (((status)::text = ANY ((ARRAY['completed'::character varying, 'cancelled'::character varying])::text[])))
);


--
-- Name: orders_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.orders_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: orders_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.orders_id_seq OWNED BY public.orders.id;


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schema_migrations (
    version character varying NOT NULL
);


--
-- Name: sessions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sessions (
    id bigint NOT NULL,
    user_id bigint NOT NULL,
    ip_address character varying,
    user_agent character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: sessions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.sessions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: sessions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.sessions_id_seq OWNED BY public.sessions.id;


--
-- Name: users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.users (
    id bigint NOT NULL,
    email_address character varying NOT NULL,
    password_digest character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: users_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.users_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: users_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.users_id_seq OWNED BY public.users.id;


--
-- Name: campaign_events id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.campaign_events ALTER COLUMN id SET DEFAULT nextval('public.campaign_events_id_seq'::regclass);


--
-- Name: campaign_recipients id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.campaign_recipients ALTER COLUMN id SET DEFAULT nextval('public.campaign_recipients_id_seq'::regclass);


--
-- Name: campaigns id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.campaigns ALTER COLUMN id SET DEFAULT nextval('public.campaigns_id_seq'::regclass);


--
-- Name: consents id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.consents ALTER COLUMN id SET DEFAULT nextval('public.consents_id_seq'::regclass);


--
-- Name: customers id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customers ALTER COLUMN id SET DEFAULT nextval('public.customers_id_seq'::regclass);


--
-- Name: orders id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.orders ALTER COLUMN id SET DEFAULT nextval('public.orders_id_seq'::regclass);


--
-- Name: sessions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sessions ALTER COLUMN id SET DEFAULT nextval('public.sessions_id_seq'::regclass);


--
-- Name: users id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users ALTER COLUMN id SET DEFAULT nextval('public.users_id_seq'::regclass);


--
-- Name: ar_internal_metadata ar_internal_metadata_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ar_internal_metadata
    ADD CONSTRAINT ar_internal_metadata_pkey PRIMARY KEY (key);


--
-- Name: campaign_events campaign_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.campaign_events
    ADD CONSTRAINT campaign_events_pkey PRIMARY KEY (id);


--
-- Name: campaign_recipients campaign_recipients_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.campaign_recipients
    ADD CONSTRAINT campaign_recipients_pkey PRIMARY KEY (id);


--
-- Name: campaigns campaigns_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.campaigns
    ADD CONSTRAINT campaigns_pkey PRIMARY KEY (id);


--
-- Name: consents consents_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.consents
    ADD CONSTRAINT consents_pkey PRIMARY KEY (id);


--
-- Name: customers customers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customers
    ADD CONSTRAINT customers_pkey PRIMARY KEY (id);


--
-- Name: orders orders_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.orders
    ADD CONSTRAINT orders_pkey PRIMARY KEY (id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: sessions sessions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sessions
    ADD CONSTRAINT sessions_pkey PRIMARY KEY (id);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: index_campaign_events_on_campaign_recipient_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_campaign_events_on_campaign_recipient_id ON public.campaign_events USING btree (campaign_recipient_id);


--
-- Name: index_campaign_events_on_campaign_recipient_id_and_event_type; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_campaign_events_on_campaign_recipient_id_and_event_type ON public.campaign_events USING btree (campaign_recipient_id, event_type);


--
-- Name: index_campaign_recipients_on_campaign_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_campaign_recipients_on_campaign_id ON public.campaign_recipients USING btree (campaign_id);


--
-- Name: index_campaign_recipients_on_campaign_id_and_customer_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_campaign_recipients_on_campaign_id_and_customer_id ON public.campaign_recipients USING btree (campaign_id, customer_id);


--
-- Name: index_campaign_recipients_on_customer_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_campaign_recipients_on_customer_id ON public.campaign_recipients USING btree (customer_id);


--
-- Name: index_campaign_recipients_on_customer_id_and_contacted_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_campaign_recipients_on_customer_id_and_contacted_at ON public.campaign_recipients USING btree (customer_id, contacted_at);


--
-- Name: index_campaigns_on_confirmed_by_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_campaigns_on_confirmed_by_id ON public.campaigns USING btree (confirmed_by_id);


--
-- Name: index_campaigns_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_campaigns_on_user_id ON public.campaigns USING btree (user_id);


--
-- Name: index_consents_on_customer_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_consents_on_customer_id ON public.consents USING btree (customer_id);


--
-- Name: index_consents_on_customer_id_and_channel; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_consents_on_customer_id_and_channel ON public.consents USING btree (customer_id, channel);


--
-- Name: index_customers_on_external_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_customers_on_external_id ON public.customers USING btree (external_id);


--
-- Name: index_orders_on_customer_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_orders_on_customer_id ON public.orders USING btree (customer_id);


--
-- Name: index_orders_on_customer_id_and_ordered_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_orders_on_customer_id_and_ordered_at ON public.orders USING btree (customer_id, ordered_at);


--
-- Name: index_orders_on_external_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_orders_on_external_id ON public.orders USING btree (external_id);


--
-- Name: index_sessions_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_sessions_on_user_id ON public.sessions USING btree (user_id);


--
-- Name: index_users_on_email_address; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_users_on_email_address ON public.users USING btree (email_address);


--
-- Name: campaign_events protect_campaign_event; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER protect_campaign_event BEFORE INSERT OR DELETE OR UPDATE ON public.campaign_events FOR EACH ROW EXECUTE FUNCTION public.protect_campaign_event();


--
-- Name: campaigns protect_campaign_launch; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER protect_campaign_launch BEFORE DELETE OR UPDATE ON public.campaigns FOR EACH ROW EXECUTE FUNCTION public.protect_campaign_launch();


--
-- Name: campaign_recipients protect_campaign_snapshot; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER protect_campaign_snapshot BEFORE INSERT OR DELETE OR UPDATE ON public.campaign_recipients FOR EACH ROW EXECUTE FUNCTION public.protect_campaign_snapshot();


--
-- Name: campaigns fk_rails_11842c4616; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.campaigns
    ADD CONSTRAINT fk_rails_11842c4616 FOREIGN KEY (confirmed_by_id) REFERENCES public.users(id);


--
-- Name: campaign_recipients fk_rails_1b369e8585; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.campaign_recipients
    ADD CONSTRAINT fk_rails_1b369e8585 FOREIGN KEY (customer_id) REFERENCES public.customers(id);


--
-- Name: orders fk_rails_3dad120da9; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.orders
    ADD CONSTRAINT fk_rails_3dad120da9 FOREIGN KEY (customer_id) REFERENCES public.customers(id);


--
-- Name: consents fk_rails_42f0fa76ae; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.consents
    ADD CONSTRAINT fk_rails_42f0fa76ae FOREIGN KEY (customer_id) REFERENCES public.customers(id);


--
-- Name: campaign_recipients fk_rails_46d74037c7; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.campaign_recipients
    ADD CONSTRAINT fk_rails_46d74037c7 FOREIGN KEY (campaign_id) REFERENCES public.campaigns(id);


--
-- Name: sessions fk_rails_758836b4f0; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sessions
    ADD CONSTRAINT fk_rails_758836b4f0 FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: campaigns fk_rails_9eb8249bf2; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.campaigns
    ADD CONSTRAINT fk_rails_9eb8249bf2 FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: campaign_events fk_rails_be0243a625; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.campaign_events
    ADD CONSTRAINT fk_rails_be0243a625 FOREIGN KEY (campaign_recipient_id) REFERENCES public.campaign_recipients(id);


--
-- PostgreSQL database dump complete
--

SET search_path TO "$user", public;

INSERT INTO "schema_migrations" (version) VALUES
('20261015100000'),
('20261015061000'),
('20261015060000'),
('20261014220000'),
('20261014190000'),
('20261014054217'),
('20261014054216');

