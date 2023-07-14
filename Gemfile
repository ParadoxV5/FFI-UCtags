# frozen_string_literal: true
source 'https://rubygems.org'
gemspec

# Development Apps
group :development do
  group :type_check do
    gem 'rbs', '~> 3.1.0', require: false
  end
  group :documentation do
    gem 'yard', '~> 0.9.0', require: false
    gem 'commonmarker', '~> 0.23.0', require: false
  end
  group :test do
    gem 'minitest', '5.18.2',
      git: 'https://github.com/ParadoxV5/minitest.git',
      branch: '958-optional-default-task'
      # https://github.com/minitest/minitest/pull/959
  end
end
