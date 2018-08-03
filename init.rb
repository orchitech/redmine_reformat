Redmine::Plugin.register :redmine_convert_textile_to_markdown do
  name 'Redmine Textile -> Markdown migration Plugin'
  author 'Jens Krämer, Planio GmbH'
  author_url 'https://plan.io/'
  description ''
  version '0.1.0'
  hidden true if respond_to? :hidden

  requires_redmine version_or_higher: '3.3.0'
end

