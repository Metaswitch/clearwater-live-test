FROM ubuntu:14.04
MAINTAINER maintainers@projectclearwater.org

# Set up Ruby and the bundler
RUN apt-get update && DEBIAN_FRONTEND=noninteractive sudo apt-get install ruby1.9.1 ruby1.9.1-dev --yes
#RUN source ~/.rvm/scripts/rvm && rvm autolibs enable rvm install 1.9.3 && rvm use 1.9.3

RUN mkdir /home/live-test/clearwater-live-test
COPY * > /home/live-test/clearwater-live-test/

WORKDIR "/home/live-test/clearwater-live-test"
RUN bundle install
