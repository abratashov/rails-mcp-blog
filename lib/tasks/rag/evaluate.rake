namespace :rag do
  desc "Evaluate RAG against the fixed YAML evaluation datasets"
  task :evaluate, [ :dataset ] => :environment do |_task, args|
    user = if ENV["RAG_EVALUATION_USER_ID"].present?
      User.find(ENV.fetch("RAG_EVALUATION_USER_ID"))
    elsif ENV["RAG_EVALUATION_USER_EMAIL"].present?
      User.find_by!(email: ENV.fetch("RAG_EVALUATION_USER_EMAIL"))
    else
      raise "Set RAG_EVALUATION_USER_ID or RAG_EVALUATION_USER_EMAIL to scope evaluation to a user's documents"
    end

    document = Rag::Evaluation::ReferenceDocument.new(user: user).call
    runs = Rag::Evaluation::Runner.new.call(
      user: user,
      dataset_name: args[:dataset],
      document_id: document.id
    )
    puts Rag::Evaluation::Report.new.render(runs)
  end
end
