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

ActiveRecord::Schema[8.1].define(version: 2026_05_22_000001) do
  # Custom types defined in this database.
  # Note that some types may not work with other database engines. Be careful if changing database.
  create_enum "crdb_internal_region", ["aws-eu-west-2"]

  create_table "backup_codes", id: :bigint, default: -> { "unique_rowid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "digest", null: false
    t.datetime "used_at"
    t.bigint "user_id", null: false
    t.index ["user_id"], name: "index_backup_codes_on_user_id"
    t.unique_constraint ["user_id", "digest"], name: "index_backup_codes_on_user_id_and_digest"
  end

  create_table "ban_reasons", id: :bigint, default: -> { "unique_rowid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false

    t.unique_constraint ["name"], name: "index_ban_reasons_on_name"
  end

  create_table "categories", id: { type: :integer, limit: 2, default: nil }, force: :cascade do |t|
    t.string "name", limit: 100, null: false
    t.integer "position", limit: 2, null: false

    t.unique_constraint ["name"], name: "categories_name_unique"
  end

  create_table "content_types", id: :bigint, default: -> { "unique_rowid()" }, force: :cascade do |t|
    t.string "name", limit: 50, null: false
  end

  create_table "email_verifications", id: :bigint, default: -> { "unique_rowid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "last_sent_at"
    t.string "token", null: false
    t.bigint "user_id", null: false

    t.unique_constraint ["token"], name: "index_email_verifications_on_token"
    t.unique_constraint ["user_id"], name: "index_email_verifications_on_user_id"
  end

  create_table "flags", id: :bigint, default: -> { "unique_rowid()" }, force: :cascade do |t|
    t.integer "content_type_id", limit: 2, null: false
    t.datetime "created_at", null: false
    t.bigint "flaggable_id", null: false
    t.integer "reason", limit: 2, null: false
    t.datetime "resolved_at"
    t.bigint "resolved_by_id"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["content_type_id", "flaggable_id"], name: "index_flags_on_content_type_and_flaggable"
    t.index ["created_at"], name: "index_flags_pending_by_created_at", where: "(resolved_at IS NULL)"
    t.unique_constraint ["user_id", "content_type_id", "flaggable_id"], name: "index_flags_on_user_content_flaggable"
  end

  create_table "notifications", id: :bigint, default: -> { "unique_rowid()" }, force: :cascade do |t|
    t.bigint "actor_id", null: false
    t.datetime "created_at", null: false
    t.integer "event_type", limit: 2, null: false
    t.bigint "notifiable_id", null: false
    t.string "notifiable_type", null: false
    t.datetime "read_at"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["actor_id"], name: "index_notifications_on_actor_id"
    t.index ["notifiable_type", "notifiable_id"], name: "index_notifications_on_notifiable"
    t.index ["user_id", "notifiable_id", "notifiable_type", "event_type", "created_at"], name: "index_notifications_on_dedup_fields"
    t.index ["user_id"], name: "index_notifications_on_user_id"
    t.index ["user_id"], name: "index_notifications_on_user_id_unread", where: "(read_at IS NULL)"
  end

  create_table "password_resets", id: :bigint, default: -> { "unique_rowid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "last_sent_at"
    t.string "token", null: false
    t.bigint "user_id", null: false

    t.unique_constraint ["token"], name: "index_password_resets_on_token"
    t.unique_constraint ["user_id"], name: "index_password_resets_on_user_id"
  end

  create_table "posts", id: :bigint, default: -> { "unique_rowid()" }, force: :cascade do |t|
    t.text "body", null: false
    t.integer "category_id", limit: 2, default: 1, null: false
    t.datetime "created_at", null: false
    t.datetime "last_edited_at", default: -> { "now()" }, null: false
    t.datetime "last_replied_at"
    t.datetime "removed_at"
    t.bigint "removed_by_id"
    t.virtual "search_vector", type: :tsvector, as: "to_tsvector('english'::STRING, (COALESCE(title, ''::STRING) || ' '::STRING) || COALESCE(body, ''::STRING))", stored: true
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["category_id"], name: "index_posts_on_category_id"
    t.index ["last_replied_at"], name: "index_posts_on_last_replied_at"
    t.index ["removed_at"], name: "index_posts_on_removed_at", where: "(removed_at IS NULL)"
    t.index ["search_vector"], name: "index_posts_on_search_vector", using: :gin
    t.index ["user_id", "created_at"], name: "index_posts_on_user_id_and_created_at"
    t.index ["user_id"], name: "index_posts_on_user_id"
    t.check_constraint "(char_length(body) <= 1000)", name: "posts_body_max_length"
  end

  create_table "providers", id: { type: :integer, limit: 2, default: nil }, force: :cascade do |t|
    t.string "name", limit: 50, null: false
  end

  create_table "reactions", id: :bigint, default: -> { "unique_rowid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "emoji", limit: 10, null: false
    t.bigint "reactionable_id", null: false
    t.string "reactionable_type", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["reactionable_type", "reactionable_id"], name: "index_reactions_on_reactionable"
    t.index ["user_id"], name: "index_reactions_on_user_id"
    t.unique_constraint ["user_id", "reactionable_type", "reactionable_id"], name: "index_reactions_on_user_and_reactionable"
  end

  create_table "replies", id: :bigint, default: -> { "unique_rowid()" }, force: :cascade do |t|
    t.text "body", null: false
    t.datetime "created_at", null: false
    t.datetime "last_edited_at", default: -> { "now()" }, null: false
    t.bigint "post_id", null: false
    t.datetime "removed_at"
    t.bigint "removed_by_id"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["post_id"], name: "index_replies_on_post_id"
    t.index ["removed_at"], name: "index_replies_on_removed_at", where: "(removed_at IS NULL)"
    t.index ["user_id", "created_at"], name: "index_replies_on_user_id_and_created_at"
    t.index ["user_id"], name: "index_replies_on_user_id"
    t.check_constraint "(char_length(body) <= 1000)", name: "replies_body_max_length"
  end

  create_table "roles", id: { type: :integer, limit: 2, default: nil }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false

    t.unique_constraint ["name"], name: "index_roles_on_name"
  end

  create_table "user_bans", id: :bigint, default: -> { "unique_rowid()" }, force: :cascade do |t|
    t.bigint "ban_reason_id", null: false
    t.bigint "banned_by_id"
    t.datetime "banned_from", default: -> { "now()" }, null: false
    t.datetime "banned_until", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["ban_reason_id"], name: "index_user_bans_on_ban_reason_id"
    t.index ["user_id", "banned_until"], name: "index_user_bans_on_user_id_and_banned_until"
    t.index ["user_id"], name: "index_user_bans_on_user_id"
  end

  create_table "user_roles", id: :bigint, default: -> { "unique_rowid()" }, force: :cascade do |t|
    t.datetime "created_at", default: -> { "now()" }, null: false
    t.integer "role_id", limit: 2, null: false
    t.bigint "user_id", null: false

    t.unique_constraint ["user_id", "role_id"], name: "index_user_roles_on_user_id_and_role_id"
  end

  create_table "users", id: :bigint, default: -> { "unique_rowid()" }, force: :cascade do |t|
    t.string "avatar_url"
    t.text "bio"
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.datetime "email_verified_at"
    t.string "name", null: false
    t.string "password_digest"
    t.integer "provider_id", limit: 2, default: 3, null: false
    t.string "totp_secret"
    t.string "uid"
    t.datetime "updated_at", null: false
    t.index "lower(name) ASC", name: "index_users_on_lower_name"
    t.check_constraint "(char_length(bio) <= 500)", name: "users_bio_max_length"
    t.unique_constraint ["........pg.dropped.12........"], name: "index_users_on_lower_email"
    t.unique_constraint ["provider_id", "uid"], name: "index_users_on_provider_id_and_uid"
  end

  add_foreign_key "backup_codes", "users", on_delete: :cascade
  add_foreign_key "email_verifications", "users", on_delete: :cascade
  add_foreign_key "flags", "content_types"
  add_foreign_key "flags", "users"
  add_foreign_key "flags", "users", column: "resolved_by_id"
  add_foreign_key "notifications", "users"
  add_foreign_key "notifications", "users", column: "actor_id"
  add_foreign_key "password_resets", "users", on_delete: :cascade
  add_foreign_key "posts", "categories"
  add_foreign_key "posts", "users"
  add_foreign_key "posts", "users", column: "removed_by_id"
  add_foreign_key "reactions", "users"
  add_foreign_key "replies", "posts"
  add_foreign_key "replies", "users"
  add_foreign_key "replies", "users", column: "removed_by_id"
  add_foreign_key "user_bans", "ban_reasons"
  add_foreign_key "user_bans", "users"
  add_foreign_key "user_bans", "users", column: "banned_by_id"
  add_foreign_key "user_roles", "roles"
  add_foreign_key "user_roles", "users"
  add_foreign_key "users", "providers"
end
