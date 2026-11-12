module Retrieval
  Result = Struct.new(
    :content,
    :document_id,
    :filename,
    :page_start,
    :page_end,
    :position,
    :distance,
    :score,
    :metric,
    :provider,
    :model,
    :dimensions,
    :configuration_version,
    :metadata,
    keyword_init: true
  )
end
