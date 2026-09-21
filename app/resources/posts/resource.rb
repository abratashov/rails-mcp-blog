# frozen_string_literal: true

module Posts
  class Resource < MCP::ResourceTemplate
    uri_template "posts://{id}"
    resource_template_name "post"
    description "Read a blog post and its comments as Markdown"
    mime_type "text/markdown"

    def self.contents(id:, server_context: nil)
      post = Post.includes(:comments).find(id)
      comments = post.comments.order(:created_at)

      text = <<~MARKDOWN
        # #{post.title}

        #{post.body}

        ## Comments
      MARKDOWN

      if comments.empty?
        text << "\n_No comments._\n"
      else
        comments.each do |comment|
          text << "\n- #{comment.content}\n"
        end
      end

      MCP::Resource::TextContents.new(
        uri: "posts://#{post.id}",
        mime_type: "text/markdown",
        text: text
      )
    end
  end
end