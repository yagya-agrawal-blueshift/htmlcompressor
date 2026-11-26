# encoding: UTF-8
require 'test_helper'

module HtmlCompressor
  class TestCompressorEmail < Minitest::Test
    def test_bee_confirmation_preserves_preheader_tracking_links_and_both_clients
      source = fixture('bee_order_confirmation.html')
      output = compressor.compress(source)

      assert_equal compressor.compress(source.sub(/<!-- editor:.*?-->/, '')), output
      assert_equal liquid_tags(source), liquid_tags(output)
      assert_ordered output,
        '<span id="bsft-preheader"',
        '<!--[if mso]><table role="presentation" width="600" align="center">',
        '<!--[if mso]><v:roundrect href="{{ order.tracking_url | escape }}"',
        'utm_source=email&amp;utm_medium=transactional" data-bsft-link-index="1"',
        '<style>.tracking-link { color: #1b1b1b; }</style>',
        '<!--<![endif]-->',
        'data-bsft-link-index="2"',
        '<!--[if mso]></td></tr></table><![endif]-->',
        'data-bsft-link-index="3"'
      assert_includes output, '@media (prefers-color-scheme: dark)'
      assert_includes output, '<!-- End -->'
    end

    def test_classic_digest_preserves_recommendations_fallback_and_rtl_text
      source = fixture('classic_product_digest.html')
      output = compressor.compress(source)

      assert_equal compressor.compress(source.sub(/<!-- editor:.*?-->/, '')), output
      assert_equal liquid_tags(source), liquid_tags(output)
      assert_includes output, '<html dir="rtl" lang="ar">'
      assert_includes output, 'أهلاً، {{ heading | escape }} 👋'
      assert_ordered output,
        '{% if products.size > 0 %}', '{% for product in products %}',
        'source=digest&amp;position={{ forloop.index }}',
        '{% if product.sale %}', '{% endfor %}', 'We are still finding your picks.',
        '<!--[if mso]><table role="presentation" width="540">',
        'data-bsft-link-index="2"', 'data-bsft-link-index="3"'
    end

    def test_multiple_expanded_shared_fragments_do_not_absorb_the_next_section
      section = '<table role="presentation"><tr><td>{% if show %}<a href="{{ url }}">Offer</a>{% endif %}</td></tr></table>'
      expanded = '<!-- Header asset: uses <style> -->' + section +
        '<!-- Nested button asset: uses <![if mso]> -->' +
        '<!--[if mso]><p>Client-only</p><![endif]-->' + section +
        '<style>.button { font-weight: bold; }</style><p>Footer</p>'
      expected = section + '<!--[if mso]><p>Client-only</p><![endif]-->' + section +
        '<style>.button { font-weight: bold; }</style><p>Footer</p>'

      assert_equal expected, compressor.compress(expanded)
    end

    def test_repeated_rows_keep_every_cta_and_footer_at_large_message_size
      row = '<tr><td><a href="{{ product.url }}?utm_source=digest&amp;position={{ forloop.index }}">View product</a>' \
        '<img src="{{ product.image_url }}" alt="Product" width="120"></td></tr>'
      rows = row * 675
      before = '<table role="presentation">'
      after = '</table><style>.item { display: block; }</style>' \
        '<p><a href="{{ unsubscribe_url }}">Unsubscribe</a></p>'
      expected = before + rows + after
      input = before + '<!-- editor note about <style> position -->' + rows + after

      assert_operator input.bytesize, :>, 102 * 1024
      assert_equal expected, compressor.compress(input)
    end

    def test_customer_facing_title_with_literal_comment_syntax_remains_unchanged
      title = 'title="Edit the &quot;delivery note&quot; <!-- internal marker --> safely"'
      action = "<a #{title} href=\"{{ manage_url }}\" data-bsft-link-index=\"4\">Update delivery</a>"
      source = '<p>Change your details.</p>' + action + '<!-- Editorial note --><p>Thank you.</p>'

      assert_equal '<p>Change your details.</p>' + action + '<p>Thank you.</p>',
        compressor.compress(source)
    end

    def test_editor_comment_cannot_supply_the_closer_of_a_revealed_email_branch
      open = '<!--[if !mso]><!-->'
      finish = '<a href="{{ signup_url }}" data-bsft-link-index="1">Join</a><!--<![endif]-->'
      note = '<!-- Editor note: the fallback ends with <![endif]-->'

      assert_equal open + '<p>Signup</p>' + finish,
        compressor.compress(open + '<p>Signup</p>' + note + finish)
    end

    private

    def fixture(name)
      File.read(File.join(File.dirname(__FILE__), 'resources', 'html', name), :encoding => 'UTF-8')
    end

    def compressor
      Compressor.new(:remove_intertag_spaces => true, :preserve_patterns => TestFixtures::EMAIL_PRESERVE_PATTERNS)
    end

    def liquid_tags(html)
      html.scan(/\{%.*?%\}|\{\{.*?\}\}/m)
    end

    def assert_ordered(output, *fragments)
      offset = 0
      fragments.each do |fragment|
        position = output.index(fragment, offset)
        assert position, "expected #{fragment.inspect} after offset #{offset}"
        offset = position + fragment.length
      end
    end
  end
end
