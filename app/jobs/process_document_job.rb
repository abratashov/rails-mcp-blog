class ProcessDocumentJob < ApplicationJob
  queue_as :default

  def perform(document)
    Documents::Processor.new(document).call
  end
end
