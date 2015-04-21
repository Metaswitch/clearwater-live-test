#!/bin/bash

export DEB_COMPONENT=clearwater-live-verification
export DEB_MAJOR_VERSION=1.0
export DEB_NAMES=clearwater-live-verification

make -f build-infra/cw-deb.mk
