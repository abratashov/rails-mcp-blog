require "test_helper"

class PostsResourceTest < ActiveSupport::TestCase
  self.fixture_table_names = []

  setup do
    @post = Post.create!(title: "Test post", body: "Test body")
    Comment.create!(post: @post, content: "Test comment")
  end

  test "reads a post and its comments as markdown" do
    contents = Posts::Resource.contents(id: @post.id)

    assert_equal "posts://#{@post.id}", contents.uri
    assert_includes contents.text, "# Test post"
    assert_includes contents.text, "Test comment"
  end
end