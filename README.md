# readability

[![Build Status](https://travis-ci.org/joenas/readability.cr.svg?branch=master)](https://travis-ci.org/joenas/readability.cr)

Crystal port of @cantino's [port](https://github.com/cantino/ruby-readability) of arc90's readability project

**Still a WIP!**

`document#images` is not implemented. Specs are not passing and some parts of them are probably incorrect...
There's also a monkey patch for `LibXML` while waiting for the changes in https://github.com/crystal-lang/crystal/pull/6910) to be released.

## Installation

Add this to your application's `shard.yml`:

```yaml
dependencies:
  readability:
    github: joenas/readability.cr
    version: 0.2.0
```

## Usage

```crystal
require "readability"
require "http/client"

response = HTTP::Client.get "http://www.example.com"

document = Readability::Document.new(response.body)

puts document.content
puts document.meta_image


# With Options

options = Readability::Options.new(
  tags: %w[article p span div document b strong em h1 h2 h3 h4],
  remove_empty_nodes: true,
  attributes: %w[],
  blacklist: %w[figcaption figure]
)
document = Readability::Document.new(response.body, options)
```

Options
-------

You may provide options to `Readability::Options.new`, including:

* `:retry_length`: how many times to retry getting the best content
* `:min_text_length`: the least number of characters in a paragraph for it to be scored
* `:tags`: the base whitelist of tags to sanitize, defaults to `%w[div p]`;
* `:attributes`: whitelist of allowed attributes for `tags`;
* `:blacklist` and `:whitelist` allow you to explicitly scope to, or remove, CSS selectors.
* `:remove_unlikely_candidates`: whether to remove unlikely candidates or not
* `:weight_classes`: whether to use `weight_classes` or not
* `:clean_conditionally`: whether to use clean conditionally or not
* `:return_nil_content`: if no decent match, return `nil` for `#content`
* `:remove_empty_nodes`: remove `<p>` tags that have no text content; also
  removes `<p>` tags that contain only images;
* `:debug`: provide debugging output, defaults false;

* `:ignore_image_format`: ~~for use with .images.  For example:
  `:ignore_image_format => ["gif", "png"]`;~~
* `:min_image_height`: ~~set a minimum image height for `#images`;~~
* `:min_image_width`: ~~set a minimum image width for `#images`.~~



## Contributing

1. Fork it (<https://github.com/joenas/readability.cr/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

- [joenas](https://github.com/joenas) joenas - creator, maintainer
