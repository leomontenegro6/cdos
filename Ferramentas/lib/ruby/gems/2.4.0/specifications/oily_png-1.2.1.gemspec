# -*- encoding: utf-8 -*-
# stub: oily_png 1.2.1 ruby lib ext
# stub: ext/oily_png/extconf.rb

Gem::Specification.new do |s|
  s.name = "oily_png".freeze
  s.version = "1.2.1"

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.require_paths = ["lib".freeze, "ext".freeze]
  s.authors = ["Willem van Bergen".freeze]
  s.date = "2016-09-13"
  s.description = "    This Ruby C extenstion defines a module that can be included into ChunkyPNG to improve its speed.\n".freeze
  s.email = ["willem@railsdoctors.com".freeze]
  s.extensions = ["ext/oily_png/extconf.rb".freeze]
  s.extra_rdoc_files = ["README.rdoc".freeze]
  s.files = ["README.rdoc".freeze, "ext/oily_png/extconf.rb".freeze]
  s.homepage = "http://wiki.github.com/wvanbergen/oily_png".freeze
  s.licenses = ["MIT".freeze]
  s.rdoc_options = ["--title".freeze, "oily_png".freeze, "--main".freeze, "README.rdoc".freeze, "--line-numbers".freeze, "--inline-source".freeze]
  s.rubyforge_project = "oily_png".freeze
  s.rubygems_version = "2.6.14.4".freeze
  s.summary = "Native mixin to speed up ChunkyPNG".freeze

  s.installed_by_version = "2.6.14.4" if s.respond_to? :installed_by_version

  if s.respond_to? :specification_version then
    s.specification_version = 4

    if Gem::Version.new(Gem::VERSION) >= Gem::Version.new('1.2.0') then
      s.add_runtime_dependency(%q<chunky_png>.freeze, ["~> 1.3.7"])
      s.add_development_dependency(%q<rake>.freeze, [">= 0"])
      s.add_development_dependency(%q<rake-compiler>.freeze, [">= 0"])
      s.add_development_dependency(%q<rspec>.freeze, ["~> 3"])
    else
      s.add_dependency(%q<chunky_png>.freeze, ["~> 1.3.7"])
      s.add_dependency(%q<rake>.freeze, [">= 0"])
      s.add_dependency(%q<rake-compiler>.freeze, [">= 0"])
      s.add_dependency(%q<rspec>.freeze, ["~> 3"])
    end
  else
    s.add_dependency(%q<chunky_png>.freeze, ["~> 1.3.7"])
    s.add_dependency(%q<rake>.freeze, [">= 0"])
    s.add_dependency(%q<rake-compiler>.freeze, [">= 0"])
    s.add_dependency(%q<rspec>.freeze, ["~> 3"])
  end
end
