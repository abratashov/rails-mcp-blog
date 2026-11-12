class ProcessDocumentJob < ApplicationJob
  queue_as :default

  def perform(document)
    Documents::Processor.new(document).call
    GenerateDocumentEmbeddingsJob.perform_later(document.id)
  end
end
