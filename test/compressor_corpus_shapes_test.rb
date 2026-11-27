# encoding: UTF-8
require 'test_helper'
require_relative 'support/email_semantics'

module HtmlCompressor
  # Named regressions for markup shapes seen while replaying stored templates
  # from Sweetwater, Optimalprint and LendingTree with BSFT's options. Inputs are
  # synthetic and keep only the structure that affected the replay.
  class TestCompressorCorpusShapes < Minitest::Test
    def read_resource(file)
      File.read(File.join(File.expand_path(File.dirname(__FILE__)), 'resources', 'html', file), :encoding => 'UTF-8')
    end

    def compressor
      @compressor ||= Compressor.new(EmailSemantics::BSFT_OPTIONS)
    end

    def wrap(body, head = '')
      "<!DOCTYPE html><html><head><meta charset=\"utf-8\">#{head}</head><body>#{body}</body></html>"
    end

    def assert_clients_see_the_same(source, context = nil)
      output = compressor.compress(source)
      assert_equal EmailSemantics.of(source), EmailSemantics.of(output)
      if context
        assert_equal EmailSemantics.of(EmailSemantics.render(source, context)),
          EmailSemantics.of(EmailSemantics.render(output, context))
      end
      output
    end

    # --- Liquid inside CSS (send path renders in Liquid's default lax mode) ---

    def test_liquid_tag_after_a_css_block_opener_is_not_merged_into_a_variable_delimiter
      source = wrap('<p>x</p>', "<style>@media (max-width:600px){ {%if offers.size > 20%} .a{color:red} {%endif%} }</style>")
      output = compressor.compress(source)

      refute_includes output, '{{%'
      Liquid::Template.parse(output)
      assert_equal EmailSemantics.render(source, 'offers' => Array.new(25, 1)),
        EmailSemantics.render(output, 'offers' => Array.new(25, 1))
    end

    def test_liquid_comparison_in_css_keeps_the_branch_it_selects
      source = wrap('<p>x</p>', '<style>{% if score > 1 %}.a { color: red }{% else %}.a { color: blue }{% endif %}</style>')
      output = compressor.compress(source)

      [{ 'score' => 5 }, { 'score' => 0 }].each do |context|
        assert_equal EmailSemantics.render(source, context), EmailSemantics.render(output, context)
      end
      assert_includes EmailSemantics.render(output, 'score' => 5), 'color: red'
    end

    def test_liquid_filter_argument_in_css_keeps_its_value
      source = wrap('<p>x</p>', '<style>.h { height: {{ h | times: 0.5 }}px }</style>')

      assert_includes EmailSemantics.render(compressor.compress(source), 'h' => 240), '120.0px'
    end

    def test_liquid_output_as_a_whole_css_declaration_block_stays_parseable
      source = wrap('<p>x</p>', "<style>a {\n{{ css_rule }}\n}</style>")
      output = compressor.compress(source)

      refute_includes output, '{{{'
      assert_equal EmailSemantics.render(source, 'css_rule' => 'color:red'),
        EmailSemantics.render(output, 'css_rule' => 'color:red')
    end

    def test_styles_without_liquid_are_still_minified
      output = compressor.compress(wrap('<p>x</p>', '<style>.a { color : #FFFFFF; margin : 0px }</style>'))

      assert_includes output, '<style>.a{color:#fff;margin:0}</style>'
    end

    # --- Outlook boundaries that HTML5 clients read differently ---

    def test_closed_comment_before_a_stylesheet_keeps_it_applied_outside_outlook
      source = wrap('<!--[if mso]><!-- --><style>.c-r>table{border-collapse:collapse}</style><![endif]--><p class="c-r">x</p>')
      output = assert_clients_see_the_same(source)

      assert_equal 1, EmailSemantics.of(output)[:styles].length
    end

    def test_editor_comment_inside_an_outlook_branch_keeps_product_links_visible
      source = wrap('<!--[if mso | IE]><table role="presentation"><tr><td width="600"><!-- Loop through products -->' \
        "\n{% for p in products %}<a href=\"{{ p.url }}\">{{ p.title }}</a>{% endfor %}</td></tr></table><![endif]-->")
      context = { 'products' => [{ 'url' => 'https://example.com/a', 'title' => 'Mug' }] }
      output = assert_clients_see_the_same(source, context)

      assert_equal ['https://example.com/a'], EmailSemantics.of(EmailSemantics.render(output, context))[:hrefs]
    end

    def test_stray_outlook_closer_without_an_opener_is_harmless
      assert_clients_see_the_same(wrap("<p>Intro</p><![endif]-->\n<p>Body</p>"))
    end

    # --- Links and URLs ---

    def test_block_markup_nested_in_a_link_keeps_the_link
      source = wrap("<table><tr><td>\n  <a href=\"{{ link }}\">\n    <div>\n      <table><tr><td>\n        {{ title }}\n" \
        "      </td></tr></table>\n    </div>\n  </a>\n</td></tr></table>")
      assert_clients_see_the_same(source, 'link' => 'https://example.com/l', 'title' => 'Mug')
    end

    def test_liquid_branch_href_renders_the_same_destination_for_each_branch
      source = wrap("<a href=\"{% if user.score == true %}\n   {{ dest_a }}\n   {% elsif user.score == false %}\n   " \
        "{{ dest_b }}\n   {% else %}\n   https://example.com/signup?id=crm\n   {% endif %}\">Sign up</a>")
      [{ 'user' => { 'score' => true }, 'dest_a' => 'https://example.com/a' },
       { 'user' => { 'score' => false }, 'dest_b' => 'https://example.com/b' }, {}].each do |context|
        assert_clients_see_the_same(source, context)
      end
    end

    def test_multiline_personalized_image_url_keeps_its_bytes
      url = "https://preview.example.com/p?product_uid=cards_hor\n&customer_key={{ key }}&oi={{ item }}"
      output = compressor.compress(wrap("<img src=\"#{url}\" width=\"170\" alt=\"\">"))

      assert_includes output, "src=\"#{url}\""
    end

    # --- Visible text ---

    def test_adjacent_price_spans_keep_their_separator
      source = wrap('<p><span class="old">{{ regular_price }}</span> <span class="new">{{ discounted_price }}</span></p>')
      output = assert_clients_see_the_same(source, 'regular_price' => '$49', 'discounted_price' => '$39')

      assert_includes EmailSemantics.render(output, 'regular_price' => '$49', 'discounted_price' => '$39'), '$49</span> <span'
    end

    def test_product_name_and_quantity_spans_keep_their_separator
      assert_clients_see_the_same(wrap("<p><span>{{ name }}</span>\n <span>Quantity: {{ qty }}</span></p>"),
        'name' => 'Mug', 'qty' => 2)
    end

    # Found by the semantic property test: an Outlook block between two links
    # is invisible to HTML5 clients, so the whitespace around it separates them.
    def test_whitespace_between_an_outlook_block_and_an_inline_link_still_separates_words
      ['<!--[if mso]></td><td><![endif]-->', '<!--[if !mso]><!--><b>x</b><!--<![endif]-->'].each do |block|
        source = wrap("<p><a href=\"https://example.com/1\">One</a>#{block}\n<a href=\"https://example.com/2\">Two</a></p>")
        output = assert_clients_see_the_same(source)

        assert_includes output, "#{block} <a href=\"https://example.com/2\">"
      end
      source = wrap("<p><a href=\"https://example.com/1\">One</a>\r\n\t<!--[if mso]></td><td><![endif]--><a href=\"https://example.com/2\">Two</a></p>")
      assert_includes assert_clients_see_the_same(source), 'One</a> <!--[if mso]>'
    end

    def test_whitespace_between_adjacent_outlook_buttons_still_separates_their_labels
      button = '<!--[if mso]><v:roundrect href="https://example.com/btn"><center>Buy</center></v:roundrect><![endif]-->' \
        '<!--[if !mso]><!--><a href="https://example.com/btn">Buy</a><!--<![endif]-->'
      output = assert_clients_see_the_same(wrap("<p>#{button}\n#{button}</p>"))

      assert_equal %w[Buy Buy], EmailSemantics.of(output)[:words]
    end

    def test_whitespace_between_an_outlook_block_and_a_block_element_is_still_removed
      output = compressor.compress(wrap("<table><tr><td>A</td></tr></table>\n<!--[if mso]><p>o</p><![endif]-->\n<table><tr><td>B</td></tr></table>"))

      assert_includes output, '</table><!--[if mso]><p>o</p><![endif]--><table>'
    end

    def test_footer_links_around_non_breaking_separators_keep_their_text
      assert_clients_see_the_same(wrap('<p><a href="https://example.com/u">Unsubscribe</a> &nbsp;|&nbsp; ' \
        '<a href="https://example.com/p">Preferences</a></p>'))
    end

    # --- Liquid in ordinary HTML comments (Liquid still runs inside them) ---

    def test_commented_capture_that_is_recaptured_before_use_renders_the_same
      source = wrap("<!--\n{% if fetch.url != blank %}{% capture dest_url %}{{ fetch.url }}&{% endcapture %}" \
        "{% else %}{% capture dest_url %}https://example.com/old?{% endcapture %}{% endif %}\n-->" \
        '{% if fetch.url != blank %}{% capture dest_url %}{{ fetch.url }}&{% endcapture %}' \
        '{% else %}{% capture dest_url %}https://example.com/plans?{% endcapture %}{% endif %}' \
        '<a href="{{ dest_url }}utm=crm">Monitor</a>')
      output = compressor.compress(source)

      [{ 'fetch' => { 'url' => 'https://example.com/c' } }, {}].each do |context|
        assert_equal EmailSemantics.of(EmailSemantics.render(source, context)),
          EmailSemantics.of(EmailSemantics.render(output, context))
      end
    end

    def test_liquid_comment_blocks_inside_html_comments_render_nothing_before_and_after
      source = wrap('<!-- {% comment %} splitter notes {% endcomment %} --><p>Body</p>')

      assert_equal EmailSemantics.of(EmailSemantics.render(source, {})),
        EmailSemantics.of(EmailSemantics.render(compressor.compress(source), {}))
    end

    # --- Repository email fixtures through the semantic oracle ---

    def test_email_fixtures_keep_what_clients_see_and_their_rendered_text
      %w[bee_order_confirmation.html classic_product_digest.html].each do |file|
        source = read_resource(file)
        output = compressor.compress(source)

        assert_equal EmailSemantics.of(source), EmailSemantics.of(output), file
        Liquid::Template.parse(output)
      end
    end
  end
end
