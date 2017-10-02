FROM ubuntu:14.04
MAINTAINER maintainers@projectclearwater.org

# Set up Ruby and the bundler
RUN apt-get update && DEBIAN_FRONTEND=noninteractive sudo apt-get install build-essential bundler git curl gnupg2 --yes
RUN gpg2 --recv-keys 409B6B1796C275462A1703113804BB82D39DC0E3
RUN curl -L https://get.rvm.io | bash -s stable
RUN source ~/.rvm/scripts/rvm && rvm autolibs enable rvm install 1.9.3 && rvm use 1.9.3

RUN mkdir /home/live-test/clearwater-live-test
COPY . > /home/live-test/clearwater-live-test/

WORKDIR "/home/live-test/clearwater-live-test"
RUN bundle install
