require 'test_helper'
require 'cgi'

module HtmlCompressor
  class TestCompressorCommentSafety < Minitest::Test
    def test_literal_style_token_cannot_be_restored_inside_preserved_user_text
      snippet = '<!-- {{{ --><p>%%%~COMPRESS~STYLE~0~%%%</p><!-- }}} -->'
      input = snippet + '<style>.label{color:red}</style>'

      assert_equal input, Compressor.new.compress(input)
    end

    def test_preformatted_copy_keeps_its_layout_when_a_comment_mentions_the_closing_tag
      input = "<pre>first<!-- editor note about </pre> -->  keep\n   me</pre><p>after</p>"

      assert_equal input, Compressor.new.compress(input)
    end

    def test_removing_comment_does_not_create_a_character_reference
      source = '<p>&am<!-- needed seam --><!-- removable -->p; &#x2<!-- numeric seam -->6;</p>'
      output = Compressor.new.compress(source)
      text = CGI.unescapeHTML(output).gsub(/<!--.*?-->/, '')

      refute_includes output, '<!-- removable -->'
      assert_equal '<p>&amp; &#x26;</p>', text
    end

    def test_removing_comment_does_not_turn_visible_text_into_a_tag
      source = '<p>Use <<!-- keep -->b> in your message.</p><!-- remove -->'

      assert_equal '<p>Use <<!-- keep -->b> in your message.</p>', Compressor.new.compress(source)
    end

    def test_nonstandard_comment_ending_does_not_swallow_live_vml_or_css
      comment = '<!-- Note about the <style> and <![if mso]> fallback --!>'
      body = '<!--[if mso]><v:rect>Offer</v:rect><![endif]--><style>.offer { color: red; }</style><p>Offer</p>'

      assert_equal body, Compressor.new.compress(comment + body)
    end

    def test_revealed_outlook_branches_keep_the_comment_that_exposes_their_content
      body = '<a href="/offer">Offer</a><style>.copy { color: red; }</style>'
      ending = '<!--<![endif]-->'
      ['<!-->', '<!---->', '<!-- -->', "\n<!-- \n -->"].each do |marker|
        opener = '<!--[if !mso]>' + marker
        input = opener + body + '<!-- editorial note -->' + ending

        assert_equal opener + body + ending,
          Compressor.new(:remove_intertag_spaces => true).compress(input)
      end
    end

    def test_removing_nested_comment_text_does_not_erase_an_outlook_marker
      marker = "<!-- section label\n<!-- nested label\n<![endif]-->"
      source = marker + '<!-- removable note --><p>Continue</p>'

      assert_equal marker.gsub(/\s+/, ' ') + '<p>Continue</p>', Compressor.new.compress(source)
    end

    def test_unmatched_outlook_opener_keeps_the_first_html_terminator
      opener = '<!--[if (gte mso 9)|(IE)]><table><tr><td>'
      fallback = '<p><a href="/details">Details</a></p>'
      ['-->', '--!>'].each do |ending|
        boundary = "<!-- editorial note #{ending}"
        source = opener + boundary + fallback + '<!-- removable once visible -->'

        assert_equal opener + boundary + fallback, Compressor.new.compress(source)
      end
    end

    def test_keeps_both_fallbacks_visible_when_multiple_assets_leave_unmatched_outlook_openers
      first_asset = '<!--[if mso]><table><tr><td><!-- first asset boundary -->' \
        '<a href="{{ details_url }}" data-bsft-link-index="1">Details</a></td></tr></table>'
      second_asset = '<!--[if (gte mso 9)|(IE)]><table><tr><td><!-- second asset boundary --!>' \
        '<a href="{{ support_url }}" data-bsft-link-index="2">Support</a></td></tr></table>'
      source = first_asset + '<!-- between assets -->' + second_asset + '<!-- end of email -->'
      compressor = Compressor.new(:remove_intertag_spaces => true, :preserve_patterns => TestFixtures::EMAIL_PRESERVE_PATTERNS)

      assert_equal first_asset + second_asset, compressor.compress(source)
    end

    def test_unmatched_revealed_outlook_opener_still_allows_comment_removal
      opener = '<!--[if !mso]><!-- -->'
      fallback = '<p><a href="/details">Details</a></p>'
      source = opener + '<!-- removable note -->' + fallback

      assert_equal opener + fallback, Compressor.new.compress(source)
    end

    def test_restores_a_custom_script_nested_in_a_preserved_style
      source = '<style>.label { color: {{ color }}; } /* ' \
        '<script type="application/ld+json">{"example":" onload=\'preserve me\'"}</script> */</style>'
      compressor = Compressor.new(:compress_css => true, :preserve_patterns => TestFixtures::EMAIL_PRESERVE_PATTERNS)

      assert_equal source, compressor.compress(source)
    end

    def test_restores_skip_directives_nested_in_preformatted_and_conditional_blocks
      skipped = '<!-- {{{ --><code>keep  spacing</code><!-- }}} -->'
      sources = ["<pre>start\n#{skipped}\nend</pre>", "<!--[if mso]>#{skipped}<![endif]-->"]

      sources.each do |source|
        assert_equal source, Compressor.new.compress(source)
      end
    end

    def test_conditional_comments_preserve_the_first_html_end_even_after_nested_markup
      exposed = '<!--[if mso | IE]><table><tr><td><!-- Editorial handoff -->'
      body = '<a href="/details">Details</a><style>.copy { color: red; }</style>'
      ending = '</td></tr></table><![endif]-->'
      source = exposed + body + '<!-- removable once visible -->' + ending

      assert_equal exposed + body + ending, Compressor.new.compress(source)
    end
  end
end
