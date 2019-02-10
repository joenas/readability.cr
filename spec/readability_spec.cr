# encoding: UTF-8

require "./spec_helper"
require "xml"
require "yaml"

class Fragments
  YAML.mapping(
    required_fragments: Array(String),
    excluded_fragments: Array(String)?,
  )
end

describe Readability do
  simple_html_fixture = <<-HTML
    <html>
      <head>
        <title>title!</title>
      </head>
      <body class="comment">
        <div>
          <p class="comment">a comment</p>
          <div class="comment" id="body">real content</div>
          <div id="contains_blockquote"><blockquote>something in a table</blockquote></div>
        </div>
      </body>
    </html>
  HTML

  simple_html_with_img_no_text = <<-HTML
  <html>
    <head>
      <title>title!</title>
    </head>
    <body class="main">
      <div class="article-img">
        <img src="http://img.thesun.co.uk/multimedia/archive/01416/dim_1416768a.jpg">
      </div>
    </body>
    </html>
  HTML

  simple_html_with_img_in_noscript = <<-HTML
  <html>
    <head>
      <title>title!</title>
    </head>
    <body class="main">
      <div class="article-img">
      <img src="http://img.thesun.co.uk/multimedia/archive/00703/sign_up_emails_682__703711a.gif" width="660"
      height="317" alt="test" class="lazy"
      data-original="http://img.thesun.co.uk/multimedia/archive/01416/dim_1416768a.jpg">
      <noscript><img src="http://img.thesun.co.uk/multimedia/archive/01416/dim_1416768a.jpg"></noscript>
      </div>
    </body>
    </html>
  HTML

  context "transformMisusedDivsIntoParagraphs" do
    it "should transform divs containing no block elements into <p>s" do
      doc = Readability::Document.new(simple_html_fixture)
      doc.transform_misused_divs_into_paragraphs!
      doc.html.xpath_node("//*[@id = 'body']").not_nil!.name.should eq "p"
    end

    it "should not transform divs that contain block elements" do
      doc = Readability::Document.new(simple_html_fixture)
      doc.transform_misused_divs_into_paragraphs!
      doc.html.xpath_node("//*[@id = 'contains_blockquote']").not_nil!.name.should eq "div"
    end
  end

  context "author" do
    it "should pick up <meta name='dc.creator'></meta> as an author" do
      doc = Readability::Document.new(<<-HTML)
        <html>
          <head>
            <meta name="dc.creator" content="Austin Fonacier" />
          </head>
          <body></body>
        </html>
      HTML
      doc.author.should eq("Austin Fonacier")
    end

    it "should pick up readability's recommended author format" do
      doc = Readability::Document.new(<<-HTML)
        <html>
          <head>
          </head>
          <body>
            <p class="byline author vcard">
            By <cite class="fn">Austin Fonacier</span>
            </p>
          </body>
        </html>
      HTML
      doc.author.should eq("Austin Fonacier")
    end

    it "should pick up vcard fn" do
      doc = Readability::Document.new(<<-HTML)
        <html>
          <head>
          </head>
          <body>
            <div class="author">By</div>
            <div class="author vcard">
              <a class="url fn" href="http://austinlivesinyotests.com/">Austin Fonacier</a>
            </div>
          </body>
        </html>
      HTML
      doc.author.should eq("Austin Fonacier")
    end

    it "should pick up <a rel=\"author\">" do
      doc = Readability::Document.new(<<-HTML)
        <html>
          <head></head>
          <body>
            <a rel="author" href="http://google.com">Danny Banks (rel)</a>
          </body>
        </html>
      HTML
      doc.author.should eq("Danny Banks (rel)")
    end

    it "should pick up <div id=\"author\">" do
      doc = Readability::Document.new(<<-HTML)
        <html>
          <head></head>
          <body>
            <div id="author">Austin Fonacier (author)</div>
          </body>
        </html>
      HTML
      doc.author.should eq("Austin Fonacier (author)")
    end
  end

  context "score_node" do
    doc = Readability::Document.new(<<-HTML)
      <html>
        <body>
          <div id="elem1">
            <p>some content</p>
          </div>
          <th id="elem2">
            <p>some other content</p>
          </th>
        </body>
      </html>
    HTML
    elem1 = doc.html.xpath_node("//*[@id = 'elem1']").not_nil!
    elem2 = doc.html.xpath_node("//*[@id = 'elem2']").not_nil!

    it "should like <div>s more than <th>s" do
      doc.score_node(elem1).score.should be > doc.score_node(elem2).score
    end

    it "should like classes like text more than classes like comment" do
      elem2.name = "div"
      doc.score_node(elem1).score.should eq doc.score_node(elem2).score
      elem1["class"] = "text"
      elem2["class"] = "comment"
      doc.score_node(elem1).score.should be > doc.score_node(elem2).score
    end
  end

  context "remove_unlikely_candidates!" do
    doc = Readability::Document.new(simple_html_fixture)
    doc.remove_unlikely_candidates!

    it "should remove things that have class comment" do
      doc.html.content.to_s.should_not match /a comment/
    end

    it "should not remove body tags" do
      doc.html.to_s.should match /<\/body>/
    end

    it "should not remove things with class comment and id body" do
      doc.html.content.to_s.should match /real content/
    end
  end

  context "score_paragraphs" do
    doc = Readability::Document.new(<<-HTML)
      <html>
        <head>
          <title>title!</title>
        </head>
        <body id="body">
          <div id="div1">
            <div id="div2>
              <p id="some_comment">a comment</p>
            </div>
            <p id="some_text">some text</p>
          </div>
          <div id="div3">
            <p id="some_text2">some more text</p>
          </div>
        </body>
      </html><!-- " -->
    HTML
    candidates = doc.score_paragraphs(0)

    it "should score elements in the document" do
      candidates.values.size.should eq 3
    end

    it "should prefer the body in this particular example" do
      candidates.values.sort { |a, b|
        b.score <=> a.score
      }.first.element["id"].should eq "body"
    end

    context "when two consequent br tags are used instead of p" do
      it "should assign the higher score to the first paragraph in this particular example" do
        doc = Readability::Document.new(<<-HTML)
          <html>
            <head>
              <title>title!</title>
            </head>
            <body id="body">
              <div id="post1">
                This is the main content!<br/><br/>
                Zebra found killed butcher with the chainsaw.<br/><br/>
                If only I could think of an example, oh, wait.
              </div>
              <div id="post2">
                This is not the content and although it"s longer if you meaure it in characters,
                it"s supposed to have lower score than the previous paragraph. And it"s only because
                of the previous paragraph is not one paragraph, it"s three subparagraphs
              </div>
            </body>
          </html>
        HTML
        candidates = doc.score_paragraphs(0)
        candidates.values.sort_by { |a| -a.score }.first.element["id"].should eq "post1"
      end
    end
  end

  context "the cant_read.html fixture" do
    it "should work on the cant_read.html fixture with some allowed tags" do
      allowed_tags = %w[div span table tr td p i strong u h1 h2 h3 h4 pre code br a]
      allowed_attributes = %w[href]
      html = File.read(File.dirname(__FILE__) + "/fixtures/cant_read.html")
      options = Readability::Options.new(tags: allowed_tags, attributes: allowed_attributes)
      Readability::Document.new(html, options).content.to_s.should match(/Can you talk a little about how you developed the looks for the/)
    end
  end

  context "general functionality" do
    options = Readability::Options.new(min_text_length: 0, retry_length: 1)
    doc = Readability::Document.new("<html><head><title>title!</title></head><body><div><p>Some content</p></div></body>", options)

    it "should return the main page content" do
      doc.content.to_s.should contain("Some content")
    end

    it "should return the page title if present" do
      doc.title.should eq("title!")

      options = Readability::Options.new(min_text_length: 0, retry_length: 1)
      doc = Readability::Document.new("<html><head></head><body><div><p>Some content</p></div></body>", options)
      doc.title.should be_nil
    end
  end

  context "ignoring sidebars" do
    options = Readability::Options.new(min_text_length: 0, retry_length: 1)
    doc = Readability::Document.new("<html><head><title>title!</title></head><body><div><p>Some content</p></div><div class=\"sidebar\"><p>sidebar<p></div></body>",
      options)

    it "should not return the sidebar" do
      doc.content.to_s.should_not match("sidebar")
    end
  end

  context "inserting space for block elements" do
    html = <<-HTML
      <html><head><title>title!</title></head>
        <body>
          <div>
            <p>a<br>b<hr>c<address>d</address>f/p>
          </div>
        </body>
      </html>
    HTML
    options = Readability::Options.new(min_text_length: 0, retry_length: 1)
    doc = Readability::Document.new(html, options)

    it "should not return the sidebar" do
      doc.content.to_s.should_not match("a b c d f")
    end
  end

  context "outputs good stuff for known documents" do
    html_files = Dir.glob(File.dirname(__FILE__) + "/fixtures/samples/*.html")
    samples = html_files.map { |filename| File.basename(filename, ".html") }

    it "should output expected fragments of text" do
      checks = 0
      samples.each do |sample|
        html = File.read(File.dirname(__FILE__) + "/fixtures/samples/#{sample}.html")
        doc = Readability::Document.new(html).content.not_nil!
        yaml = File.read(File.dirname(__FILE__) + "/fixtures/samples/#{sample}-fragments.yml")
        data = Fragments.from_yaml(yaml)
        # puts "testing #{sample}..."

        data.required_fragments.each do |required_text|
          doc.should contain(required_text)
          checks += 1
        end
        next unless data.excluded_fragments
        data.excluded_fragments.not_nil!.each do |text_to_avoid|
          doc.should_not contain(text_to_avoid)
          checks += 1
        end
      end
      # puts "Performed #{checks} checks."
    end
  end

  pending "encoding guessing" do
    if RUBY_VERSION =~ /^1\.9\./
      context "with ruby 1.9.2" do
        it "should correctly guess and enforce HTML encoding" do
          doc = Readability::Document.new("<html><head><meta http-equiv=\"content-type\" content=\"text/html; charset=LATIN1\"></head><body><div>hi!</div></body></html>")
          content = doc.content
          content.encoding.to_s.should eq "ISO-8859-1"
          content.to_s.should be_valid_encoding
        end

        it "should allow encoding guessing to be skipped" do
          do_not_allow(GuessHtmlEncoding).encode
          doc = Readability::Document.new(simple_html_fixture)
          doc.content
        end

        it "should allow encoding guessing to be overridden" do
          do_not_allow(GuessHtmlEncoding).encode
          doc = Readability::Document.new(simple_html_fixture, encoding: "UTF-8")
          doc.content
        end
      end
    end
  end

  context "#make_html" do
    it "should strip the html comments tag" do
      doc = Readability::Document.new("<html><head><meta http-equiv=\"content-type\" content=\"text/html; charset=LATIN1\"></head><body><div>hi!<!-- bye~ --></div></body></html>")
      content = doc.content
      content.to_s.should contain("hi!")
      content.to_s.should_not contain("bye")
    end

    # "<body></body>\n" makes no sense?
    it "should not error with empty content" do
      Readability::Document.new("").content.to_s.should eq ""
    end

    it "should not error with a document with no <body>" do
      Readability::Document.new("<html><head><meta http-equiv=\"refresh\" content=\"0;URL=http://example.com\"></head></html>").content.to_s.should eq ""
    end
  end

  context "No side-effects" do
    bbc = File.read(File.dirname(__FILE__) + "/fixtures/bbc.html")
    nytimes = File.read(File.dirname(__FILE__) + "/fixtures/nytimes.html")
    thesum = File.read(File.dirname(__FILE__) + "/fixtures/thesun.html")

    it "should not have any side-effects when calling content() and then images()" do
      options = Readability::Options.new(tags: %w[div p img a], attributes: %w[src href], remove_empty_nodes: false)
      doc = Readability::Document.new(nytimes, options)
      # doc.images.should eq ["http://graphics8.nytimes.com/images/2011/12/02/opinion/02fixes-freelancersunion/02fixes-freelancersunion-blog427.jpg"]
      doc.content
      # doc.images.should eq ["http://graphics8.nytimes.com/images/2011/12/02/opinion/02fixes-freelancersunion/02fixes-freelancersunion-blog427.jpg"]
    end

    it "should not have any side-effects when calling content() multiple times" do
      options = Readability::Options.new(tags: %w[div p img a], attributes: %w[src href], remove_empty_nodes: false)
      doc = Readability::Document.new(nytimes, options)
      doc.content.to_s.should eq doc.content
    end

    it "should not have any side-effects when calling content and images multiple times" do
      options = Readability::Options.new(tags: %w[div p img a], attributes: %w[src href], remove_empty_nodes: false)
      doc = Readability::Document.new(nytimes, options)
      # doc.images.should eq ["http://graphics8.nytimes.com/images/2011/12/02/opinion/02fixes-freelancersunion/02fixes-freelancersunion-blog427.jpg"]
      doc.content.to_s.should eq doc.content
      # doc.images.should eq ["http://graphics8.nytimes.com/images/2011/12/02/opinion/02fixes-freelancersunion/02fixes-freelancersunion-blog427.jpg"]
    end
  end

  context "Code blocks" do
    code = File.read(File.dirname(__FILE__) + "/fixtures/code.html")
    options = Readability::Options.new(tags: %w[div p img a ul ol li h1 h2 h3 h4 h5 h6 blockquote strong em b code pre],
      attributes: %w[src href],
      remove_empty_nodes: false)
    content = Readability::Document.new(code, options).content
    doc = XML.parse(content.to_s)

    it "preserve the code blocks" do
      doc.xpath_node("//code/pre").try &.text.should eq "\nroot\n  indented\n    "
    end

    it "preserve backwards code blocks" do
      doc.xpath_node("//code/pre").try &.text.should eq "\nroot\n  indented\n    "
    end
  end

  context "remove all tags" do
    options = Readability::Options.new(tags: [] of String)

    it "should work for an incomplete piece of HTML" do
      doc = Readability::Document.new("<div>test</div", options)
      doc.content.to_s.should eq "test"
    end

    it "should work for a HTML document" do
      doc = Readability::Document.new("<html><head><title>title!</title></head><body><div><p>test</p></div></body></html>",
        options)
      doc.content.to_s.should eq "test"
    end

    it "should work for a plain text" do
      doc = Readability::Document.new("test", options)
      doc.content.to_s.should eq "test"
    end
  end

  context "boing boing" do
    boing_boing = File.read(File.dirname(__FILE__) + "/fixtures/boing_boing.html")

    # crystal author: I don't understand this spec :/
    pending "contains incorrect data by default" do
      # NOTE: in an ideal world this spec starts failing
      #  and readability correctly detects content for the
      #  boing boing sample.

      doc = Readability::Document.new(boing_boing)

      content = doc.content
      (content !~ /Bees and Bombs/).should eq true
      content.to_s.should match /ADVERTISE/
    end

    it "should apply whitelist" do
      options = Readability::Options.new(whitelist: [".post-content"])
      doc = Readability::Document.new(boing_boing, options)
      content = doc.content
      content.to_s.should match /Bees and Bombs/
      content.to_s.should match /No idea who made this, but it's wonderful/
    end

    it "should apply blacklist" do
      options = Readability::Options.new(blacklist: ["#sidebar_adblock"])
      doc = Readability::Document.new(boing_boing, options)
      content = doc.content
      (content !~ /ADVERTISE AT BOING BOING/).should eq true
    end
  end

  context "clean_conditionally_reason?" do
    list_fixture = "<div><p>test</p>#{"<li></li>" * 102}"

    it "does not raise error" do
      doc = Readability::Document.new(list_fixture)
      doc.content # .should_not expect_raises
    end
  end

  # pending "images" do
  #   Spec.before_each do
  #     bbc      = File.read(File.dirname(__FILE__) + "/fixtures/bbc.html")
  #     nytimes  = File.read(File.dirname(__FILE__) + "/fixtures/nytimes.html")
  #     thesum   = File.read(File.dirname(__FILE__) + "/fixtures/thesun.html")
  #     @ch       = File.read(File.dirname(__FILE__) + "/fixtures/codinghorror.html")

  #     WebMock.stub(:get, "http://img.thesun.co.uk/multimedia/archive/01416/dim_1416768a.jpg",
  #                          body: File.read(File.dirname(__FILE__) + "/fixtures/images/dim_1416768a.jpg"))

  #     WebMock.stub(:get, "http://img.thesun.co.uk/multimedia/archive/00703/sign_up_emails_682__703711a.gif",
  #                          body: File.read(File.dirname(__FILE__) + "/fixtures/images/sign_up_emails_682__703711a.gif"))

  #     WebMock.stub(:get, "http://img.thesun.co.uk/multimedia/archive/00703/sign_up_emails_682__703712a.gif",
  #                          body: File.read(File.dirname(__FILE__) + "/fixtures/images/sign_up_emails_682__703712a.gif"))

  #     # Register images for codinghorror
  #     WebMock.stub(:get, "http://blog.codinghorror.com/content/images/2014/Sep/JohnPinhole.jpg",
  #                          body: File.read(File.dirname(__FILE__) + "/fixtures/images/JohnPinhole.jpg"))
  #     WebMock.stub(:get, "http://blog.codinghorror.com/content/images/2014/Sep/Confusion_of_Tongues.png",
  #                          body: File.read(File.dirname(__FILE__) + "/fixtures/images/Confusion_of_Tongues.png"))
  #   end

  #   it "should show one image, but outside of the best candidate" do
  #     it
  #     doc = Readability::Document.new(thesum)
  #     doc.images.should eq ["http://img.thesun.co.uk/multimedia/archive/01416/dim_1416768a.jpg", "http://img.thesun.co.uk/multimedia/archive/00703/sign_up_emails_682__703711a.gif", "http://img.thesun.co.uk/multimedia/archive/00703/sign_up_emails_682__703712a.gif"]
  #     doc.best_candidate_has_image.should eq false
  #   end

  #   it "should show one image inside of the best candidate" do
  #     doc = Readability::Document.new(nytimes)
  #     doc.images.should eq ["http://graphics8.nytimes.com/images/2011/12/02/opinion/02fixes-freelancersunion/02fixes-freelancersunion-blog427.jpg"]
  #     doc.best_candidate_has_image.should eq true
  #   end

  #   it "should expand relative image url" do
  #     url = "http://blog.codinghorror.com/standard-flavored-markdown/"
  #     doc = Readability::Document.new(@ch, tags: %w[div p img a],
  #                                           attributes: %w[src href],
  #                                           remove_empty_nodes: false)
  #     doc.images_with_fqdn_uris!(url)

  #     doc.content.to_s.should contain("http://blog.codinghorror.com/content/images/2014/Sep/JohnPinhole.jpg")
  #     doc.content.to_s.should contain("http://blog.codinghorror.com/content/images/2014/Sep/Confusion_of_Tongues.png")

  #     expect(doc.images).to match_array([
  #       "http://blog.codinghorror.com/content/images/2014/Sep/JohnPinhole.jpg",
  #       "http://blog.codinghorror.com/content/images/2014/Sep/Confusion_of_Tongues.png"
  #     ])
  #   end

  #   it "should not try to download local images" do
  #     doc = Readability::Document.new(<<-HTML)
  #       <html>
  #         <head>
  #           <title>title!</title>
  #         </head>
  #         <body class="comment">
  #           <div>
  #             <img src="/something/local.gif" />
  #           </div>
  #         </body>
  #       </html>
  #     HTML
  #     do_not_allow(doc).load_image(anything)
  #     #doc.images.should eq []
  #   end

  #   pending "no images" do
  #     it "shouldn't show images" do
  #       doc = Readability::Document.new(bbc, min_image_height: 600)
  #       #doc.images.should eq []
  #       doc.best_candidate_has_image.should eq false
  #     end
  #   end

  #   pending "poll of images" do
  #     pending
  #     it "should show some images inside of the best candidate" do
  #       doc = Readability::Document.new(bbc)
  #       doc.images.should =~ ["http://news.bbcimg.co.uk/media/images/57027000/jpg/_57027794_perseus_getty.jpg",
  #                              "http://news.bbcimg.co.uk/media/images/57027000/jpg/_57027786_john_capes229_rnsm.jpg",
  #                              "http://news.bbcimg.co.uk/media/images/57060000/gif/_57060487_sub_escapes304x416.gif",
  #                              "http://news.bbcimg.co.uk/media/images/57055000/jpg/_57055063_perseus_thoctarides.jpg"]
  #       doc.best_candidate_has_image.should eq true
  #     end

  #     it "should show some images inside of the best candidate, include gif format" do
  #       doc = Readability::Document.new(bbc, ignore_image_format: [])
  #       doc.images.should eq ["http://news.bbcimg.co.uk/media/images/57027000/jpg/_57027794_perseus_getty.jpg", "http://news.bbcimg.co.uk/media/images/57027000/jpg/_57027786_john_capes229_rnsm.jpg", "http://news.bbcimg.co.uk/media/images/57060000/gif/_57060487_sub_escapes304x416.gif", "http://news.bbcimg.co.uk/media/images/57055000/jpg/_57055063_perseus_thoctarides.jpg"]
  #       doc.best_candidate_has_image.should eq true
  #     end

  #     pending "width, height and format" do
  #       it "should show some images inside of the best candidate, but with width most equal to 400px" do
  #         doc = Readability::Document.new(bbc, min_image_width: 400, ignore_image_format: [])
  #         doc.images.should eq ["http://news.bbcimg.co.uk/media/images/57027000/jpg/_57027794_perseus_getty.jpg"]
  #         doc.best_candidate_has_image.should eq true
  #       end

  #       it "should show some images inside of the best candidate, but with width most equal to 304px" do
  #         doc = Readability::Document.new(bbc, min_image_width: 304, ignore_image_format: [])
  #         doc.images.should eq ["http://news.bbcimg.co.uk/media/images/57027000/jpg/_57027794_perseus_getty.jpg", "http://news.bbcimg.co.uk/media/images/57060000/gif/_57060487_sub_escapes304x416.gif", "http://news.bbcimg.co.uk/media/images/57055000/jpg/_57055063_perseus_thoctarides.jpg"]
  #         doc.best_candidate_has_image.should eq true
  #       end

  #       it "should show some images inside of the best candidate, but with width most equal to 304px and ignoring JPG format" do
  #         doc = Readability::Document.new(bbc, min_image_width: 304, ignore_image_format: ["jpg"])
  #         doc.images.should eq ["http://news.bbcimg.co.uk/media/images/57060000/gif/_57060487_sub_escapes304x416.gif"]
  #         doc.best_candidate_has_image.should eq true
  #       end

  #       it "should show some images inside of the best candidate, but with height most equal to 400px, no ignoring no format" do
  #         doc = Readability::Document.new(bbc, min_image_height: 400, ignore_image_format: [])
  #         doc.images.should eq ["http://news.bbcimg.co.uk/media/images/57060000/gif/_57060487_sub_escapes304x416.gif"]
  #         doc.best_candidate_has_image.should eq true
  #       end

  #       it "should not miss an image if it exists by itself in a div without text" do
  #         doc = Readability::Document.new(simple_html_with_img_no_text,tags: %w[div p img a], attributes: %w[src href], remove_empty_nodes: false)
  #         doc.images.should eq ["http://img.thesun.co.uk/multimedia/archive/01416/dim_1416768a.jpg"]
  #       end

  #       it "should not double count an image between script and noscript" do
  #         doc = Readability::Document.new(simple_html_with_img_in_noscript,tags: %w[div p img a], attributes: %w[src href], remove_empty_nodes: false)
  #         doc.images.should eq ["http://img.thesun.co.uk/multimedia/archive/00703/sign_up_emails_682__703711a.gif", "http://img.thesun.co.uk/multimedia/archive/01416/dim_1416768a.jpg"]
  #       end

  #     end
  #   end
  # end
end
