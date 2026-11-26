# encoding: UTF-8
require 'test_helper'

module HtmlCompressor
  class TestCompressorProperties < Minitest::Test
    RAW_CONTENT = {
      'pre' => " first\t second\n",
      'textarea' => "row one\r\n  <b>not HTML here</b>",
      'script' => 'var payload = "a  >  b";',
      'style' => '.copy::before { content: "a  >  b"; }'
    }.freeze

    SKIP_DIRECTIVE = '<!-- {{{ --><p data-source="raw">  untouched  </p><!-- }}} -->'.freeze

    # The expected output of each fragment is independent of the compressor.
    FRAGMENTS = [
      ['<p lang="fr">Café  du monde &amp; thé</p>', '<p lang="fr">Café du monde &amp; thé</p>'],
      ['<a  href = "{{ product.url }}" data-bsft-link-index="10">Shop now</a>',
        '<a href="{{ product.url }}" data-bsft-link-index="10">Shop now</a>'],
      ['{% if available %}<span>{{ title }}</span>{% else %}<em>Sold out</em>{% endif %}'] * 2,
      ['<script type="application/json">{"text":"two  spaces","number":1}</script>'] * 2,
      ['<table role="presentation"><tr><td>Order  details</td></tr></table>',
        '<table role="presentation"><tr><td>Order details</td></tr></table>'],
      ['<!--#include file="email  fragment.html" -->'] * 2,
      [SKIP_DIRECTIVE] * 2,
      ["<pre>Before\n#{SKIP_DIRECTIVE}\nAfter</pre>"] * 2,
      ["<textarea>Before\r\n#{SKIP_DIRECTIVE}\r\nAfter</textarea>"] * 2
    ].freeze

    OUTLOOK = [
      ['', ''],
      ['<!--[if mso]>', '<![endif]-->'],
      ['<!--[if !mso]><!-->', '<!--<![endif]-->'],
      ['<!--[if !mso]><!---->', '<!-- <![endif]-->'],
      ['<!--[if !mso]><!-- -->', "<!--\t\n<![ENDIF]-->"]
    ].freeze

    COMMENT_TARGETS = RAW_CONTENT.keys + ['conditional', 'event'].freeze

    def test_removing_an_ordinary_comment_preserves_the_rest_of_the_message
      check_property(method(:comment_example)) do |example|
        compressor = Compressor.new(example[:options])
        source = build_example(example, '')
        annotated = build_example(example, example[:comment])
        [compressor.compress(source), compressor.compress(annotated)]
      end
    end

    def test_keeping_comments_without_whitespace_transforms_preserves_every_byte
      check_property(method(:retained_comment_example)) do |example|
        source = build_example(example, example[:comment])
        [source, Compressor.new(example[:options]).compress(source)]
      end
    end

    def test_outlook_comment_boundaries_keep_fallbacks_visible
      check_property(method(:outlook_boundary_example)) do |example|
        source = build_example(example, example[:comment])
        expected_comment = example[:options][:remove_comments] ? '' : example[:comment]
        expected = build_example(example, expected_comment)
        [expected, Compressor.new(example[:options]).compress(source)]
      end
    end

    def test_protected_and_template_fragments_preserve_exact_bytes_and_order
      check_property(method(:fragment_example)) do |example|
        source = example[:fragments].map(&:first).join
        expected = example[:fragments].map(&:last).join
        [expected, Compressor.new(example[:options]).compress(source)]
      end
    end

    def test_stable_fragments_are_idempotent_and_state_does_not_leak_between_calls
      check_property(method(:fragment_example)) do |example|
        source = example[:fragments].map(&:first).join
        compressor = Compressor.new(example[:options])
        first = compressor.compress(source)
        compressor.compress('<pre>another    message</pre><p>{{ extra }}</p>')
        [[first, first], [compressor.compress(source), compressor.compress(first)]]
      end
    end

    private

    def comment_example(random, iteration)
      target = COMMENT_TARGETS[iteration % COMMENT_TARGETS.length]
      # Hidden conditionals are separate fragments. Nesting an ordinary HTML
      # comment in their body can terminate the outer comment in other clients.
      wrapper = OUTLOOK[iteration / COMMENT_TARGETS.length % 2 == 0 ? 0 : 2]
      opener, after = comment_target(target, random)
      after = '<!--[if mso]><p>Client-specific</p><![endif]-->' if target == 'conditional' && wrapper.first.empty?
      comment = random.rand(2).zero? ? "<!-- notes #{opener} -->" : "<!--\n notes #{opener}\r\n-->"
      {
        :fragments => ['<p>Before café</p>'],
        :after => ['{% if live %}<em>{{ label }}</em>{% endif %}', after, '<p>After</p>'],
        :wrapper => wrapper,
        :comment => comment,
        :options => email_options.merge(
          :remove_intertag_spaces => random.rand(2).zero?,
          :remove_spaces_inside_tags => random.rand(2).zero?,
          :preserve_line_breaks => random.rand(2).zero?
        )
      }
    end

    def comment_target(target, random)
      case target
      when 'conditional'
        opener = ['<![if !mso]>', '<![IF (gte mso 9)]>'][random.rand(2)]
        [opener, '<p>Conditional example</p>']
      when 'event'
        quote = ['"', "'"][random.rand(2)]
        ["OnMouseOver = #{quote}", "<span title=#{quote}keep me#{quote}>Offer</span>"]
      else
        tag = random.rand(2).zero? ? target : target.upcase
        ["<#{tag} data-sample=\"example\">", "<#{target}>#{RAW_CONTENT.fetch(target)}</#{target}>" * 2]
      end
    end

    def retained_comment_example(random, iteration)
      example = comment_example(random, iteration)
      example[:options].merge!(
        :remove_comments => false, :remove_intertag_spaces => false,
        :remove_multi_spaces => false, :remove_spaces_inside_tags => false,
        :preserve_line_breaks => false
      )
      example
    end

    def outlook_boundary_example(random, iteration)
      terminator = ['-->', '--!>'][iteration % 2]
      opening = '<!--[if (gte mso 9)|(IE)]><table><tr><td>'
      opening += "<!-- editor handoff #{terminator}"
      closing = '</td></tr></table>'
      closing += '<![endif]-->' if (iteration / 2).even?
      fallback = [
        '<a href="{{ details_url }}" data-bsft-link-index="56">Détails</a>',
        '{% if available %}<p>{{ title }}</p>{% endif %}',
        '<style>.offer{color:red}</style>'
      ]
      first, *rest = fallback.rotate(iteration % fallback.length)
      {
        :wrapper => [opening, closing],
        :fragments => [first],
        :comment => "<!-- editor note mentions <style> #{terminator}",
        :after => rest,
        :options => email_options.merge(
          :remove_comments => (iteration / 4).even?,
          :remove_intertag_spaces => random.rand(2).zero?
        )
      }
    end

    def fragment_example(random, _iteration)
      remove_intertag_spaces = random.rand(2).zero?
      table = ['<table> <tr><td>Variant</td></tr> </table>',
               remove_intertag_spaces ? '<table><tr><td>Variant</td></tr></table>' :
                                         '<table> <tr><td>Variant</td></tr> </table>']
      stable = FRAGMENTS + OUTLOOK.drop(1).map do |open, close|
        ["#{open}<p>Client-specific</p>#{close}"] * 2
      end
      stable << table
      stable += RAW_CONTENT.map { |tag, body| ["<#{tag}>#{body}</#{tag}>"] * 2 }
      {
        :fragments => Array.new(3 + random.rand(7)) { stable[random.rand(stable.length)] },
        :options => email_options.merge(:remove_intertag_spaces => remove_intertag_spaces)
      }
    end

    def email_options
      { :preserve_patterns => TestFixtures::EMAIL_PRESERVE_PATTERNS + [Compressor::SERVER_SIDE_INCLUDE_PATTERN] }
    end

    def build_example(example, comment)
      open, close = example[:wrapper]
      open + example[:fragments].join + comment + example[:after].join + close
    end

    def check_property(generator, &compare)
      seed = Integer(ENV.fetch('HTMLCOMPRESSOR_SEED', '5014'))
      count = Integer(ENV.fetch('HTMLCOMPRESSOR_CASES', '240'))
      raise ArgumentError, 'HTMLCOMPRESSOR_CASES must be positive' unless count > 0

      random = Random.new(seed)
      count.times do |index|
        example = generator.call(random, index)
        expected, actual, failure = compare_example(example, &compare)
        if failure
          example = minimize(example) { |smaller| compare_example(smaller, &compare).last == failure }
          expected, actual = compare_example(example, &compare)
          assert_equal expected, actual, "seed=#{seed} case=#{index + 1} minimized=#{example.inspect}"
        else
          assert_equal expected, actual
        end
      end
    end

    def compare_example(example)
      expected, actual = yield(example)
      [expected, actual, expected == actual ? nil : :wrong_output]
    rescue StandardError => error
      ['compression succeeds', "#{error.class}: #{error.message}", error.class]
    end

    # Remove one fragment at a time while the same property still fails.
    # The insertion boundary and options stay fixed during shrinking.
    def minimize(example)
      loop do
        previous = example
        [:fragments, :after].each do |key|
          next unless example[key]

          index = 0
          while index < example[key].length
            fragments = example[key].dup
            fragments.delete_at(index)
            smaller = example.merge(key => fragments)
            if yield(smaller)
              example = smaller
            else
              index += 1
            end
          end
        end
        return example if example.equal?(previous)
      end
    end
  end
end
