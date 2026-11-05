# frozen_string_literal: true

require "dotenv"
require "json"
require "tty-markdown"

Dotenv.load(Rails.root.join(".env.development"))

namespace :mcp do
  desc "Run any registered MCP prompt (PROMPT_ARGUMENTS accepts a JSON object)"

  task :prompt_runner, [ :prompt_name ] => :environment do |_task, args|
    prompt_name = args[:prompt_name].presence || ENV.fetch("PROMPT_NAME", "essay_workshop")
    prompt_arguments = JSON.parse(ENV.fetch("PROMPT_ARGUMENTS", "{}"))
    raise ArgumentError, "PROMPT_ARGUMENTS must be a JSON object" unless prompt_arguments.is_a?(Hash)

    # ----------------------------------------------------------
    # Authenticate the CLI user
    # ----------------------------------------------------------

    puts "=== Prompt: #{prompt_name} ==="
    puts
    puts "Authentication required."

    access_token = authenticate

    # ----------------------------------------------------------
    # Create authenticated workshop
    # ----------------------------------------------------------

    workshop = AI::PromptRunner.new(
      prompt_name: prompt_name,
      prompt_arguments: prompt_arguments,
      provider: ENV.fetch("LLM_PROVIDER").to_sym,
      access_token: access_token
    )

    quit_cmds = %w[
      /quit
      /q
      /bye
      \quit
      \q
      \bye
    ]

    puts "To QUIT type any of these commands:"
    puts quit_cmds.join(", ")
    puts

    puts "Prompt:"
    puts workshop.initial_prompt[:content]
    puts

    begin
      # --------------------------------------------------------
      # Initial AI response
      # --------------------------------------------------------

      result = workshop.start

      print_tool_calls(result)

      puts
      puts "AI:"
      puts TTY::Markdown.parse(result.fetch(:text))
      puts

      # --------------------------------------------------------
      # Interactive conversation
      # --------------------------------------------------------

      loop do
        print "You: "

        input = STDIN.gets&.chomp

        break if input.nil?
        break if quit_cmds.include?(input)
        if input.strip.empty?
          puts "Please enter a response."
          next
        end

        result = workshop.reply(input)

        print_tool_calls(result)

        puts
        puts "AI:"
        puts TTY::Markdown.parse(result.fetch(:text))
        puts
      rescue Faraday::BadRequestError => e
        puts e.response_body
        raise
      end
    ensure
      workshop.close
    end
  end

  desc "Run the essay workshop prompt"
  task essay_workshop: :prompt_runner

  def print_tool_calls(result)
    result.fetch(:tool_calls).each do |tool_call|
      puts
      puts "MCP TOOL:"
      puts "  #{tool_call.fetch(:name)}"

      puts "  #{tool_call.fetch(
        :arguments
      ).inspect}"

      puts "  Result:"

      puts TTY::Markdown.parse(
        tool_call.fetch(:content)
      )
    end
  end

  def authenticate
    client = Doorkeeper::Application.find_or_initialize_by(
      name: "MCP CLI"
    )

    client.redirect_uri = "http://127.0.0.1:9876/oauth/callback"
    client.scopes = "public"
    client.confidential = false
    client.save!

    authenticator = AI::CLIAuthenticator.new(client_id: client.uid)
    access_token = authenticator.authenticate
  end
end
