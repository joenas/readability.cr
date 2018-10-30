module Readability
  struct Options
    getter retry_length,
      min_text_length,
      tags,
      attributes,
      blacklist,
      whitelist,
      remove_unlikely_candidates,
      weight_classes,
      clean_conditionally,
      return_nil_content,
      remove_empty_nodes,
      min_image_width,
      min_image_height,
      ignore_image_format,
      debug

    def initialize(
      @retry_length = 250,
      @min_text_length = 25,
      @tags = [] of String,
      @attributes = [] of String,
      @blacklist = [] of String,
      @whitelist = [] of String,
      @remove_unlikely_candidates = true,
      @weight_classes = true,
      @clean_conditionally = true,
      @return_nil_content = false,
      @remove_empty_nodes = true,
      @min_image_width = 130,
      @min_image_height = 80,
      @ignore_image_format = [] of String,
      @debug = false
    )
    end
  end
end
