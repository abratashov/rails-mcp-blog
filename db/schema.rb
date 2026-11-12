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

ActiveRecord::Schema[8.1].define(version: 2026_11_12_140000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "vector"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "comments", force: :cascade do |t|
    t.text "content"
    t.datetime "created_at", null: false
    t.integer "post_id", null: false
    t.datetime "updated_at", null: false
    t.index ["post_id"], name: "index_comments_on_post_id"
  end

  create_table "document_chunk_embeddings", force: :cascade do |t|
    t.string "configuration_version", limit: 64, null: false
    t.datetime "created_at", null: false
    t.integer "dimensions", null: false
    t.bigint "document_chunk_id", null: false
    t.vector "embedding"
    t.text "error_message"
    t.string "input_checksum", null: false
    t.string "model", null: false
    t.string "provider", limit: 64, null: false
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["document_chunk_id", "provider", "model", "dimensions", "configuration_version"], name: "index_document_chunk_embeddings_on_identity", unique: true
    t.index ["document_chunk_id"], name: "index_document_chunk_embeddings_on_document_chunk_id"
    t.index ["provider", "model", "dimensions", "configuration_version", "status"], name: "index_embeddings_on_retrieval_identity"
    t.index ["status"], name: "index_document_chunk_embeddings_on_status"
    t.check_constraint "dimensions >= 1 AND dimensions <= 16000", name: "document_chunk_embeddings_dimensions_valid"
    t.check_constraint "embedding IS NULL OR vector_dims(embedding) = dimensions", name: "document_chunk_embeddings_vector_dimensions_match"
    t.check_constraint "status::text = 'completed'::text AND embedding IS NOT NULL OR status::text <> 'completed'::text AND embedding IS NULL", name: "document_chunk_embeddings_status_matches_embedding"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying, 'processing'::character varying, 'completed'::character varying, 'failed'::character varying]::text[])", name: "document_chunk_embeddings_valid_status"
  end

  create_table "document_chunks", force: :cascade do |t|
    t.text "content", null: false
    t.datetime "created_at", null: false
    t.bigint "document_id", null: false
    t.jsonb "metadata", default: {}, null: false
    t.integer "page_end"
    t.integer "page_start"
    t.integer "position", null: false
    t.datetime "updated_at", null: false
    t.index ["document_id", "position"], name: "index_document_chunks_on_document_id_and_position", unique: true
    t.index ["document_id"], name: "index_document_chunks_on_document_id"
    t.index ["metadata"], name: "index_document_chunks_on_metadata", using: :gin
  end

  create_table "documents", force: :cascade do |t|
    t.string "checksum", null: false
    t.string "content_type", null: false
    t.datetime "created_at", null: false
    t.bigint "file_size", null: false
    t.string "filename", null: false
    t.text "processing_error"
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id", "checksum"], name: "index_documents_on_user_id_and_checksum", unique: true
    t.index ["user_id"], name: "index_documents_on_user_id"
  end

  create_table "oauth_access_grants", force: :cascade do |t|
    t.integer "application_id", null: false
    t.string "code_challenge"
    t.string "code_challenge_method"
    t.datetime "created_at", null: false
    t.integer "expires_in", null: false
    t.text "redirect_uri", null: false
    t.string "resource"
    t.integer "resource_owner_id", null: false
    t.datetime "revoked_at"
    t.string "scopes", default: "", null: false
    t.string "token", null: false
    t.index ["application_id"], name: "index_oauth_access_grants_on_application_id"
    t.index ["resource_owner_id"], name: "index_oauth_access_grants_on_resource_owner_id"
    t.index ["token"], name: "index_oauth_access_grants_on_token", unique: true
  end

  create_table "oauth_access_tokens", force: :cascade do |t|
    t.integer "application_id", null: false
    t.datetime "created_at", null: false
    t.integer "expires_in"
    t.string "previous_refresh_token", default: "", null: false
    t.string "refresh_token"
    t.string "resource"
    t.integer "resource_owner_id"
    t.datetime "revoked_at"
    t.string "scopes"
    t.string "token", null: false
    t.index ["application_id"], name: "index_oauth_access_tokens_on_application_id"
    t.index ["refresh_token"], name: "index_oauth_access_tokens_on_refresh_token", unique: true
    t.index ["resource"], name: "index_oauth_access_tokens_on_resource"
    t.index ["resource_owner_id"], name: "index_oauth_access_tokens_on_resource_owner_id"
    t.index ["token"], name: "index_oauth_access_tokens_on_token", unique: true
  end

  create_table "oauth_applications", force: :cascade do |t|
    t.boolean "confidential", default: true, null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.text "redirect_uri", null: false
    t.string "scopes", default: "", null: false
    t.string "secret", null: false
    t.string "uid", null: false
    t.datetime "updated_at", null: false
    t.index ["uid"], name: "index_oauth_applications_on_uid", unique: true
  end

  create_table "posts", force: :cascade do |t|
    t.text "body"
    t.datetime "created_at", null: false
    t.string "title"
    t.datetime "updated_at", null: false
  end

  create_table "rag_conversations", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.jsonb "messages", default: [], null: false
    t.jsonb "metadata", default: {}, null: false
    t.string "title"
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.index ["user_id"], name: "index_rag_conversations_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "comments", "posts"
  add_foreign_key "document_chunk_embeddings", "document_chunks", on_delete: :cascade
  add_foreign_key "document_chunks", "documents", on_delete: :cascade
  add_foreign_key "documents", "users"
  add_foreign_key "oauth_access_grants", "oauth_applications", column: "application_id"
  add_foreign_key "oauth_access_grants", "users", column: "resource_owner_id"
  add_foreign_key "oauth_access_tokens", "oauth_applications", column: "application_id"
  add_foreign_key "oauth_access_tokens", "users", column: "resource_owner_id"
  add_foreign_key "rag_conversations", "users"
end
