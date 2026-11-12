require "test_helper"

class PostsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    sign_in users(:one)
    @post = posts(:one)
  end

  test "should get index" do
    get posts_url
    assert_response :success
    assert_select "main.posts-page"
    assert_select ".posts-page__header h1", "Posts"
    assert_select "#posts a[href='#{post_path(@post)}']", text: @post.title
    assert_select "nav[aria-label='Main navigation']" do
      assert_select "a[href='#{posts_path}']", text: "Posts"
      assert_select "a[href='#{new_post_path}']", text: "New post"
      assert_select "a[href='#{prompts_path}']", text: "Run a prompt"
      assert_select "a[href='#{admin_dashboard_path}']", text: "Admin"
    end
    assert_select "body > a", count: 0
  end

  test "should get new" do
    get new_post_url
    assert_response :success
    assert_select "main.posts-page"
    assert_select ".posts-page__form-panel"
    assert_select "input[name='post[title]']"
    assert_select "textarea[name='post[body]']"
  end

  test "should create post" do
    assert_difference("Post.count") do
      post posts_url, params: { post: { body: @post.body, title: @post.title } }
    end

    assert_redirected_to post_url(Post.last)
  end

  test "should show post" do
    get post_url(@post)
    assert_response :success
    assert_select "main.posts-page"
    assert_select ".posts-page__detail"
    assert_select ".posts-page__actions a[href='#{edit_post_path(@post)}']", text: "Edit post"
    assert_select ".posts-page__actions form[action='#{post_path(@post)}'] button[aria-label='Delete post'] svg[aria-hidden='true']"
  end

  test "should get edit" do
    get edit_post_url(@post)
    assert_response :success
  end

  test "should update post" do
    patch post_url(@post), params: { post: { body: @post.body, title: @post.title } }
    assert_redirected_to post_url(@post)
  end

  test "should destroy post" do
    assert_difference("Post.count", -1) do
      delete post_url(@post)
    end

    assert_redirected_to posts_url
  end
end
