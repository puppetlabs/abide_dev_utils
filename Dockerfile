FROM ruby:2.7.3-alpine

ARG version

RUN mkdir /extvol && \
    apk update && \
    apk add git build-base

VOLUME /extvol

WORKDIR /usr/src/app

RUN mkdir -p ./lib/abide_dev_utils/
COPY Gemfile abide_dev_utils.gemspec ./
COPY lib/abide_dev_utils/version.rb lib/abide_dev_utils
RUN bundle install

COPY . .

RUN bundle exec rake build && \
    gem install pkg/abide_dev_utils-${version}.gem

ENTRYPOINT [ "abide" ]