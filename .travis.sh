#/bin/bash
set -e

if [[ ! "$TESTSPACE" = /* ]] ||
   [[ ! "$PATH_TO_REDMINE" = /* ]] ||
   [[ ! "$REDMINE_VER" = * ]] ||
   [[ ! "$NAME_OF_PLUGIN" = * ]] ||
   [[ ! "$PATH_TO_PLUGIN" = /* ]];
then
  echo "You should set"\
       " TESTSPACE, PATH_TO_REDMINE, REDMINE_VER"\
       " NAME_OF_PLUGIN, PATH_TO_PLUGIN"\
       " environment variables"
  echo "You set:"\
       "$TESTSPACE"\
       "$PATH_TO_REDMINE"\
       "$REDMINE_VER"\
       "$NAME_OF_PLUGIN"\
       "$PATH_TO_PLUGIN"
  exit 1;
fi

export RAILS_ENV=test
export REDMINE_GIT_REPO=git://github.com/redmine/redmine.git
export REDMINE_GIT_TAG=$REDMINE_VER
export BUNDLE_GEMFILE=$PATH_TO_REDMINE/Gemfile

# checkout redmine
git clone $REDMINE_GIT_REPO $PATH_TO_REDMINE
cd $PATH_TO_REDMINE
if [ ! "$REDMINE_GIT_TAG" = "master" ]; then
  git checkout tags/$REDMINE_GIT_TAG
fi

cp -rp $PATH_TO_PLUGIN plugins/$NAME_OF_PLUGIN

mv $TESTSPACE/database.yml.travis config/database.yml

# install gems
bundle install

# run redmine database migrations
bundle exec rake db:migrate > /dev/null

# run plugin database migrations
bundle exec rake redmine:plugins:migrate

# run tests
bundle exec rake redmine:plugins:test NAME=$NAME_OF_PLUGIN
