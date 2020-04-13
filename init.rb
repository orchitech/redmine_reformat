Redmine::Plugin.register :redmine_reformat do
  name 'Redmine richtext conversion plugin'
  author 'Martin Cizek, Orchitech Solutions'
  author_url 'https://orchi.tech/'
  description 'Rake task providing configurable format conversion. Contains portions of Ecodev and plan.io work.'
  version '0.3.1'
  hidden true if respond_to? :hidden

  requires_redmine version_or_higher: '3.3.0'
end
