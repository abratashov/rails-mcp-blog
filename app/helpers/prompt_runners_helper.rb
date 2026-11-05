# frozen_string_literal: true

module PromptRunnersHelper
  def prompt_markdown(text)
    sanitize(Kramdown::Document.new(text).to_html)
  end
end
