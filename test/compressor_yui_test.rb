require 'test_helper'

module HtmlCompressor

  class TestCompressor < Minitest::Test

    def test_compress_javascript_yui
      source = read_resource("testCompressJavaScript.html");
      result = read_resource("testCompressJavaScriptYuiResult.html");

      compressor = Compressor.new(
        :compress_javascript => true,
        :javascript_compressor => :yui,
        :remove_intertag_spaces => true,
        :compress_js_templates => true
      )

      assert_equal result, compressor.compress(source)
    end

    def test_compress_css
      source = read_resource("testCompressCss.html")
      result = read_resource("testCompressCssResult.html")

      compressor = Compressor.new(
        :compress_css => true,
        :css_compressor => :yui,
        :remove_intertag_spaces => true
      )

      assert_equal result, compressor.compress(source)
    end

    def test_compress_css_with_comment_boundaries_and_preserved_template_syntax
      source = '<!-- docs mention <style> and <![if mso]> -->' \
        '<div>before</div>' \
        '{% if user.enabled %}<div>keep</div>{% endif %}' \
        '<style>.button { color: red; }</style>' \
        '<!--[if mso]><table><tr><td>mso</td></tr></table><![endif]-->' \
        '<!-- later comment -->' \
        '<div>after</div>'
      result = '<div>before</div>' \
        '{% if user.enabled %}<div>keep</div>{% endif %}' \
        '<style>.button{color:red}</style>' \
        '<!--[if mso]><table><tr><td>mso</td></tr></table><![endif]-->' \
        '<div>after</div>'
      compressor = Compressor.new(
        :compress_css => true,
        :css_compressor => :yui,
        :remove_intertag_spaces => true,
        :preserve_patterns => TestFixtures::EMAIL_PRESERVE_PATTERNS
      )

      assert_equal result, compressor.compress(source)
    end

    def test_compress_responsive_and_dark_mode_css_in_order_confirmation_email
      source = read_resource('bee_order_confirmation.html')
      compressor = Compressor.new(
        :compress_css => true,
        :css_compressor => :yui,
        :remove_intertag_spaces => true,
        :preserve_patterns => TestFixtures::EMAIL_PRESERVE_PATTERNS
      )

      output = compressor.compress(source)

      assert_includes output, '@media only screen and (max-width:600px){.stack{display:block !important;width:100% !important}}'
      assert_match(/@media\s*\(prefers-color-scheme:\s*dark\)\{\.surface\{background-color:#161616 !important\}\}/, output)
      assert_includes output, '<style>.tracking-link{color:#1b1b1b}</style>'
      assert_includes output, 'data-bsft-link-index="1">Track your order</a>'
      assert_includes output, '{% else %}'
      assert_includes output, '{% endif %}'
      refute_includes output, '<!-- editor:'
    end

    def test_yui_minifies_utf8_css_next_to_a_preserved_style_with_liquid_and_a_nested_script
      dynamic_style = '<style>.header { height: {{ height | times: 0.5 }}px; } /* ' \
        '<script type="application/ld+json">{"name":"Preserve  spaces"}</script> */</style>'
      source = '<p>Crème</p><style>.copy::before { content: "Café"; }</style>' + dynamic_style
      compressor = Compressor.new(
        :compress_css => true,
        :css_compressor => :yui,
        :remove_intertag_spaces => true,
        :preserve_patterns => TestFixtures::EMAIL_PRESERVE_PATTERNS
      )

      assert_equal '<p>Crème</p><style>.copy::before{content:"Café"}</style>' + dynamic_style,
        compressor.compress(source)
    end

  end

end
