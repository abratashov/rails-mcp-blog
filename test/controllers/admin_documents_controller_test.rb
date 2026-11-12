require "test_helper"

class AdminDocumentsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @embedding_env = %w[
      EMBEDDING_PROVIDER EMBEDDING_MODEL EMBEDDING_DIMENSIONS EMBEDDING_CONFIGURATION_VERSION
    ].to_h { |key| [ key, ENV[key] ] }
    ENV["EMBEDDING_PROVIDER"] = "openai_compatible"
    ENV["EMBEDDING_MODEL"] = "text-embedding-3-small"
    ENV["EMBEDDING_DIMENSIONS"] = "1536"
    ENV["EMBEDDING_CONFIGURATION_VERSION"] = "1"

    @user = users(:one)
    @user.update!(password: "secure-password", password_confirmation: "secure-password")
    post user_session_path, params: {
      user: { email: @user.email, password: "secure-password" }
    }
  end

  teardown do
    @embedding_env.each { |key, value| ENV[key] = value }
  end

  test "any signed-in user can access the admin dashboard and document uploads" do
    get admin_root_path
    assert_response :success

    get new_admin_document_path
    assert_response :success
    assert_select "input[type=file]"
    assert_select "select[name='document[user_id]'] option[selected][value='#{@user.id}']"
  end

  test "the admin area requires a signed-in user" do
    delete destroy_user_session_path

    get admin_root_path

    assert_redirected_to new_user_session_path
  end

  test "a different signed-in user also has full admin access" do
    delete destroy_user_session_path
    another_user = users(:two)
    another_user.update!(password: "another-password", password_confirmation: "another-password")
    post user_session_path, params: {
      user: { email: another_user.email, password: "another-password" }
    }

    get admin_documents_path

    assert_response :success
  end

  test "admin can inspect document and chunks and retry failed processing" do
    document = create_document
    chunk = document.document_chunks.create!(
      content: "Extracted text",
      position: 1,
      page_start: 2,
      page_end: 3,
      metadata: { "source" => "test" }
    )
    embedding = chunk.document_chunk_embeddings.create!(
      provider: "openai_compatible",
      model: "text-embedding-3-small",
      dimensions: 1_536,
      configuration_version: "1",
      input_checksum: Digest::SHA256.hexdigest(chunk.content),
      status: "completed",
      embedding: Array.new(1_536, 0.1)
    )

    get admin_documents_path
    assert_response :success
    assert_select "td", text: document.filename

    get admin_document_path(document)
    assert_response :success
    assert_select "td", text: chunk.content
    assert_select "h3", text: "Embedding progress"
    assert_select "td", text: "completed"
    assert_select "form[action='#{admin_document_path(document)}'] input[name='_method'][value='delete']"
    assert_select "form[action='#{admin_document_path(document)}'] button", text: "Delete document"

    get admin_document_chunks_path
    assert_response :success
    get admin_document_chunk_path(chunk)
    assert_response :success
    assert_select "td", text: chunk.content
    assert_select "td", text: "text-embedding-3-small"

    get admin_document_chunk_embeddings_path
    assert_response :success
    assert_select "td", text: "openai_compatible"
    get admin_document_chunk_embedding_path(embedding)
    assert_response :success
    assert_select "td", text: "1"

    document.update!(status: "failed", processing_error: "Parser error")
    assert_enqueued_with(job: ProcessDocumentJob) do
      post retry_processing_admin_document_path(document)
    end
    assert_redirected_to admin_document_path(document)
    assert_equal "pending", document.reload.status
    assert_nil document.processing_error
  end

  test "admin can retry a failed embedding for a document or an individual chunk" do
    document = create_document
    chunk = document.document_chunks.create!(content: "Extracted text", position: 1)
    chunk.document_chunk_embeddings.create!(
      provider: "openai_compatible",
      model: "text-embedding-3-small",
      dimensions: 1_536,
      configuration_version: "1",
      input_checksum: Digest::SHA256.hexdigest(chunk.content),
      status: "failed",
      error_message: "Provider unavailable"
    )

    assert_enqueued_with(job: GenerateDocumentEmbeddingsJob) do
      post retry_embedding_admin_document_chunk_path(chunk)
    end
    assert_redirected_to admin_document_chunk_path(chunk)

    assert_enqueued_with(job: GenerateDocumentEmbeddingsJob) do
      post retry_embeddings_admin_document_path(document)
    end
    assert_redirected_to admin_document_path(document)
  end

  test "admin can delete a document with its chunks" do
    document = create_document
    document.document_chunks.create!(content: "Extracted text", position: 1)

    assert_difference("Document.count", -1) do
      delete admin_document_path(document)
    end
    assert_empty DocumentChunk.where(document_id: document.id)
  end

  private

  def create_document
    document = Document.new(user: users(:one))
    document.file.attach(
      io: StringIO.new("A test document."),
      filename: "admin-upload.txt",
      content_type: "text/plain"
    )
    document.save!
    document
  end
end
