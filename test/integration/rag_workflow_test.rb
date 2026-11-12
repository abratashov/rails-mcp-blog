require "test_helper"

class RagWorkflowTest < ActionDispatch::IntegrationTest
  setup do
    @embedding_env = %w[
      EMBEDDING_PROVIDER EMBEDDING_API_BASE_URL EMBEDDING_API_KEY EMBEDDING_MODEL
      EMBEDDING_DIMENSIONS EMBEDDING_CONFIGURATION_VERSION EMBEDDING_BATCH_SIZE
      LLM_PROVIDER
    ].to_h { |key| [ key, ENV[key] ] }
    ENV["EMBEDDING_PROVIDER"] = "openai_compatible"
    ENV["EMBEDDING_API_BASE_URL"] = "https://embeddings.example.test/v1"
    ENV["EMBEDDING_API_KEY"] = "test-key"
    ENV["EMBEDDING_MODEL"] = "workflow-test-embedding"
    ENV["EMBEDDING_DIMENSIONS"] = "3"
    ENV["EMBEDDING_CONFIGURATION_VERSION"] = "workflow-test-v1"
    ENV["EMBEDDING_BATCH_SIZE"] = "10"
    ENV["LLM_PROVIDER"] = "vllm"

    @user = users(:one)
    @user.update!(password: "secure-password", password_confirmation: "secure-password")
    post user_session_path, params: {
      user: { email: @user.email, password: "secure-password" }
    }

    @embedding_request = stub_request(:post, "https://embeddings.example.test/v1/embeddings")
      .to_return do |request|
        inputs = JSON.parse(request.body).fetch("input")
        {
          status: 200,
          headers: { "Content-Type" => "application/json" },
          body: {
            data: inputs.each_index.map do |index|
              { index: index, embedding: [ 1.0, 0.0, 0.0 ] }
            end
          }.to_json
        }
      end

    @answer_request = stub_request(:post, "http://localhost:8000/v1/chat/completions")
      .with do |request|
        body = JSON.parse(request.body)
        body.fetch("messages").any? do |message|
          message["content"].include?("The red fox sleeps in a hollow beneath the pine trees.") &&
            message["content"].include?("Where does the red fox sleep?")
        end
      end
      .to_return(
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body: {
          choices: [
            { message: { role: "assistant", content: "The red fox sleeps in a hollow beneath the pine trees. [1]" } }
          ]
        }.to_json
      )
  end

  teardown do
    @embedding_env.each { |key, value| ENV[key] = value }
  end

  test "uploads, extracts, chunks, embeds, retrieves, and returns a cited answer" do
    uploaded_file = Rack::Test::UploadedFile.new(
      StringIO.new("The red fox sleeps in a hollow beneath the pine trees."),
      "text/plain",
      original_filename: "forest-guide.txt"
    )

    perform_enqueued_jobs do
      post admin_documents_path, params: { document: { file: uploaded_file } }
    end

    assert_response :redirect
    document = Document.find_by!(filename: "forest-guide.txt")
    chunk = document.document_chunks.sole
    embedding = chunk.document_chunk_embeddings.sole
    assert_equal "completed", document.status
    assert_includes chunk.content, "The red fox sleeps in a hollow beneath the pine trees."
    assert_equal "completed", embedding.status
    assert_equal [ 1.0, 0.0, 0.0 ], embedding.embedding

    post chat_path, params: {
      message: "Where does the red fox sleep?",
      document_id: document.id
    }

    conversation = @user.rag_conversations.order(:id).last
    assert_response :redirect
    assert_equal "assistant", conversation.messages.last["role"]
    assert_includes conversation.messages.last["content"], "The red fox sleeps in a hollow beneath the pine trees."
    assert_includes conversation.messages.last["content"], "Sources: [1] forest-guide.txt"
    assert_requested @embedding_request, times: 2
    assert_requested @answer_request, times: 1
  end
end
