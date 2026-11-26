# Htmlcompressor
[![Build Status](https://travis-ci.org/paolochiodi/htmlcompressor.svg?branch=master)](https://travis-ci.org/paolochiodi/htmlcompressor)

## Put your html on a diet

Htmlcompressor provides tools to minify html code.
It includes
- HtmlCompressor::Compressor class which is a raw port of [google's htmlcompressor](http://code.google.com/p/htmlcompressor/)
- HtmlCompressor::Rack a rack middleware to compress html pages on the fly.
Beware that the compressor has proved to be too slow in many circunstances to be used for on the fly or real time execution. I encourage you to use it only for build-time optimisations or decrease the number of optimisations that are run at execution time.

Please note that Htmlcompressor is still in alpha version and need some additional love.

## Usage

Using the compressor class is straightforward:

```ruby
  compressor = HtmlCompressor::Compressor.new
  compressor.compress('<html><body><div id="compress_me"></div></body></html>')
```

The compressor ships with basic and safe default options that may be overwritten passing the options hash to the constructor:

```ruby
options = {
  :enabled => true,
  :remove_spaces_inside_tags => true,
  :remove_multi_spaces => true,
  :remove_comments => true,
  :remove_intertag_spaces => false,
  :remove_quotes => false,
  :compress_css => false,
  :compress_javascript => false,
  :simple_doctype => false,
  :remove_script_attributes => false,
  :remove_style_attributes => false,
  :remove_link_attributes => false,
  :remove_form_attributes => false,
  :remove_input_attributes => false,
  :remove_javascript_protocol => false,
  :remove_http_protocol => false,
  :remove_https_protocol => false,
  :preserve_line_breaks => false,
  :simple_boolean_attributes => false,
  :compress_js_templates => false
}
```

With `remove_intertag_spaces` enabled, whitespace between recognized inline
elements is retained so adjacent words do not run together. Stylesheets that
match a configured preserve pattern are kept out of the CSS minifier.

Htmlcompressor also ships a rack middleware that can be used with rails, sinatra or rack.

**However keep in mind that compression is slow (especially when also compressing javascript or css) and can negatively impact the performance of your website. Take your measurements and adopt a different strategy if necessary**

Using rack middleware (in rails) is as easy as:

```ruby
config.middleware.use HtmlCompressor::Rack, options
```

And in sinatra:

```ruby
use HtmlCompressor::Rack, options
```

The middleware uses a little more aggressive options by default:

```ruby
options = {
  :enabled => true,
  :remove_multi_spaces => true,
  :remove_comments => true,
  :remove_intertag_spaces => false,
  :remove_quotes => true,
  :compress_css => false,
  :compress_javascript => false,
  :simple_doctype => false,
  :remove_script_attributes => true,
  :remove_style_attributes => true,
  :remove_link_attributes => true,
  :remove_form_attributes => false,
  :remove_input_attributes => true,
  :remove_javascript_protocol => true,
  :remove_http_protocol => false,
  :remove_https_protocol => false,
  :preserve_line_breaks => false,
  :simple_boolean_attributes => true
}
```

Rails 2.3 users may need to add
```ruby
require 'htmlcompressor'
```

## Javascript template compression

You can compress javascript templates that are present in the html.
Setting the `:compress_js_templates` options to `true` will by default compress the content of script tags marked with `type="text/x-jquery-tmpl"`.
For compressing other types of templates, you can pass a string (or an array of strings) containing the type: `:compress_js_templates => ['text/html']`.
Please note that activating template compression will disable the removal of quotes from attributes values, as this could lead to unexpected errors with compiled templates.


## Custom preservation rules

If you need to define custom preservation rules, you can list regular expressions in the `preserve_patterns` option. For example, to preserve PHP blocks you might want to define:

```ruby
options = {
  :preserve_patterns => [/<\?php.*?\?>/im]
}
```

## CSS and JavaScript Compression

By default CSS/JS compression is disabled.
In order to minify in page javascript and css, you need to supply a compressor in the options hash.
A compressor can be `:yui` or `:closure` or any object that responds to `:compress`. E.g.: `compressed = compressor.compress(source)`

```ruby
class MyCompressor

  def compress(source)
    return 'minified'
  end

end

options = {
  :compress_css => true,
  :css_compressor => MyCompressor.new,
  :compress_javascript => true,
  :javascript_compressor => MyCompressor.new
}
```

Please note that in order to use yui or closure compilers you need to manually add them to the Gemfile

```ruby
gem 'yui-compressor'

...

options = {
  :compress_javascript => true,
  :javascript_compressor => :yui,
  :compress_css => true,
  :css_compressor => :yui
}
```

```ruby
gem 'closure-compiler'

...

options = {
  :compress_javascript => true,
  :javascript_compressor => :closure
}
```

## Statistics

As of now the statistic framework hasn't been ported. Refer to original [htmlcompressor documentation](http://code.google.com/p/htmlcompressor/) for statistics on minified pages.

## Compatibility tests

Run the normal suite with `bundle exec rake test`. The property suite uses
the existing Minitest dependency and is runnable on its own:

```sh
ruby -Ilib:test test/compressor_property_test.rb
HTMLCOMPRESSOR_SEED=4975 HTMLCOMPRESSOR_CASES=1000 ruby -Ilib:test test/compressor_property_test.rb
```

The default seed is `5014`, with 240 inputs per property. Generated inputs
combine supported email fragments. The tests check removal and retention of
comments, exact output for protected fragments, reuse of a compressor, and
repeat compression of stable inputs. On failure, the suite prints the seed,
case number, and a smaller input obtained by removing unrelated fragments.
Keep a named regression when a generated case identifies a new defect.

The compatibility fixtures use this gem's options and expected output.
They take behavioral cases from these upstream suites:

| Reference | Cases adapted or checked |
| --- | --- |
| [Java HtmlCompressor](https://github.com/serg472/htmlcompressor/blob/master/src/test/java/com/googlecode/htmlcompressor/compressor/HtmlCompressorTest.java) and [upstream Ruby htmlcompressor](https://github.com/paolochiodi/htmlcompressor/blob/master/test/compressor_test.rb) | Preserve-pattern ordering, skip blocks, and CSS/JavaScript compressor calls |
| [html-minifier-terser](https://github.com/terser/html-minifier-terser/blob/master/tests/minifier.spec.js) and [htmlnano](https://github.com/posthtml/htmlnano/blob/master/test/modules/removeComments.ts) | Revealed conditional comments, template fragments, inline separators, and comment-shaped literal text |
| [Go minify](https://github.com/tdewolff/minify/blob/master/html/html_test.go) and [Rust minify-html](https://github.com/wilsonzlin/minify-html/blob/master/minify-html/src/tests/mod.rs) | Outlook-specific fragments, SSI, raw-text bodies, and opaque template syntax |
| [Python htmlmin](https://github.com/mankyd/htmlmin/blob/master/htmlmin/tests/tests.py) and [PHP HtmlMin](https://github.com/voku/HtmlMin/blob/master/tests/HtmlMinTest.php) | Comment and whitespace options, Unicode spaces, JSON scripts, and protected content inside templates |
| [.NET WebMarkupMin](https://github.com/Taritsyn/WebMarkupMin/tree/master/test/WebMarkupMin.Tests/Html/Common/Minification) | Comment delimiters inside CSS and JavaScript, CDATA, and alternating Outlook forms |

The email fixtures cover transactional and recommendation messages with
preheaders, responsive CSS, Outlook fallbacks, tracking URLs, Liquid, and
right-to-left text. The comment regressions also cover quoted attribute
values, comment delimiters next to character references, and preformatted
content. If the source contains a literal internal placeholder, the
compressor returns the source unchanged to prevent incorrect substitution.

## License

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

  http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Added some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
