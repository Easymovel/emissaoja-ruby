# frozen_string_literal: true

require "rake/testtask"

# bundle exec rake test (ou só bundle exec rake). A integração com o sandbox roda só com EMISSAOJA_TEST_KEY.
Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.test_files = FileList["test/**/*_test.rb"]
  t.warning = true
end

task default: :test
