Redmine::Plugin.register :redmine_convert_textile_to_markdown do
  name 'Redmine Textile -> Markdown migration Plugin'
  author 'Martin Cizek, Orchitech Solutions'
  author_url 'https://orchi.tech/'
  description 'Rake task providing Textile to GFM conversion based on former Ecodev and plan.io work. Uses pandoc and heavy pre/post processing.'
  version '0.9.0'
  hidden true if respond_to? :hidden

  requires_redmine version_or_higher: '3.3.0'
end
