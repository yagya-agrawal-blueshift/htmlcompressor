# encoding: UTF-8
require 'test_helper'
require_relative 'support/email_semantics'

module HtmlCompressor
  # Current behavior for known cosmetic gaps that the pinned BSFT revision
  # (5e436a1) shares. These assertions document the output so a fix is a
  # deliberate change: update the expectation and the README when one lands.
  class TestCompressorKnownGaps < Minitest::Test
    GAP = 'Known gap: if this now fails because the behavior was fixed, update this expectation and the README.'.freeze

    def compress(html)
      Compressor.new(EmailSemantics::BSFT_OPTIONS).compress(html)
    end

    # Inside-tag passes treat `=` in a quoted value as an attribute assignment.
    def test_spaces_around_equals_inside_a_quoted_alt_are_removed
      assert_equal '<p><img alt="You + Loan=A Smart Move" src="https://example.com/a.png"></p>',
        compress('<p><img alt="You + Loan = A Smart Move" src="https://example.com/a.png"></p>'), GAP
    end

    # Inside-tag passes treat `>` in a quoted value as the end of the tag.
    def test_space_before_a_greater_than_sign_inside_a_quoted_alt_is_removed
      assert_equal '<p><img alt="Compare rates NOW>" src="https://example.com/a.png"></p>',
        compress('<p><img alt="Compare rates NOW >" src="https://example.com/a.png"></p>'), GAP
    end

    # A literal `>` in text matches the tag-end side of inter-tag minification.
    # The escaped spelling `&gt;` is not affected.
    def test_raw_greater_than_text_before_a_link_loses_its_space
      assert_equal '<p>&gt;&gt; <a href="https://example.com">Review</a></p><p>>><a href="https://example.com">Review</a></p>',
        compress('<p>&gt;&gt; <a href="https://example.com">Review</a></p><p>>> <a href="https://example.com">Review</a></p>'), GAP
    end

    # A <style> element is invisible, but it is not an inline element, so the
    # whitespace around one placed between inline links is removed. Replayed
    # templates put styles in the head or between blocks.
    def test_space_around_a_body_style_between_inline_links_is_removed
      assert_equal '<p><a href="https://example.com/1">One</a><style>.a{color:red}</style><a href="https://example.com/2">Two</a></p>',
        compress('<p><a href="https://example.com/1">One</a> <style>.a { color: red }</style> ' \
          '<a href="https://example.com/2">Two</a></p>'), GAP
    end

    # Liquid executes inside HTML comments at send time, but ordinary comments
    # are removed with their contents. Side-effect tags such as assign are lost.
    def test_liquid_inside_an_ordinary_comment_is_removed_with_the_comment
      assert_equal '<p>{{ x }}</p>', compress('<!-- {% assign x = 1 %} --><p>{{ x }}</p>'), GAP
    end

    # An unquoted value that is not a simple token is joined to the self-closing slash.
    def test_unquoted_url_before_a_self_closing_slash_gains_the_slash
      assert_equal '<img src=https://example.com/x.png/>', compress('<img src=https://example.com/x.png />'), GAP
    end

    # Outlook-closer text inside an ordinary comment ends that comment early.
    def test_outlook_closer_text_inside_an_ordinary_comment_leaks_the_rest_of_the_comment
      assert_equal 'docs --><!--[if mso]><p>mso</p><![endif]--><p>tail</p>',
        compress('<!-- see <![endif]--> docs --><!--[if mso]><p>mso</p><![endif]--><p>tail</p>'), GAP
    end
  end
end
