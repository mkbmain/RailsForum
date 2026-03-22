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
-- Name: ban_reasons; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ban_reasons (
    id bigint NOT NULL,
    name character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: ban_reasons_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.ban_reasons_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: ban_reasons_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.ban_reasons_id_seq OWNED BY public.ban_reasons.id;


--
-- Name: categories; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.categories (
    id smallint NOT NULL,
    name character varying(100) NOT NULL,
    "position" smallint NOT NULL
);


--
-- Name: content_types; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.content_types (
    id integer NOT NULL,
    name character varying(50) NOT NULL
);


--
-- Name: content_types_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.content_types_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: content_types_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.content_types_id_seq OWNED BY public.content_types.id;


--
-- Name: flags; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.flags (
    id integer NOT NULL,
    user_id bigint NOT NULL,
    content_type_id smallint NOT NULL,
    flaggable_id bigint NOT NULL,
    reason smallint NOT NULL,
    resolved_at timestamp(6) without time zone,
    resolved_by_id bigint,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: flags_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.flags_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: flags_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.flags_id_seq OWNED BY public.flags.id;


--
-- Name: notifications; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.notifications (
    id bigint NOT NULL,
    user_id bigint NOT NULL,
    actor_id bigint NOT NULL,
    notifiable_type character varying NOT NULL,
    notifiable_id bigint NOT NULL,
    event_type smallint NOT NULL,
    read_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: notifications_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.notifications_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: notifications_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.notifications_id_seq OWNED BY public.notifications.id;


--
-- Name: posts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.posts (
    id bigint NOT NULL,
    user_id bigint NOT NULL,
    title character varying NOT NULL,
    body text NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    category_id smallint DEFAULT 1 NOT NULL,
    last_replied_at timestamp(6) without time zone,
    removed_at timestamp(6) without time zone,
    removed_by_id bigint,
    last_edited_at timestamp(6) without time zone DEFAULT now() NOT NULL,
    CONSTRAINT posts_body_max_length CHECK ((char_length(body) <= 1000))
);


--
-- Name: posts_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.posts_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: posts_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.posts_id_seq OWNED BY public.posts.id;


--
-- Name: providers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.providers (
    id smallint NOT NULL,
    name character varying(50) NOT NULL
);


--
-- Name: reactions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.reactions (
    id bigint NOT NULL,
    user_id bigint NOT NULL,
    reactionable_id bigint NOT NULL,
    emoji character varying(10) NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    reactionable_type character varying NOT NULL
);


--
-- Name: reactions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.reactions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: reactions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.reactions_id_seq OWNED BY public.reactions.id;


--
-- Name: replies; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.replies (
    id bigint NOT NULL,
    post_id bigint NOT NULL,
    user_id bigint NOT NULL,
    body text NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    removed_at timestamp(6) without time zone,
    removed_by_id bigint,
    last_edited_at timestamp(6) without time zone DEFAULT now() NOT NULL,
    CONSTRAINT replies_body_max_length CHECK ((char_length(body) <= 1000))
);


--
-- Name: replies_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.replies_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: replies_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.replies_id_seq OWNED BY public.replies.id;


--
-- Name: roles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.roles (
    id smallint NOT NULL,
    name character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schema_migrations (
    version character varying NOT NULL
);


--
-- Name: user_bans; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_bans (
    id bigint NOT NULL,
    user_id bigint NOT NULL,
    ban_reason_id bigint NOT NULL,
    banned_from timestamp(6) without time zone DEFAULT now() NOT NULL,
    banned_until timestamp(6) without time zone NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    banned_by_id bigint
);


--
-- Name: user_bans_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.user_bans_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: user_bans_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.user_bans_id_seq OWNED BY public.user_bans.id;


--
-- Name: user_roles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_roles (
    id integer NOT NULL,
    user_id bigint NOT NULL,
    role_id smallint NOT NULL,
    created_at timestamp(6) without time zone DEFAULT now() NOT NULL
);


--
-- Name: user_roles_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.user_roles_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: user_roles_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.user_roles_id_seq OWNED BY public.user_roles.id;


--
-- Name: users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.users (
    id bigint NOT NULL,
    email character varying NOT NULL,
    password_digest character varying,
    name character varying NOT NULL,
    avatar_url character varying,
    provider_id smallint DEFAULT 3 NOT NULL,
    uid character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    bio text
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
-- Name: ban_reasons id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ban_reasons ALTER COLUMN id SET DEFAULT nextval('public.ban_reasons_id_seq'::regclass);


--
-- Name: content_types id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.content_types ALTER COLUMN id SET DEFAULT nextval('public.content_types_id_seq'::regclass);


--
-- Name: flags id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.flags ALTER COLUMN id SET DEFAULT nextval('public.flags_id_seq'::regclass);


--
-- Name: notifications id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notifications ALTER COLUMN id SET DEFAULT nextval('public.notifications_id_seq'::regclass);


--
-- Name: posts id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.posts ALTER COLUMN id SET DEFAULT nextval('public.posts_id_seq'::regclass);


--
-- Name: reactions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reactions ALTER COLUMN id SET DEFAULT nextval('public.reactions_id_seq'::regclass);


--
-- Name: replies id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.replies ALTER COLUMN id SET DEFAULT nextval('public.replies_id_seq'::regclass);


--
-- Name: user_bans id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_bans ALTER COLUMN id SET DEFAULT nextval('public.user_bans_id_seq'::regclass);


--
-- Name: user_roles id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_roles ALTER COLUMN id SET DEFAULT nextval('public.user_roles_id_seq'::regclass);


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
-- Name: ban_reasons ban_reasons_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ban_reasons
    ADD CONSTRAINT ban_reasons_pkey PRIMARY KEY (id);


--
-- Name: categories categories_name_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.categories
    ADD CONSTRAINT categories_name_unique UNIQUE (name);


--
-- Name: categories categories_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.categories
    ADD CONSTRAINT categories_pkey PRIMARY KEY (id);


--
-- Name: content_types content_types_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.content_types
    ADD CONSTRAINT content_types_pkey PRIMARY KEY (id);


--
-- Name: flags flags_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.flags
    ADD CONSTRAINT flags_pkey PRIMARY KEY (id);


--
-- Name: notifications notifications_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notifications
    ADD CONSTRAINT notifications_pkey PRIMARY KEY (id);


--
-- Name: posts posts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.posts
    ADD CONSTRAINT posts_pkey PRIMARY KEY (id);


--
-- Name: providers providers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.providers
    ADD CONSTRAINT providers_pkey PRIMARY KEY (id);


--
-- Name: reactions reactions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reactions
    ADD CONSTRAINT reactions_pkey PRIMARY KEY (id);


--
-- Name: replies replies_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.replies
    ADD CONSTRAINT replies_pkey PRIMARY KEY (id);


--
-- Name: roles roles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.roles
    ADD CONSTRAINT roles_pkey PRIMARY KEY (id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: user_bans user_bans_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_bans
    ADD CONSTRAINT user_bans_pkey PRIMARY KEY (id);


--
-- Name: user_roles user_roles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_roles
    ADD CONSTRAINT user_roles_pkey PRIMARY KEY (id);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: index_ban_reasons_on_name; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_ban_reasons_on_name ON public.ban_reasons USING btree (name);


--
-- Name: index_flags_on_content_type_and_flaggable; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_flags_on_content_type_and_flaggable ON public.flags USING btree (content_type_id, flaggable_id);


--
-- Name: index_flags_on_user_content_flaggable; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_flags_on_user_content_flaggable ON public.flags USING btree (user_id, content_type_id, flaggable_id);


--
-- Name: index_flags_pending_by_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_flags_pending_by_created_at ON public.flags USING btree (created_at) WHERE (resolved_at IS NULL);


--
-- Name: index_notifications_on_actor_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_notifications_on_actor_id ON public.notifications USING btree (actor_id);


--
-- Name: index_notifications_on_dedup_fields; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_notifications_on_dedup_fields ON public.notifications USING btree (user_id, notifiable_id, notifiable_type, event_type, created_at);


--
-- Name: index_notifications_on_notifiable; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_notifications_on_notifiable ON public.notifications USING btree (notifiable_type, notifiable_id);


--
-- Name: index_notifications_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_notifications_on_user_id ON public.notifications USING btree (user_id);


--
-- Name: index_notifications_on_user_id_unread; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_notifications_on_user_id_unread ON public.notifications USING btree (user_id) WHERE (read_at IS NULL);


--
-- Name: index_posts_on_category_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_posts_on_category_id ON public.posts USING btree (category_id);


--
-- Name: index_posts_on_last_replied_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_posts_on_last_replied_at ON public.posts USING btree (last_replied_at);


--
-- Name: index_posts_on_removed_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_posts_on_removed_at ON public.posts USING btree (removed_at) WHERE (removed_at IS NULL);


--
-- Name: index_posts_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_posts_on_user_id ON public.posts USING btree (user_id);


--
-- Name: index_posts_on_user_id_and_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_posts_on_user_id_and_created_at ON public.posts USING btree (user_id, created_at);


--
-- Name: index_reactions_on_reactionable; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_reactions_on_reactionable ON public.reactions USING btree (reactionable_type, reactionable_id);


--
-- Name: index_reactions_on_user_and_reactionable; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_reactions_on_user_and_reactionable ON public.reactions USING btree (user_id, reactionable_type, reactionable_id);


--
-- Name: index_reactions_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_reactions_on_user_id ON public.reactions USING btree (user_id);


--
-- Name: index_replies_on_post_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_replies_on_post_id ON public.replies USING btree (post_id);


--
-- Name: index_replies_on_removed_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_replies_on_removed_at ON public.replies USING btree (removed_at) WHERE (removed_at IS NULL);


--
-- Name: index_replies_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_replies_on_user_id ON public.replies USING btree (user_id);


--
-- Name: index_replies_on_user_id_and_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_replies_on_user_id_and_created_at ON public.replies USING btree (user_id, created_at);


--
-- Name: index_roles_on_name; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_roles_on_name ON public.roles USING btree (name);


--
-- Name: index_user_bans_on_ban_reason_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_user_bans_on_ban_reason_id ON public.user_bans USING btree (ban_reason_id);


--
-- Name: index_user_bans_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_user_bans_on_user_id ON public.user_bans USING btree (user_id);


--
-- Name: index_user_bans_on_user_id_and_banned_until; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_user_bans_on_user_id_and_banned_until ON public.user_bans USING btree (user_id, banned_until);


--
-- Name: index_user_roles_on_user_id_and_role_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_user_roles_on_user_id_and_role_id ON public.user_roles USING btree (user_id, role_id);


--
-- Name: index_users_on_email; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_users_on_email ON public.users USING btree (email);


--
-- Name: index_users_on_provider_id_and_uid; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_users_on_provider_id_and_uid ON public.users USING btree (provider_id, uid) WHERE (uid IS NOT NULL);


--
-- Name: flags fk_rails_05feec802b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.flags
    ADD CONSTRAINT fk_rails_05feec802b FOREIGN KEY (content_type_id) REFERENCES public.content_types(id);


--
-- Name: notifications fk_rails_06a39bb8cc; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notifications
    ADD CONSTRAINT fk_rails_06a39bb8cc FOREIGN KEY (actor_id) REFERENCES public.users(id);


--
-- Name: users fk_rails_0e71a0cbe4; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT fk_rails_0e71a0cbe4 FOREIGN KEY (provider_id) REFERENCES public.providers(id);


--
-- Name: replies fk_rails_256e4b72c5; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.replies
    ADD CONSTRAINT fk_rails_256e4b72c5 FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: user_roles fk_rails_318345354e; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_roles
    ADD CONSTRAINT fk_rails_318345354e FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: user_roles fk_rails_3369e0d5fc; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_roles
    ADD CONSTRAINT fk_rails_3369e0d5fc FOREIGN KEY (role_id) REFERENCES public.roles(id);


--
-- Name: posts fk_rails_3f2d268207; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.posts
    ADD CONSTRAINT fk_rails_3f2d268207 FOREIGN KEY (removed_by_id) REFERENCES public.users(id);


--
-- Name: posts fk_rails_5b5ddfd518; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.posts
    ADD CONSTRAINT fk_rails_5b5ddfd518 FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: replies fk_rails_63380d423b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.replies
    ADD CONSTRAINT fk_rails_63380d423b FOREIGN KEY (post_id) REFERENCES public.posts(id);


--
-- Name: posts fk_rails_9b1b26f040; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.posts
    ADD CONSTRAINT fk_rails_9b1b26f040 FOREIGN KEY (category_id) REFERENCES public.categories(id);


--
-- Name: reactions fk_rails_9f02fc96a0; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reactions
    ADD CONSTRAINT fk_rails_9f02fc96a0 FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: notifications fk_rails_b080fb4855; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notifications
    ADD CONSTRAINT fk_rails_b080fb4855 FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: user_bans fk_rails_b27db52384; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_bans
    ADD CONSTRAINT fk_rails_b27db52384 FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: user_bans fk_rails_c15024a086; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_bans
    ADD CONSTRAINT fk_rails_c15024a086 FOREIGN KEY (ban_reason_id) REFERENCES public.ban_reasons(id);


--
-- Name: flags fk_rails_d2e998acee; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.flags
    ADD CONSTRAINT fk_rails_d2e998acee FOREIGN KEY (resolved_by_id) REFERENCES public.users(id);


--
-- Name: flags fk_rails_d7842de637; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.flags
    ADD CONSTRAINT fk_rails_d7842de637 FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: replies fk_rails_e64bb1a837; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.replies
    ADD CONSTRAINT fk_rails_e64bb1a837 FOREIGN KEY (removed_by_id) REFERENCES public.users(id);


--
-- Name: user_bans fk_rails_ffcefbeed8; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_bans
    ADD CONSTRAINT fk_rails_ffcefbeed8 FOREIGN KEY (banned_by_id) REFERENCES public.users(id);


--
-- PostgreSQL database dump complete
--

SET search_path TO "$user", public;

INSERT INTO "schema_migrations" (version) VALUES
('20260322031927'),
('20260321021906'),
('20260321014337'),
('20260319160355'),
('20260317135601'),
('20260317135600'),
('20260317135559'),
('20260317114403'),
('20260317114348'),
('20260317102012'),
('20260317101956'),
('20260316134716'),
('20260316134715'),
('20260315200000'),
('20260315175233'),
('20260315175008'),
('20260315000002'),
('20260315000001'),
('20260314203927'),
('20260314203922'),
('20260314203903'),
('20260314203844');

