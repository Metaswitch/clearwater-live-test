# Makefile for Clearwater infrastructure packages

# this should come first so make does the right thing by default
all: deb

DEB_COMPONENT := clearwater-live-verification
DEB_MAJOR_VERSION := 1.0${DEB_VERSION_QUALIFIER}
DEB_NAMES := clearwater-live-verification
DEB_ARCH := all

include build-infra/cw-deb.mk

deb: deb-only

clean:

.PHONY: all deb-only deb clean
