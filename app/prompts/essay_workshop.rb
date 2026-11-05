# frozen_string_literal: true

class EssayWorkshop < MCP::Prompt
  prompt_name "essay_workshop"
  title "Essay Workshop"

  description "A guided writing exercise in which the user writes, corrects, practices, and evaluates a short essay, with an option to publish the final essay as a Post."

  arguments [
    MCP::Prompt::Argument.new(
      name: "language",
      description: "The language in which the writing exercise should be conducted. English by default.",
      required: false
    )
  ]

  class << self
    def template(args, server_context:)
      language = args[:language].presence || "English"

      user_text = <<~PROMPT
        Conduct a guided writing exercise with the user in #{language}.

        Follow these steps:

        1. Suggest a random, interesting, short essay topic about a dream, memory, thought, problem, situation, or a description of an image, book, piece of music, or movie. Ask the user to write several sentences about the topic.

        2. After the user submits their essay:
           - Review it and identify up to 5 important grammar or collocation mistakes.
           - Focus on meaningful errors that affect correctness or naturalness, not minor stylistic preferences.
           - For each mistake, briefly explain why it is incorrect and provide the natural correction.
           - Evaluate the original essay from 1–10 based on grammar, vocabulary, clarity, and naturalness.
           - Create a practice exercise using the user's original sentences: replace the incorrect words or collocations with blanks and ask the user to fill them in.

        3. After the user completes the exercise and the essay has been corrected, offer the user the option to publish the final essay as a Post using the `create_post` tool.
           - Never publish the essay without the user's explicit confirmation.
           - Before publishing, show the final version that will be published and ask for confirmation.

        Keep the exercise interactive: do not complete all steps at once.
        After each stage, wait for the user's response before continuing.
      PROMPT

      MCP::Prompt::Result.new(
        description: "EssayWorkshop",
        messages: [
          MCP::Prompt::Message.new(
            role: "user",
            content: MCP::Content::Text.new(user_text.strip)
          )
        ]
      )
    end
  end
end
