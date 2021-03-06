Kernel.load File.expand_path("../lib/optimism/version.rb", __FILE__)

Gem::Specification.new do |s|
	s.name = "optimism"
	s.version = Optimism::VERSION
	s.summary = "a configuration library for Ruby"
	s.description = <<-EOF
a configuration library for Ruby
	EOF

	s.author = "Guten"
	s.email = "ywzhaifei@Gmail.com"
	s.homepage = "http://github.com/GutenYe/optimism"
	s.rubyforge_project = "xx"

	s.files = `git ls-files`.split("\n")

  s.add_dependency "pd"
  s.add_dependency "json"
end
