require "test_helper"

class McpToolsTest < ActiveSupport::TestCase
  setup do
    @post = Post.create!(title: "Original title", body: "Original body")
    @comment = @post.comments.create!(content: "Original comment")
  end

  test "creates, shows, updates, and deletes posts" do
    created = Posts::CreateTool.call(title: "New title", body: "New body", server_context: {})
    assert_includes text(created), "Created Post"
    post = Post.order(:id).last

    shown = Posts::ShowTool.call(id: post.id, server_context: {})
    assert_includes text(shown), "New title"

    updated = Posts::UpdateTool.call(id: post.id, title: "Updated title", server_context: {})
    assert_includes text(updated), "Updated title"
    assert_equal "New body", post.reload.body

    deleted = Posts::DeleteTool.call(id: post.id, server_context: {})
    assert_includes text(deleted), "was deleted"
    assert_not Post.exists?(post.id)
  end

  test "reports missing posts and handles unexpected errors" do
    missing = Posts::ShowTool.call(id: -1, server_context: {})
    assert_includes text(missing), "Post of id = -1 was not found"

    with_stubbed_method(Post, :find, ->(*) { raise "database unavailable" }) do
      error = Posts::ShowTool.call(id: @post.id, server_context: {})
      assert_includes text(error), "database unavailable"
    end
  end

  test "reports failed post writes and deleting a missing post" do
    with_stubbed_method(Post, :new, ->(**) { raise "write failed" }) do
      error = Posts::CreateTool.call(title: "Bad", body: "Bad", server_context: {})
      assert_includes text(error), "write failed"
    end

    missing = Posts::DeleteTool.call(id: -1, server_context: {})
    assert_includes text(missing), "Post of id = -1 was not found"
  end

  test "lists posts and reports an empty result" do
    listed = Posts::IndexTool.call(count: 1, server_context: {})
    assert_includes text(listed), "Original title"

    Post.destroy_all
    empty = Posts::IndexTool.call(server_context: {})
    assert_equal "Nothing was found", text(empty)
  end

  test "creates, shows, updates, and deletes comments" do
    created = Comments::CreateTool.call(
      post_id: @post.id,
      content: "New comment",
      server_context: {}
    )
    assert_includes text(created), "Created Comment"
    comment = @post.comments.order(:id).last

    shown = Comments::ShowTool.call(id: comment.id, server_context: {})
    assert_includes text(shown), "New comment"

    updated = Comments::UpdateTool.call(
      id: comment.id,
      content: "Updated comment",
      server_context: {}
    )
    assert_includes text(updated), "Updated comment"
    assert_equal @post.id, comment.reload.post_id

    deleted = Comments::DeleteTool.call(id: comment.id, server_context: {})
    assert_includes text(deleted), "was deleted"
    assert_not Comment.exists?(comment.id)
  end

  test "filters comments and reports empty, invalid, and missing results" do
    other_post = Post.create!(title: "Other", body: "Other")
    other_post.comments.create!(content: "Other comment")

    filtered = Comments::IndexTool.call(post_id: @post.id, server_context: {})
    assert_includes text(filtered), "Original comment"
    assert_not_includes text(filtered), "Other comment"

    empty = Comments::IndexTool.call(post_id: -1, server_context: {})
    assert_equal "Nothing was found", text(empty)

    invalid = Comments::CreateTool.call(post_id: -1, content: "Orphan", server_context: {})
    assert_includes text(invalid), "Comment was not created"
    assert_includes text(Comments::ShowTool.call(id: -1, server_context: {})), "was not found"
    assert_includes text(Comments::DeleteTool.call(id: -1, server_context: {})), "was not found"
  end

  test "reports a failed comment update" do
    response = Comments::UpdateTool.call(
      id: @comment.id,
      post_id: -1,
      server_context: {}
    )

    assert_includes text(response), "was not updated"
  end

  private

  def text(response)
    response.content.first.fetch(:text)
  end

  def with_stubbed_method(object, method_name, replacement)
    original = object.method(method_name)
    object.define_singleton_method(method_name, &replacement)
    yield
  ensure
    object.define_singleton_method(method_name, original)
  end
end
