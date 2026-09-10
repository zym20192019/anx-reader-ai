opt_out_usage

def project_root
  File.expand_path(__dir__)
end

lane :sh_on_root do |options|
  Dir.chdir(project_root) { sh(options.fetch(:command)) }
end

lane :fetch_dependencies do
  sh_on_root(command: "flutter pub get --suppress-analytics")
end
