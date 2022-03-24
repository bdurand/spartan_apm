# Spartan APM

[![Continuous Integration](https://github.com/bdurand/spartan_apm/actions/workflows/continuous_integration.yml/badge.svg)](https://github.com/bdurand/spartan_apm/actions/workflows/continuous_integration.yml)
[![Ruby Style Guide](https://img.shields.io/badge/code_style-standard-brightgreen.svg)](https://github.com/testdouble/standard)

This gem provides a simple yet powerful application performance monitoring tool for Ruby applications.

It provides a simple set of top line features like you'd find in a more robust service like DataDog, Scout, or NewRelic to give you insight into the performance of various aspects of you application. It does not, by any means, serve as a full replacement for any of those paid services. If your application performance is critical to your business, you should absolutely be paying for such a service or building something more complex from available open source tools.

However, if you need something simple and free that just works out of the box, then SpartanAPM might be for you. SpartanAPM might be a good fit for you if:

1. you're just starting up a new application and don't know if it's going to be worth paying for a service
2. your side project application is starting to hit it big time with traffic, but doesn't generate enough revenue to justify an expensive tool yet
3. your full featured APM charges a per seat license but you want to expose some performance information to your entire organization; for instance if you want your P1 support personell to have access to current performance, but only developers need full access to all your tools
4. you want to include performance data in custom monitors from within your application

## The Tool

## Instrumentation

## Performance

## Installation

_TODO: this tool is currently under construction and has not been published to rubygems.org yet. You can still install directly from GitHub._

Add this line to your application's Gemfile:

```ruby
gem 'spartan_apm'
```

And then execute:
```bash
$ bundle
```

Or install it yourself as:
```bash
$ gem install spartan_apm
```

### Configuration

### Rails Applications

## Contributing

Open a pull request on GitHub.

Please use the [standardrb](https://github.com/testdouble/standard) syntax and lint your code with `standardrb --fix` before submitting.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
