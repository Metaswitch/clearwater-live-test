FROM ubuntu:14.04
MAINTAINER maintainers@projectclearwater.org

# Set up Ruby and the bundler
RUN apt-get update && DEBIAN_FRONTEND=noninteractive sudo apt-get install ruby1.9.3 ruby1.9.1-dev zlib1g-dev libzmq3-dev bundler git --yes

RUN mkdir -p /home/live-test/clearwater-live-test
COPY ./ /home/live-test/clearwater-live-test/

WORKDIR "/home/live-test/clearwater-live-test"
RUN bundle install
