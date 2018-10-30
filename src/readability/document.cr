module Readability
  class Document
    SAVE_OPTS  = XML::SaveOptions::NO_DECL | XML::SaveOptions::AS_HTML | XML::SaveOptions::NO_EMPTY
    PARSE_OPTS = XML::HTMLParserOptions::NODEFDTD | XML::HTMLParserOptions::NOIMPLIED | XML::HTMLParserOptions::NOBLANKS

    REGEXES = {
      :unlikelyCandidatesRe   => /combx|comment|community|disqus|extra|foot|footer|header|menu|remark|rss|shoutbox|sidebar|sponsor|ad-break|agegate|pagination|pager|popup|search/i,
      :okMaybeItsACandidateRe => /and|article|body|column|main|shadow/i,
      :positiveRe             => /article|body|content|entry|hentry|main|page|pagination|post|text|blog|story/i,
      :negativeRe             => /combx|comment|com-|contact|foot|footer|footnote|masthead|media|meta|outbrain|promo|related|scroll|shoutbox|sidebar|sponsor|shopping|tags|tool|widget/i,
      :divToPElementsRe       => /<(a|blockquote|dl|div|img|ol|p|pre|table|ul)/i,
      :replaceBrsRe           => /(?<content>.*)(<br[^>]*>[ \n\r\t]*){2,}/i,
      :replaceFontsRe         => /<(\/?)font[^>]*>/i,
      :trimRe                 => /^\s+|\s+$/,
      :normalizeRe            => /\s{2,}/,
      :killBreaksRe           => /(<br\s*\/?>(\s|&nbsp;?)*){1,}/,
      :videoRe                => /http:\/\/(www\.)?(youtube|vimeo)\.com/i,
    }

    property :options, :html, :best_candidate_has_image

    @html : XML::Node

    # Transform the css query into an xpath query
    # https://github.com/madeindjs/Crystagiri/blob/master/src/crystagiri/html.cr
    def self.css_query_to_xpath(query : String) : String
      query = "//#{query}"
      # Convert '#id_name' as '[@id="id_name"]'
      query = query.gsub /\#([A-z0-9]+-*_*)+/ { |m| "*[@id=\"%s\"]" % m.delete('#') }
      # Convert '.classname' as '[@class="classname"]'
      query = query.gsub /\.([A-z0-9]+-*_*)+/ { |m| "[@class=\"%s\"]" % m.delete('.') }
      # Convert ' > ' as '/'
      query = query.gsub /\s*>\s*/ { |m| "/" }
      # Convert ' ' as '//'
      query = query.gsub " ", "//"
      # a leading '*' when xpath does not include node name
      query = query.gsub /\/\[/ { |m| "/*[" }
      return query
    end

    def self.html_from_input(input, options = XML::HTMLParserOptions::NODEFDTD)
      html = XML.parse_html(input, options: XML::HTMLParserOptions::NODEFDTD).as(XML::Node)

      # In case document has no body, such as from empty string or redirect
      html = XML.parse_html("<body />") unless html.xpath_node("//body")

      # Remove html comment tags
      html.xpath_nodes("//comment()").each { |i| i.unlink }
      html
    end

    def initialize(@input : String, options = Options.new)
      @input = "<body />" if @input.empty?
      @options = options
      @input = @input.gsub(REGEXES[:replaceBrsRe], "<p>\\k<content></p>").gsub(REGEXES[:replaceFontsRe], "<\1span>").gsub(/\s{2,}/, " ")
      @remove_unlikely_candidates = options.remove_unlikely_candidates
      @weight_classes = options.weight_classes
      @clean_conditionally = options.clean_conditionally
      @best_candidate_has_image = true
      @html = Document.html_from_input(@input)

      handle_exclusions!(options.whitelist, options.blacklist)
    end

    def meta_image
      @html
        .xpath_node("//meta[@name='twitter:image' or @name='twitter:image:src' or @property='twitter:image']")
        .try { |node| node["content"]? }
    end

    # Look through the @html document looking for the author
    # Precedence Information here on the wiki: (TODO: attach wiki URL if it is accepted)
    # Returns nil if no author is detected
    def author
      # Let's grab this author:
      # <meta name="dc.creator" content="Finch - http://www.getfinch.com" />
      author_elements = @html.xpath_nodes("//meta[@name = 'dc.creator']")
      author_elements.each do |element|
        return element["content"].strip if element["content"]
      end

      # Now let's try to grab this
      # <span class="byline author vcard"><span>By</span><cite class="fn">Austin Fonacier</cite></span>
      # <div class="author">By</div><div class="author vcard"><a class="url fn" href="http://austinlivesinyoapp.com/">Austin Fonacier</a></div>
      author_elements = @html.xpath_nodes("//*[contains(@class, 'vcard')]//*[contains(@class, 'fn')]")
      author_elements.each do |element|
        return element.text.strip if element.text
      end

      # Now let's try to grab this
      # <a rel="author" href="http://dbanksdesign.com">Danny Banks (rel)</a>
      # TODO: strip out the (rel)?
      author_elements = @html.xpath_nodes("//a[@rel = 'author']")
      author_elements.each do |element|
        return element.text.strip if element.text
      end

      author_elements = @html.xpath_nodes("//*[@id = 'author']")
      author_elements.each do |element|
        return element.text.strip if element.text
      end
    end

    def handle_exclusions!(whitelist, blacklist)
      return if whitelist.empty? && blacklist.empty?

      blacklist.as(Array).each do |tag|
        css = Document.css_query_to_xpath(tag)
        elems = @html.xpath_nodes(css)
        elems.each &.unlink
      end

      whitelist.as(Array).each do |tag|
        css = Document.css_query_to_xpath(tag)
        elems = @html.xpath_node(css)
        @html = elems if elems
      end
      @input = @html.to_xml(options: SAVE_OPTS)
    end

    def title
      title = @html.xpath_node("//title")
      title ? title.text : nil
    end

    def content(remove_unlikely_candidates = :default)
      @remove_unlikely_candidates = false if remove_unlikely_candidates == false

      prepare_candidates
      candidates = score_paragraphs(options.min_text_length)
      best_candidate = select_best_candidate(candidates)
      article = get_article(candidates, best_candidate)
      cleaned_article = sanitize(article, candidates)
      if article.text.strip.size < options.retry_length
        if @remove_unlikely_candidates
          @remove_unlikely_candidates = false
        elsif @weight_classes
          @weight_classes = false
        elsif @clean_conditionally
          @clean_conditionally = false
        else
          # nothing we can do
          return (options.return_nil_content ? nil : cleaned_article)
        end
        @html = Document.html_from_input(@input, options: PARSE_OPTS)
        content
      else
        cleaned_article
      end
    end

    # This method only touches @html instance variable
    def prepare_candidates
      @html.xpath_nodes("//script|//style").each { |i| i.unlink }
      remove_unlikely_candidates! if @remove_unlikely_candidates
      transform_misused_divs_into_paragraphs!
    end

    def score_paragraphs(min_text_length : Int32) : Hash(XML::Node, Readability::NodeScore)
      candidates = Hash(XML::Node, Readability::NodeScore).new

      @html.xpath_nodes("//p|//td").each do |elem|
        parent_node = elem.parent.not_nil!
        grand_parent_node = parent_node.responds_to?(:parent) ? parent_node.parent : nil
        inner_text = elem.text

        # If this paragraph is less than 25 characters, don"t even count it.
        next if inner_text.size < min_text_length
        if parent_node
          candidates[parent_node] ||= score_node(parent_node.not_nil!)
          candidates[grand_parent_node] ||= score_node(grand_parent_node) if grand_parent_node

          content_score = 1
          content_score += inner_text.split(",").size
          content_score += [(inner_text.size / 100).to_i, 3].min

          candidates[parent_node].score += content_score
          candidates[grand_parent_node].score += content_score / 2.0 if grand_parent_node
        end
      end

      # Scale the final candidates score based on link density. Good content should have a
      # relatively small link density (5% or less) and be mostly unaffected by this operation.
      candidates.each do |elem, candidate|
        candidate.score = candidate.score * (1 - get_link_density(elem))
      end

      candidates
    end

    def select_best_candidate(candidates)
      sorted_candidates = candidates.values.sort { |a, b| b.score <=> a.score }

      best_candidate = sorted_candidates.first? || NodeScore.new(element: @html.xpath_node("//body").not_nil!)
      # best_candidate = sorted_candidates.first? || NodeScore.new(element: @html)
      best_candidate
    end

    def get_article(candidates, best_candidate)
      # Now that we have the top candidate, look through its siblings for content that might also be related.
      # Things like preambles, content split by ads that we removed, etc.

      sibling_score_threshold = [10, best_candidate.score * 0.2].max

      output = "<div>"

      parent = best_candidate.element.parent.not_nil!
      parent.children.each do |sibling|
        append = false
        append = true if sibling == best_candidate.element
        append = true if candidates[sibling]? && candidates[sibling].score >= sibling_score_threshold

        if sibling.name.downcase == "p"
          link_density = get_link_density(sibling)
          node_content = sibling.text
          node_length = node_content.size

          append = if node_length > 80 && link_density < 0.25
                     true
                   elsif node_length < 80 && link_density == 0 && node_content =~ /\.( |$)/
                     true
                   end
        end
        if append
          sibling_dup = sibling.dup # otherwise the state of the document in processing will change, thus creating side effects
          sibling_dup.name = "div" unless %w[div p].includes?(sibling.name.downcase)
          output += sibling_dup.to_xml(options: SAVE_OPTS)
        end
      end
      output = XML.parse_html(output, options: PARSE_OPTS)

      #debug("-"*20 + "OUTPUT" + "-"*20)
      #debug(output.to_xml(options: SAVE_OPTS))

      output
    end

    def get_link_density(elem)
      link_length = elem.xpath_nodes("descendant::node()").flat_map { |el| el.name == "a" ? el.text : "" }.join("").size
      text_length = elem.text.size
      link_length / text_length.to_f
    end

    def class_weight(e)
      weight = 0
      return weight unless @weight_classes

      if e && e["class"]? && e["class"] != ""
        weight -= 25 if e["class"] =~ REGEXES[:negativeRe]
        weight += 25 if e["class"] =~ REGEXES[:positiveRe]
      end

      if e && e["id"]? && e["id"] != ""
        weight -= 25 if e["id"] =~ REGEXES[:negativeRe]
        weight += 25 if e["id"] =~ REGEXES[:positiveRe]
      end

      weight
    end

    ELEMENT_SCORES = {
      "div"        => 5.0,
      "blockquote" => 3.0,
      "form"       => -3.0,
      "th"         => -5.0,
    }

    def score_node(elem)
      content_score = class_weight(elem)
      content_score += ELEMENT_SCORES.fetch(elem.not_nil!.name.downcase, 0.0)
      NodeScore.new(content_score, elem)
    end

    def debug(str)
      p! str if options.debug
    end

    def remove_unlikely_candidates!
      @html.xpath_nodes("//*").each do |elem|
        str = "#{elem["class"]?}#{elem["id"]?}"
        if str =~ REGEXES[:unlikelyCandidatesRe] && str !~ REGEXES[:okMaybeItsACandidateRe] && (elem.name.downcase != "html") && (elem.name.downcase != "body")
          debug("Removing unlikely candidate - #{str}")
          elem.unlink
        end
      end
    end

    def transform_misused_divs_into_paragraphs!
      @html.xpath_nodes("//*").each do |elem|
        if elem.name.downcase == "div" && elem.children.to_s !~ REGEXES[:divToPElementsRe]
          # transform <div>s that do not contain other block elements into <p>s
          debug("Altering div(##{elem["id"]?}.#{elem["class"]?}) to p")
          elem.name = "p"
        end
      end
    end

    def sanitize(node, candidates = {} of Any => Any)
      html = nil
      node.xpath_nodes("//h1|//h2|//h3|//h4|//h5|//h6").each do |header|
        header.unlink if !options.tags.includes?(header.name) && (class_weight(header) < 0 || get_link_density(header) > 0.33)
      end

      node.xpath_nodes("//form|//object|//iframe|//embed").each do |elem|
        elem.unlink
      end

      if options.remove_empty_nodes
        # remove <p> tags that have no text content - this will also remove p tags that contain only images.
        node.xpath_nodes("//p").each do |elem|
          elem.unlink if elem.content.strip.empty?
        end
      end

      # Conditionally clean <table>s, <ul>s, and <div>s
      clean_conditionally(node, candidates, "//table|//ul|//div")

      # We"ll sanitize all elements using a whitelist
      base_whitelist = options.tags || %w[div p]
      # We"ll add whitespace instead of block elements,
      # so a<br>b will have a nice space between them
      base_replace_with_whitespace = %w[br hr h1 h2 h3 h4 h5 h6 dl dd ol li ul address blockquote center]

      # Use a hash for speed (don"t want to make a million calls to includes?)
      whitelist = Hash(String, Bool).new
      base_whitelist.each { |tag| whitelist[tag] = true }
      replace_with_whitespace = Hash(String, Bool).new
      base_replace_with_whitespace.each { |tag| replace_with_whitespace[tag] = true }

      nodes = [node] + node.xpath_nodes("//*").flat_map { |node| node }
      nodes.each do |el|
        # If element is in whitelist, delete all its attributes
        if whitelist[el.name]?
          attrs_to_delete = el.attributes.map(&.name.to_s).select { |attr_name| !options.attributes.includes?(attr_name) }
          attrs_to_delete.each { |attr_name| el.delete(attr_name) }
          # Otherwise, replace the element with its contents
        else
          # If element is root, replace the node as a text node
          if el.parent.nil?
            html = el.text
            break
          else
            if replace_with_whitespace[el.name]?
              # TODO: what to do
              # el.swap(Nokogiri::XML::Text.new(" " << el.text << " ", el.document))
            else
              # el.swap(Nokogiri::XML::Text.new(el.text, el.document))
            end
          end
        end
      end

      html ||= node.to_xml(options: SAVE_OPTS)

      # Get rid of duplicate whitespace
      return html.gsub(/[\r\n\f]+/, "\n").gsub("&nbsp;", " ").strip
    end

    def clean_conditionally(node, candidates, selector)
      return unless @clean_conditionally
      node.xpath_nodes("//#{selector}").each do |el|
        weight = class_weight(el)
        content_score = candidates[el]? ? candidates[el].score : 0
        name = el.name.downcase

        if weight + content_score < 0
          el.unlink
          debug("Conditionally cleaned #{name}##{el["id"]?}.#{el["class"]?} with weight #{weight} and content score #{content_score} because score + content score was less than zero.")
        elsif el.text.count(",") < 10
          counts = %w[p img li a embed input].reduce({} of String => Int32) { |m, kind| m[kind] = el.xpath_nodes("//#{kind}").size; m }
          counts["li"] -= 100

          # For every img under a noscript tag discount one from the count to avoid double counting
          counts["img"] -= el.xpath_nodes("//noscript").reduce(0) { |sum, node| node.xpath_nodes("//img").size }

          content_length = el.text.strip.size # Count the text length excluding any surrounding whitespace
          link_density = get_link_density(el)

          reason = clean_conditionally_reason?(name, counts, content_length, weight, link_density)
          if reason
            debug("Conditionally cleaned #{name}##{el["id"]?}.#{el["class"]?} with weight #{weight} and content score #{content_score} because it has #{reason}.")
            el.unlink
          end
        end
      end
    end

    def clean_conditionally_reason?(name, counts, content_length, weight, link_density)
      if (counts["img"] > counts["p"]) && (counts["img"] > 1)
        "too many images"
      elsif counts["li"] > counts["p"] && name != "ul" && name != "ol"
        "more <li>s than <p>s"
      elsif counts["input"] > (counts["p"] / 3).to_i
        "less than 3x <p>s than <input>s"
      elsif (content_length < options.min_text_length) && (counts["img"] != 1)
        "too short a content length without a single image"
      elsif weight < 25 && link_density > 0.2
        "too many links for its weight (#{weight})"
      elsif weight >= 25 && link_density > 0.5
        "too many links for its weight (#{weight})"
      elsif (counts["embed"] == 1 && content_length < 75) || counts["embed"] > 1
        "<embed>s with too short a content length, or too many <embed>s"
      else
        nil
      end
    end
  end
end
