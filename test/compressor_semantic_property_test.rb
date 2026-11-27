# encoding: UTF-8
require 'test_helper'
require_relative 'support/email_semantics'

module HtmlCompressor
  # Generated emails built from markup shapes found while replaying 16,669
  # stored templates from three accounts. Each shape is synthetic: it keeps the
  # structure that mattered, not customer content. The checks compare what an
  # HTML5 mail client sees and what Liquid renders, not output bytes.
  class TestCompressorSemanticProperties < Minitest::Test
    SHAPES = {
      # A closed comment before the style keeps it visible to HTML5 clients.
      :revealed_stylesheet =>
        '<!--[if mso]><!-- --><style>.c-r>table{border-collapse:collapse}</style><![endif]-->',
      # An editor comment ends an Outlook branch early for HTML5 clients.
      :editor_comment_in_outlook_branch =>
        '<!--[if mso | IE]><table role="presentation"><tr><td width="600"><!-- Loop through products -->' \
        "\n{% for p in products %}<a href=\"{{ p.url }}\" data-bsft-link-index=\"2\">" \
        '<img src="{{ p.image }}" alt=""></a>{% endfor %}</td></tr></table><![endif]-->',
      :block_inside_link =>
        "<table><tr><td>\n  <a href=\"{{ link }}\" style=\"color:#2e2e2d\">\n    <div>\n" \
        "      <table><tr><td>\n        {{ title }}\n      </td></tr></table>\n    </div>\n  </a>\n</td></tr></table>",
      :liquid_branch_href =>
        "<a href=\"{% if user.score == true %}\n   {{ dest_a }}\n   {% elsif user.score == false %}\n   " \
        "{{ dest_b }}\n   {% else %}\n   https://example.com/signup?id=crm\n   {% endif %}\">Sign up</a>",
      :stray_outlook_closer => "<p>Intro</p><![endif]-->\n<p>Body</p>",
      :inline_prices =>
        '<p><span class="old">{{ regular_price }}</span> <span class="new">{{ discounted_price }}</span></p>',
      :name_then_quantity => "<p><span>{{ product_name }}</span>\n <span>Quantity: {{ qty }}</span></p>",
      :multiline_image_url =>
        "<img src=\"https://preview.example.com/p?product_uid=cards_hor\n&customer_key={{ key }}&oi={{ item }}\" " \
        'width="170" alt="">',
      :footer_separators =>
        '<p><a href="https://example.com/u">Unsubscribe</a> &nbsp;|&nbsp; <a href="https://example.com/p">Preferences</a></p>',
      :legacy_font => '<p><font face="Arial">Shop</font> <font face="Arial">now</font></p>',
      :mobile_reveal =>
        '<!--[if !mso]><!--><div class="desktop_hide"><img src="{{ mobile }}" alt=""></div><!--<![endif]-->',
      :vml_button =>
        '<!--[if mso]><v:roundrect xmlns:v="urn:schemas-microsoft-com:vml" href="https://example.com/btn" ' \
        'style="height:40px;width:200px" arcsize="10%" fillcolor="#f00"><center>Buy</center></v:roundrect>' \
        '<![endif]--><!--[if !mso]><!--><a href="https://example.com/btn">Buy</a><!--<![endif]-->',
      :padded_closer => '<!--[if !mso]><!-- --><p>All clients</p><!-- <![endif]-->',
      :css_liquid_media =>
        "<style>@media (max-width: 600px) {\n {%if offers.size > 20%}\n .a { color : red }\n {%endif%}\n}</style>",
      :css_liquid_values => "<style>.h { height: {{ h | times: 0.5 }}px; color: {{ brand | default: '#FFFFFF' }} }</style>",
      :css_liquid_condition => '<style>{%- if roboto == true -%}table, td { font-family: Roboto, Arial }{%- endif -%}</style>',
      :tracking_link =>
        '<a href="https://example.com/?a=1&amp;b={{ user.id }}" data-bsft-link-index="7" target="_blank">Shop  now</a>',
      :table_cells => "<table>\n <tr>\n  <td> A </td>\n  <td> B </td>\n </tr>\n</table>",
      :mixed_inline =>
        '<p>Free <b>shipping</b> on <a href="https://example.com/x">orders</a> over <strong>$50</strong>.</p>'
    }.freeze

    JOINERS = ['', "\n", "\n    ", ' ', "\r\n\t"].freeze
    WRAPPERS = [['', ''], ['<table><tr><td>', '</td></tr></table>'], ['<div class="body">', '</div>']].freeze

    # Branch-covering contexts for the Liquid in SHAPES.
    CONTEXTS = [
      { 'offers' => Array.new(25, 1), 'user' => { 'score' => true, 'id' => 7 }, 'roboto' => true, 'h' => 240,
        'brand' => '#123456', 'products' => [{ 'url' => 'https://example.com/a', 'image' => 'https://example.com/a.png' }],
        'dest_a' => 'https://example.com/a', 'regular_price' => '$49', 'discounted_price' => '$39',
        'product_name' => 'Mug', 'qty' => 2, 'key' => 'k1', 'item' => 'i1', 'link' => 'https://example.com/l',
        'title' => 'Mug', 'mobile' => 'https://example.com/m.png' },
      { 'offers' => [1], 'user' => { 'score' => false }, 'roboto' => false, 'dest_b' => 'https://example.com/b' },
      {}
    ].freeze

    def test_compression_preserves_what_html5_clients_see
      check_shapes do |source, compressed|
        [EmailSemantics.of(source), EmailSemantics.of(compressed)]
      end
    end

    def test_compression_preserves_the_rendered_email_for_every_liquid_branch
      check_shapes do |source, compressed|
        CONTEXTS.map { |context| EmailSemantics.of(EmailSemantics.render(source, context)) }.zip(
          CONTEXTS.map { |context| EmailSemantics.of(EmailSemantics.render(compressed, context)) }
        ).transpose
      end
    end

    def test_compression_never_makes_valid_liquid_invalid
      check_shapes do |source, compressed|
        [liquid_status(source), liquid_status(compressed)]
      end
    end

    def test_recompressing_compressed_output_changes_nothing_clients_see
      check_shapes do |_source, compressed|
        [EmailSemantics.of(compressed), EmailSemantics.of(compressor.compress(compressed))]
      end
    end

    private

    def compressor
      @compressor ||= Compressor.new(EmailSemantics::BSFT_OPTIONS)
    end

    def liquid_status(html)
      Liquid::Template.parse(html)
      :valid
    rescue Liquid::SyntaxError => error
      error.message
    end

    def example(random)
      keys = Array.new(3 + random.rand(7)) { SHAPES.keys[random.rand(SHAPES.length)] }
      { :keys => keys, :joiner => JOINERS[random.rand(JOINERS.length)], :wrapper => WRAPPERS[random.rand(WRAPPERS.length)] }
    end

    # Stylesheet shapes go in the head, as in the replayed templates. A body
    # <style> between inline elements is a known gap (TestCompressorKnownGaps).
    HEAD_SHAPES = [:revealed_stylesheet, :css_liquid_media, :css_liquid_values, :css_liquid_condition].freeze

    def source_for(example)
      open, close = example[:wrapper]
      head_keys, body_keys = example[:keys].partition { |key| HEAD_SHAPES.include?(key) }
      head = head_keys.map { |key| SHAPES.fetch(key) }.join(example[:joiner])
      body = body_keys.map { |key| SHAPES.fetch(key) }.join(example[:joiner])
      "<!DOCTYPE html><html><head><meta charset=\"utf-8\">#{head}</head><body>#{open}#{body}#{close}</body></html>"
    end

    def check_shapes
      seed = Integer(ENV.fetch('HTMLCOMPRESSOR_SEED', '5014'))
      count = Integer(ENV.fetch('HTMLCOMPRESSOR_SEMANTIC_CASES', '120'))
      random = Random.new(seed)
      count.times do |index|
        failing = lambda do |candidate|
          source = source_for(candidate)
          expected, actual = yield(source, compressor.compress(source))
          expected != actual
        end
        current = example(random)
        next unless failing.call(current)

        current = minimize(current, &failing)
        source = source_for(current)
        expected, actual = yield(source, compressor.compress(source))
        assert_equal expected, actual, "seed=#{seed} case=#{index + 1} shapes=#{current[:keys].inspect} " \
          "joiner=#{current[:joiner].inspect} wrapper=#{current[:wrapper].first.inspect}"
      end
      pass
    end

    # Drop one shape at a time while the property still fails.
    def minimize(example)
      loop do
        previous = example
        index = 0
        while index < example[:keys].length && example[:keys].length > 1
          keys = example[:keys].dup
          keys.delete_at(index)
          smaller = example.merge(:keys => keys)
          if yield(smaller)
            example = smaller
          else
            index += 1
          end
        end
        return example if example.equal?(previous)
      end
    end
  end
end
