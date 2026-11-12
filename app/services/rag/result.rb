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
    keyword_init: true
  )
end
