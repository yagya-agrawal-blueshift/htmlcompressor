# encoding: UTF-8
require 'test_helper'

module HtmlCompressor
  class TestCompressorCompatibility < Minitest::Test
    def test_revealed_outlook_branch_contains_an_ordinary_comment_with_a_fake_opener
      open = '<!--[if !mso]><!-->'
      before = '<a href="{{ product.url }}" data-bsft-link-index="1">See offer</a>'
      after = '{% if available %}<p>In stock</p>{% endif %}'
      close = '<!--<![endif]-->'
      comment = '<!-- Example <![if mso]> syntax -->'

      assert_equal open + before + after + close,
        email_compressor.compress(open + before + comment + after + close)
    end

    def test_adjacent_revealed_and_hidden_outlook_branches_keep_matching_wrappers
      hidden = '<!--[if gte mso 9]><v:rect style="width:400px"><v:fill color="#fff" /></v:rect><![endif]-->'
      revealed = '<!--[if !mso]><!--><a href="{{ promo_url }}">Shop</a><!--<![endif]-->'
      fallback = '<!--[if lt mso 9]><p>Plain fallback</p><![endif]-->'
      input = "<!-- Outside -->#{hidden}<!-- Between -->#{revealed}#{fallback}<!-- End -->"

      expected_hidden = '<!--[if gte mso 9]><v:rect style="width:400px"><v:fill color="#fff"/></v:rect><![endif]-->'

      assert_equal expected_hidden + revealed + fallback + '<!-- End -->',
        email_compressor.compress(input)
    end

    def test_partial_revealed_branch_with_bee_end_marker
      input = '<!--[if !mso]><!--><p>First<!-- Extra editor note --></p><!-- End -->'
      expected = '<!--[if !mso]><!--><p>First</p><!-- End -->'

      assert_equal expected, email_compressor.compress(input)
    end

    def test_literal_comment_start_in_javascript_does_not_consume_html_after_script
      script = '<script>var sample = "<!-- <style>";</script>'
      following_html = '<p>Body</p><style>.x{color:red}</style>'

      assert_equal script + following_html,
        Compressor.new.compress(script + '<p>Body</p><!-- note --><style>.x{color:red}</style>')
    end

    def test_literal_comment_start_in_css_does_not_consume_following_markup
      style = '<style>.label::before { content: "<!-- <pre>"; }</style>'
      following_html = '<p>Body</p><pre>  text  </pre>'

      assert_equal style + following_html,
        Compressor.new.compress(style + '<p>Body</p><!-- note --><pre>  text  </pre>')
    end

    def test_literal_comment_start_in_textarea_cannot_consume_a_later_comment
      textarea = '<textarea>Text that says <!-- <style> without a close</textarea>'
      following_html = '<p>After</p><style>.label{color:red}</style>'

      assert_equal textarea + following_html,
        Compressor.new.compress(textarea + '<p>After</p><!-- note --><style>.label{color:red}</style>')
      assert_equal textarea + following_html,
        Compressor.new.compress(textarea + following_html)
    end

    def test_literal_comment_placeholder_is_not_restored_as_a_comment
      authored = '<p>%%%~COMPRESS~COMMENT~0~%%%</p>'
      real_style = '<style>.label{color:red}</style>'

      assert_equal authored + real_style,
        Compressor.new.compress(authored + '<!-- Example <style> -->' + real_style)
    end

    def test_case_insensitive_raw_element_preserves_original_tag_and_body_bytes
      input = "<TEXTAREA data-mode=\"copy\"> a\r\n  Café &amp; thé </TEXTAREA>" \
        "<PRE title=\"example\"> \t<span>  fixed  </span>\n</PRE>"

      assert_equal input, Compressor.new.compress(input)
    end

    def test_adjacent_empty_and_documentation_comments_do_not_drop_surrounding_content
      input = '<p>Before</p><!----><!-- Notes about <pre> with no matching tag -->' \
        '<!-- More notes --><!----><p>After</p>'

      assert_equal '<p>Before</p><p>After</p>', Compressor.new.compress(input)
    end

    def test_restoration_keeps_repeated_blocks_and_double_and_triple_digit_indices_in_order
      blocks = (0..125).map do |index|
        "<pre>  #{index}\t preserved  </pre><textarea>  repeat  </textarea>"
      end
      input = blocks.join('<!-- spacer -->')

      assert_equal blocks.join, Compressor.new.compress(input)
    end

    def test_intertag_minification_keeps_the_space_between_inline_elements
      input = '<b>Blue</b>  <!-- marker -->  <em>shoes</em>'

      assert_equal '<b>Blue</b> <em>shoes</em>', Compressor.new.compress(input)
      assert_equal '<b>Blue</b> <em>shoes</em>',
        Compressor.new(:remove_intertag_spaces => true).compress(input)
    end

    def test_intertag_minification_keeps_spacing_inside_a_link_and_around_inline_images
      source = '<div> <a href="/offer"><span>Blue</span> </a>shoes <img src="badge.png"> <strong>Sale</strong> </div>'
      expected = '<div><a href="/offer"><span>Blue</span> </a>shoes <img src="badge.png"> <strong>Sale</strong></div>'

      assert_equal expected, Compressor.new(:remove_intertag_spaces => true).compress(source)
    end

    def test_intertag_minification_keeps_a_separator_inside_nested_inline_wrappers
      source = '<p><span>{{ first }}</span><span><a href="/offer"> <u>{{ second }}</u></a></span></p>'

      assert_equal source, email_compressor(:remove_intertag_spaces => true).compress(source)
    end

    def test_css_compression_leaves_styles_with_preserved_template_expressions_intact
      compiler = RecordingCompiler.new('unexpected')
      dynamic = '.header { height: {{ height | times: 0.5 }}px; }'
      source = "<style>#{dynamic}</style><style>.static { width: 20px; }</style>"

      assert_equal "<style>#{dynamic}</style><style>unexpected</style>",
        email_compressor(:compress_css => true, :css_compressor => compiler).compress(source)
      assert_equal ['.static { width: 20px; }'], compiler.inputs
    end

    def test_css_compression_restores_utf8_bytes_returned_as_binary_or_us_ascii
      css = '.copy::before{content:"Café"}'
      source = '<p>Crème</p><style>.copy::before { content: "Café"; }</style>'
      expected = "<p>Crème</p><style>#{css}</style>"

      [Encoding::BINARY, Encoding::US_ASCII].each do |encoding|
        output = css.dup.force_encoding(encoding).freeze
        compiler = RecordingCompiler.new(output)
        compressor = Compressor.new(:compress_css => true, :css_compressor => compiler)

        assert_equal expected, compressor.compress(source)
      end
    end

    def test_css_compression_keeps_original_style_when_the_compiler_returns_invalid_bytes
      source = '<p>Crème</p><style><![CDATA[.copy { color: blue; }]]></style>'

      [Encoding::BINARY, Encoding::US_ASCII].each do |encoding|
        output = [0xff].pack('C').force_encoding(encoding).freeze
        compiler = RecordingCompiler.new(output)
        compressor = Compressor.new(:compress_css => true, :css_compressor => compiler)

        assert_equal source, compressor.compress(source)
      end
    end

    def test_non_breaking_space_and_character_reference_spelling_survive
      input = '<a href="https://example.com/?color=blue&amp;size=m">Crème brûlée  &nbsp; &#160;</a>'
      expected = '<a href="https://example.com/?color=blue&amp;size=m">Crème brûlée &nbsp; &#160;</a>'

      assert_equal expected, Compressor.new.compress(input)
    end

    def test_link_indices_ampersands_and_liquid_values_survive_attribute_minification
      input = '<a   href = "https://example.com/?q={{ query | url_encode }}&amp;v=1" ' \
        'data-bsft-link-index = "42" rel="external">Open</a>'
      expected = '<a href="https://example.com/?q={{ query | url_encode }}&amp;v=1" ' \
        'data-bsft-link-index=42 rel=external>Open</a>'

      assert_equal expected, email_compressor(:remove_quotes => true).compress(input)
    end

    def test_adjacent_liquid_segments_keep_their_rendered_text_separators
      input = '<p>{% if title %} {{ title }} {% endif %} {{ suffix }}</p>'

      assert_equal input, email_compressor(:remove_intertag_spaces => true).compress(input)
    end

    def test_skip_block_can_hold_nested_templates_and_conditional_markup_verbatim
      excluded = '<!-- {{{ --><script type="text/html">  <p>{{ phrase }}</p>  </script>' \
        '<!--[if mso]><span>  keep  </span><![endif]--><!-- }}} -->'
      normal = '<!-- ordinary note --><div>  normal   text  </div>'

      assert_equal excluded + '<div> normal text </div>',
        email_compressor.compress(excluded + normal)
    end

    def test_custom_patterns_can_keep_ssi_and_server_code_while_removing_ordinary_comments
      fragment = '<!--#include file="space  here.html" --><%  render fragment  %>'
      options = {
        :preserve_patterns => [Compressor::SERVER_SIDE_INCLUDE_PATTERN, Compressor::SERVER_SCRIPT_TAG_PATTERN]
      }

      assert_equal fragment + '<p>Next</p>',
        Compressor.new(options).compress(fragment + '<!-- note --><p>Next</p>')
    end

    def test_later_custom_preservation_pattern_restores_nested_liquid_tokens
      include_header = '<!--#include file="{{ locale }}/header.html" -->'
      include_footer = '<!--#include file="{{ brand }}/footer.html" -->'
      body = '<p>{{ greeting }}</p>'
      options = { :preserve_patterns => [/\{\{.*?\}\}/m, Compressor::SERVER_SIDE_INCLUDE_PATTERN] }
      source = include_header + '<!-- removable note -->' + body + include_footer

      assert_equal include_header + body + include_footer, Compressor.new(options).compress(source)
    end

    def test_data_scripts_stay_opaque_when_html_template_compression_is_enabled
      data = '<script type="application/ld+json">{"name":"Two  spaces","count":2}</script>'
      script_template = '<script type="text/html"><p>Item</p><!-- Note --><p> Next  </p></script>'
      expected = '<script type="text/html"><p>Item</p><p> Next </p></script>'
      compressor = Compressor.new(:compress_js_templates => ['text/html'])

      assert_equal data + expected, compressor.compress(data + script_template)
    end

    def test_javascript_compiler_receives_only_executable_script_bodies
      compiler = RecordingCompiler.new('console.log(1);')
      script = '<script type="text/javascript"> console.log( 1 ); </script>'
      json = '<script type="application/json">{"text":"unmodified  data"}</script>'
      template = '<script type="text/html"><p> unmodified  template </p></script>'
      compressor = Compressor.new(:compress_javascript => true, :javascript_compressor => compiler)

      assert_equal json + '<script type="text/javascript">console.log(1);</script>' + template,
        compressor.compress(json + script + template)
      assert_equal [' console.log( 1 ); '], compiler.inputs
    end

    def test_css_compiler_consumes_cdata_payload_and_preserves_the_wrapper
      compiler = RecordingCompiler.new('.label{color:red}')
      input = "<style><![CDATA[\n.label { color: red; }\n]]></style><!-- editorial --><p>Content</p>"
      compressor = Compressor.new(:compress_css => true, :css_compressor => compiler)

      assert_equal '<style><![CDATA[.label{color:red}]]></style><p>Content</p>', compressor.compress(input)
      assert_equal ["\n.label { color: red; }\n"], compiler.inputs
    end

    def test_javascript_compiler_consumes_cdata_payload_and_restores_the_script_wrapper
      compiler = RecordingCompiler.new('show(1);')
      input = "<script><![CDATA[\nshow( 1 );\n]]></script><p>After</p>"
      compressor = Compressor.new(:compress_javascript => true, :javascript_compressor => compiler)

      assert_equal '<script>/*<![CDATA[*/show(1);/*]]>*/</script><p>After</p>', compressor.compress(input)
      assert_equal ["\nshow( 1 );\n"], compiler.inputs
    end

    def test_compiler_failure_is_raised_without_modifying_input_or_poisoning_the_instance
      input = '<style>.label { color: red; }</style>'.freeze
      compiler = RecordingCompiler.new('.label{color:red}')
      compiler.fail = true
      compressor = Compressor.new(:compress_css => true, :css_compressor => compiler)

      assert_raises(ArgumentError) { compressor.compress(input) }
      assert_equal '<style>.label { color: red; }</style>', input
      compiler.fail = false
      assert_equal '<style>.label{color:red}</style>', compressor.compress(input)
    end

    def test_disabled_compression_preserves_frozen_html_and_does_not_call_css_compiler
      input = "<!-- editorial -->\r\n<style>.label { color: red; }</style>\n".freeze
      compiler = RecordingCompiler.new('')
      options = { :enabled => false, :compress_css => true, :css_compressor => compiler }

      assert_equal input, Compressor.new(options).compress(input)
      assert_empty compiler.inputs
      assert_nil Compressor.new.compress(nil)
      assert_equal '', Compressor.new.compress('')
    end

    private

    def email_compressor(options = {})
      Compressor.new({ :preserve_patterns => TestFixtures::EMAIL_PRESERVE_PATTERNS }.merge(options))
    end

    class RecordingCompiler
      attr_accessor :fail
      attr_reader :inputs

      def initialize(output)
        @output = output
        @inputs = []
      end

      def compress(source)
        @inputs << source
        raise ArgumentError, 'fixture compiler failure' if @fail

        @output
      end
    end
  end
end
