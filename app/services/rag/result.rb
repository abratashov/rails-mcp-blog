module Rag
  Result = Struct.new(
    :answer,
    :sources,
    :citations,
    :retrieved_chunks,
    :context,
    :prompt,
    :grounded,
    :metadata,
    :provider,
    :model,
    :error,
    :timings,
    :token_usage,
    keyword_init: true
  )
end
