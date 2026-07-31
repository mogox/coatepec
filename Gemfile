# frozen_string_literal: true

source "https://rubygems.org"

# Specify your gem's dependencies in coatepec.gemspec
gemspec

gem "irb"
gem "rake", "~> 13.0"

gem "rspec", "~> 3.0"

gem "rubocop", "~> 1.21"
# rubocop-ast's parallel dependency dropped Ruby 3.2 support in 2.1.0;
# pin below that so `bundle lock` resolves a lockfile installable on the
# gemspec's full supported range (Ruby >= 3.2), not just this machine's Ruby.
gem "parallel", "< 2.1"
