class Post < ApplicationRecord
  has_many :comments, dependent: :destroy

  broadcasts_to :replace_posts

  private

  def replace_posts
    broadcast_replace_to "posts", target: "posts", partial: "posts/posts"
  end
end
