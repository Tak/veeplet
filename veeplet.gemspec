require_relative 'lib/veeplet/version'

Gem::Specification.new do |spec|
  spec.name          = "veeplet"
  spec.version       = Veeplet::VERSION
  spec.authors       = ["Levi Bard"]
  spec.email         = ["taktaktaktaktaktaktaktaktaktak@gmail.com"]

  spec.summary       = %q{Gtk3 applet for dealing with openvpn3}
  spec.homepage      = 'https://github.com/Tak/veeplet'
  spec.required_ruby_version = Gem::Requirement.new(">= 2.3.0")

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files         = [ 'lib/veeplet/credentials.rb' ].append(
    Dir.chdir(File.expand_path('..', __FILE__)) do
      `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
    end)
  spec.bindir        = "bin"
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency 'gtk3'
  spec.add_dependency 'ruby-enum'
end
